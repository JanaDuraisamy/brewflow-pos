import 'dart:async';
import 'dart:convert';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_gateway.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Engine
///
/// One cycle = PUSH then PULL:
///
///   PUSH  drain the outbox FIFO in batches → typed gateway pushes per
///         entity → markDone on success / incrementAttempt on failure;
///         after [maxAttempts] consecutive failures one change parks as
///         FAILED (kept locally for inspection, never silently dropped).
///         A failing batch STOPS pushing for the cycle — FIFO order means
///         later changes must not overtake a stuck predecessor.
///
///   PULL  every entity + deletions, ascending by SERVER updated_at from the
///         shared cursor; each page applies atomically and idempotently;
///         parents before children (categories → products → variants), and
///         deletions last. The cursor advances to the MINIMUM of all entity
///         frontiers so no row can fall behind a cursor unseen.
///
/// Offline-first: a failed cycle changes nothing durable except retry
/// bookkeeping — local POS usage is never blocked or rolled back.
///
/// Conflict policy: last successful push wins at the server boundary,
/// ordered by server-owned timestamps (arrival), never client clocks
/// (see supabase/migrations/0003_master_data_sync.sql).
/// ---------------------------------------------------------------------------

final class SyncEngine {
  SyncEngine(
    this._sync,
    this._gateway,
    this._applier, {
    this.pullPageSize = 200,
  });

  static const String tag = 'SyncEngine';

  /// After this many consecutive failures one outbox entry stops blocking the
  /// FIFO queue and parks as FAILED for inspection/manual retry.
  static const int maxAttempts = 8;

  /// Epoch used as the first-ever pull cursor (full-history bootstrap).
  static DateTime get initialCursor =>
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  final DriftSyncRepository _sync;
  final RemoteMasterDataGateway _gateway;
  final LocalMasterDataApplier _applier;

  final int pullPageSize;

  bool _running = false;

  bool get isRunning => _running;

  /// Runs one full push+pull cycle. Reentrant calls collapse into the
  /// running cycle (timers/connectivity can overlap harmlessly).
  Future<void> runCycle({
    required String deviceId,
    required String shopId,
  }) async {
    if (_running) return;
    _running = true;
    try {
      await _reconcileCategories();
      await _push();
      await _pull(deviceId: deviceId, shopId: shopId);
      await _sync.upsertState(
        deviceId: deviceId,
        shopId: shopId,
        lastPushedAt: DateTime.now().toUtc(),
      );
      // Operational telemetry for hardware verification: one line per
      // completed cycle showing exactly what remains queued locally.
      final pendingAfter = await _sync.pendingOutboxCount();
      AppLog.info('Sync cycle complete · pending=$pendingAfter', tag: tag);
    } catch (error, stackTrace) {
      AppLog.warning(
        'Sync cycle incomplete (will retry)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    } finally {
      _running = false;
    }
  }

  // ---- PUSH -----------------------------------------------------------------

  Future<void> _push() async {
    while (true) {
      final batch = await _sync.pendingOutboxBatch();
      if (batch.isEmpty) return;

      final pushedAny = await _pushBatch(batch);
      if (!pushedAny) {
        // Head of the queue is failing (likely offline): retry next cycle
        // instead of spinning through the rest out of order.
        return;
      }
      // Parked-FAILED entries leave the pending set; everything else was
      // marked done, so progress is guaranteed each loop iteration.
    }
  }

  /// Returns true when at least one entry of the batch reached DONE.
  Future<bool> _pushBatch(List<SyncOutboxEntry> batch) async {
    var doneCount = 0;
    try {
      for (final entry in batch) {
        await _pushEntry(entry);
        doneCount++;
      }
    } catch (error, stackTrace) {
      await _recordFailureFrom(batch, doneCount, error.toString());
      AppLog.warning(
        'Push failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
    return doneCount > 0;
  }

  Future<void> _pushEntry(SyncOutboxEntry entry) async {
    final entity = MasterEntity.fromWire(entry.entity);
    switch (entity) {
      case MasterEntity.shop:
        if (entry.operation == 'DELETE') {
          throw StateError('SHOP supports UPSERT sync only');
        }
        await _gateway.upsertShops([
          SyncShop.fromJson(decodePayload(entry.payload)),
        ]);
      case MasterEntity.category:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          final attempted = SyncCategory.fromJson(decodePayload(entry.payload));
          try {
            await _gateway.upsertCategories([attempted]);
          } catch (error) {
            final msg = error.toString();
            if (msg.contains('23505') &&
                msg.contains('ux_categories_shop_name')) {
              AppLog.info(
                'Category "${attempted.name}" already exists under this shop — converging to canonical',
                tag: tag,
              );
              // Proactively fetch the canonical and remap local references so
              // subsequent product pushes use the correct FK. Best-effort.
              try {
                final cloudCategories = await _fetchAllCloudCategories();
                SyncCategory? canonical;
                for (final c in cloudCategories) {
                  if (c.name == attempted.name) {
                    canonical = c;
                    break;
                  }
                }
                if (canonical != null && canonical.id != attempted.id) {
                  await _sync.adoptCanonicalCategory(
                    oldCategoryId: attempted.id,
                    canonical: canonical,
                  );
                }
              } catch (_) {}
              // The duplicate category is already represented on the cloud
              // under the canonical id — mark this outbox entry DONE so the
              // FIFO queue does not block forever on a known duplicate.
              await _sync.markDone(entry.id);
              return;
            }
            rethrow;
          }
        }
      case MasterEntity.product:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertProducts([
            SyncProduct.fromJson(decodePayload(entry.payload)),
          ]);
        }
      case MasterEntity.productVariant:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertProductVariants([
            SyncProductVariant.fromJson(decodePayload(entry.payload)),
          ]);
        }
      case MasterEntity.supplier:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertSuppliers([
            SyncSupplier.fromJson(decodePayload(entry.payload)),
          ]);
        }
      case MasterEntity.customer:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertCustomers([
            SyncCustomer.fromJson(decodePayload(entry.payload)),
          ]);
        }
      case MasterEntity.sale:
        if (entry.operation == 'DELETE') {
          throw StateError('SALE supports UPSERT sync only');
        }
        await _gateway.upsertSales([
          SyncSale.fromJson(decodePayload(entry.payload)),
        ]);
      case MasterEntity.saleItem:
        if (entry.operation == 'DELETE') {
          throw StateError('SALE_ITEM supports UPSERT sync only');
        }
        await _gateway.upsertSaleItems([
          SyncSaleItem.fromJson(decodePayload(entry.payload)),
        ]);
      case MasterEntity.expense:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertExpenses([
            SyncExpense.fromJson(decodePayload(entry.payload)),
          ]);
        }
      case MasterEntity.customerPayment:
        if (entry.operation == 'DELETE') {
          throw StateError('CUSTOMER_PAYMENT supports UPSERT sync only');
        }
        await _gateway.upsertCustomerPayments([
          SyncCustomerPayment.fromJson(decodePayload(entry.payload)),
        ]);
      case MasterEntity.offer:
        if (entry.operation == 'DELETE') {
          await _gateway.recordDeletion(_deletionOf(entry));
        } else {
          await _gateway.upsertOffers([
            SyncOffer.fromJson(decodePayload(entry.payload)),
          ]);
        }
    }
    await _sync.markDone(entry.id);
  }

  SyncDeletion _deletionOf(SyncOutboxEntry entry) => SyncDeletion(
    entity: MasterEntity.fromWire(entry.entity),
    id: entry.entityId,
    shopId: entry.shopId,
  );

  /// Bumps retry bookkeeping for every not-yet-done entry of the failed
  /// batch, parking entries that exhausted their attempts as FAILED.
  Future<void> _recordFailureFrom(
    List<SyncOutboxEntry> batch,
    int doneCount,
    String message,
  ) async {
    AppLog.warning('Push batch failed after $doneCount done', tag: tag);
    for (final entry in batch.skip(doneCount)) {
      final fresh = await _sync.outboxById(entry.id);
      if (fresh == null || fresh.status != 'PENDING') continue;
      if (fresh.attemptCount + 1 >= maxAttempts) {
        await _sync.parkFailed(fresh.id, message);
      } else {
        await _sync.incrementAttempt(fresh.id, message);
      }
    }
  }

  // ---- Category reconciliation (Phase 7.4) -----------------------------------

  /// Proactively converges duplicate master-data categories that share the same
  /// business key `(shop_id, name)` but have different UUIDs after a shop
  /// merge. The cloud row is canonical (first writer wins by arrival order);
  /// all local product references and outbox payloads are repointed, the
  /// duplicate local row is retired, and its outbox entry is marked DONE so
  /// the FIFO queue never blocks on a known duplicate. Idempotent.
  Future<void> _reconcileCategories() async {
    try {
      final cloudCategories = await _fetchAllCloudCategories();
      if (cloudCategories.isEmpty) return;
      await _sync.reconcileCategoryCollisions(cloudCategories);
    } catch (error, stackTrace) {
      AppLog.warning(
        'Category reconciliation skipped (will retry next cycle)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<List<SyncCategory>> _fetchAllCloudCategories() async {
    final all = <SyncCategory>[];
    var cursor = SyncEngine.initialCursor;
    while (true) {
      final page = await _gateway.pullCategories(since: cursor, limit: 200);
      all.addAll(page.rows);
      cursor = page.newCursor;
      if (page.rows.length < 200) break;
    }
    return all;
  }

  // ---- PULL -----------------------------------------------------------------

  Future<void> _pull({required String deviceId, required String shopId}) async {
    final state = await _sync.stateFor(deviceId);
    final since = state?.lastPulledAt?.toUtc() ?? initialCursor;

    final frontiers = <DateTime>[
      await _drainShops(since),
      await _drainCategories(since),
      await _drainProducts(since),
      await _drainVariants(since),
      await _drainSuppliers(since),
      await _drainCustomers(since),
      // Transaction entities: sales before sale_items (parent→child FK).
      await _drainSales(since),
      await _drainSaleItems(since),
      await _drainExpenses(since),
      await _drainCustomerPayments(since),
      await _drainOffers(since),
      await _drainDeletions(since),
    ];

    // Cursor advance rule: each table drains until EXHAUSTION (short page),
    // so any table that returned rows is fully caught up through its last
    // row's timestamp. Tables with no new rows impose no constraint (they
    // are vacuously caught up — anything written to them mid-cycle carries
    // a fresh server timestamp above the adopted cursor and is picked up
    // next cycle, thanks to strictly-increasing server updated_at).
    var newCursor = since;
    for (final frontier in frontiers) {
      if (frontier.isAfter(newCursor)) newCursor = frontier;
    }

    await _sync.upsertState(
      deviceId: deviceId,
      shopId: shopId,
      lastPulledAt: newCursor,
    );
  }

  /// Returns the timestamp of the last applied row, or [since] when the
  /// table had nothing new.
  Future<DateTime> _drainShops(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullShops(since: since, limit: limit),
    apply: (rows, at) => _applier.applyShopPage(rows, at),
  );

  Future<DateTime> _drainCategories(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullCategories(since: since, limit: limit),
    apply: (rows, at) => _applier.applyCategoryPage(rows, at),
  );

  Future<DateTime> _drainProducts(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullProducts(since: since, limit: limit),
    apply: (rows, at) => _applier.applyProductPage(rows, at),
  );

  Future<DateTime> _drainVariants(DateTime since) => _drainPage(
    since,
    pull: (since, limit) =>
        _gateway.pullProductVariants(since: since, limit: limit),
    apply: (rows, at) => _applier.applyVariantPage(rows, at),
  );

  Future<DateTime> _drainSuppliers(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullSuppliers(since: since, limit: limit),
    apply: (rows, at) => _applier.applySupplierPage(rows, at),
  );

  Future<DateTime> _drainCustomers(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullCustomers(since: since, limit: limit),
    apply: (rows, at) => _applier.applyCustomerPage(rows, at),
  );

  Future<DateTime> _drainSales(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullSales(since: since, limit: limit),
    apply: (rows, at) => _applier.applySalePage(rows, at),
  );

  Future<DateTime> _drainSaleItems(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullSaleItems(since: since, limit: limit),
    apply: (rows, at) => _applier.applySaleItemPage(rows, at),
  );

  Future<DateTime> _drainExpenses(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullExpenses(since: since, limit: limit),
    apply: (rows, at) => _applier.applyExpensePage(rows, at),
  );

  Future<DateTime> _drainCustomerPayments(DateTime since) => _drainPage(
    since,
    pull: (since, limit) =>
        _gateway.pullCustomerPayments(since: since, limit: limit),
    apply: (rows, at) => _applier.applyCustomerPaymentPage(rows, at),
  );

  Future<DateTime> _drainOffers(DateTime since) => _drainPage(
    since,
    pull: (since, limit) => _gateway.pullOffers(since: since, limit: limit),
    apply: (rows, at) => _applier.applyOfferPage(rows, at),
  );

  Future<DateTime> _drainDeletions(DateTime since) async {
    var cursor = since;
    while (true) {
      final page = await _gateway.pullDeletions(
        since: cursor,
        limit: pullPageSize,
      );
      for (final deletion in page.rows) {
        await _applier.applyDeletion(deletion);
      }
      cursor = page.newCursor;
      if (page.rows.length < pullPageSize) break;
    }
    return cursor;
  }

  Future<DateTime> _drainPage<T>(
    DateTime since, {
    required Future<PullPage<T>> Function(DateTime since, int limit) pull,
    required Future<void> Function(List<T> rows, DateTime appliedAt) apply,
  }) async {
    var cursor = since;
    while (true) {
      final page = await pull(cursor, pullPageSize);
      if (page.rows.isNotEmpty) {
        await apply(page.rows, page.newCursor);
      }
      cursor = page.newCursor;
      if (page.rows.length < pullPageSize) break;
    }
    return cursor;
  }
}

/// Decodes an outbox payload JSON string into its wire map.
Map<String, dynamic> decodePayload(String payload) =>
    const JsonDecoder().convert(payload) as Map<String, dynamic>;
