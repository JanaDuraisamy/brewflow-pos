import 'dart:convert';

import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Foundation Repositories (Drift)
///
/// Phase-6 foundation only:
///  - device registration (many devices per user/shop are valid),
///  - the durable sync outbox with an ATOMIC enqueue helper so future
///    business writes can append their outbox row inside the same Drift
///    transaction as the business change,
///  - per-device pull/push cursors.
///
/// No uploader/pull engine lives here yet — that is later Phase-6 work.
/// ---------------------------------------------------------------------------

final class RegisteredDevice {
  const RegisteredDevice({
    required this.id,
    required this.shopId,
    required this.userId,
    required this.isActive,
    this.deviceName,
    this.platform,
  });

  final String id;
  final String shopId;
  final String userId;
  final bool isActive;
  final String? deviceName;
  final String? platform;
}

/// One pending/processed change in the local outbox.
final class SyncOutboxEntry {
  const SyncOutboxEntry({
    required this.id,
    required this.deviceId,
    required this.shopId,
    required this.entity,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.status,
    required this.attemptCount,
  });

  final String id;
  final String deviceId;
  final String shopId;
  final String entity;
  final String entityId;
  final String operation;
  final String payload;
  final String status;
  final int attemptCount;
}

final class DriftSyncRepository {
  DriftSyncRepository(this._database);

  final db.AppDatabase _database;

  /// Runs [action] inside one database transaction (used by the outbox
  /// coordinator to bind business writes and queue appends atomically).
  Future<T> runInTransaction<T>(Future<T> Function() action) =>
      _database.transaction(action);

  // ---- Devices -----------------------------------------------------------

  /// Registers (or refreshes) THIS installation for [shopId]/[userId].
  /// Insert-or-update by device id keeps the id stable while refreshing
  /// last-seen/user binding; multiple rows per user are valid.
  Future<void> registerDevice({
    required String deviceId,
    required String shopId,
    required String userId,
    String? deviceName,
    String? platform,
  }) async {
    final existing = await (_database.select(
      _database.devices,
    )..where((t) => t.id.equals(deviceId))).getSingleOrNull();
    final now = DateTime.now().toUtc();
    if (existing == null) {
      await _database
          .into(_database.devices)
          .insert(
            db.DevicesCompanion.insert(
              id: Value(deviceId),
              shopId: shopId,
              userId: userId,
              deviceName: Value(deviceName),
              platform: Value(platform),
            ),
          );
      return;
    }
    await (_database.update(
      _database.devices,
    )..where((t) => t.id.equals(deviceId))).write(
      db.DevicesCompanion(
        shopId: Value(shopId),
        userId: Value(userId),
        deviceName: deviceName != null
            ? Value(deviceName)
            : const Value.absent(),
        platform: platform != null ? Value(platform) : const Value.absent(),
        isActive: const Value(true),
        lastSeenAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<List<RegisteredDevice>> devicesForShop(String shopId) async {
    final rows = await (_database.select(
      _database.devices,
    )..where((t) => t.shopId.equals(shopId))).get();
    return rows.map(_deviceFromRow).toList();
  }

  /// Whether the installation [deviceId] already has a local row.
  Future<bool> hasDevice(String deviceId) async {
    final row = await (_database.select(
      _database.devices,
    )..where((t) => t.id.equals(deviceId))).getSingleOrNull();
    return row != null;
  }

  // ---- Outbox ------------------------------------------------------------

  /// ATOMIC helper: runs [businessWrite] and appends [entry] in the SAME
  /// Drift transaction. If the business write throws, the outbox row is
  /// rolled back with it — no orphaned queue entries, no unsynced writes.
  Future<T> enqueueInTransaction<T>(
    Future<T> Function() businessWrite,
    SyncOutboxEntry entry,
  ) {
    return _database.transaction(() async {
      final result = await businessWrite();
      await insertOutbox(entry);
      return result;
    });
  }

  /// Inserts one outbox row. Duplicate logical changes still PENDING are
  /// collapsed onto the existing row (identity index), keeping replays safe.
  ///
  /// Conflict semantics matter here: onConflict-update touches ONLY the
  /// columns present in the companion, so mutable bookkeeping (status,
  /// attempts, error) is listed EXPLICITLY. Re-enqueueing a change whose
  /// previous entry already reached DONE must flip it back to PENDING with
  /// fresh retry counters — otherwise the new change would silently never
  /// sync.
  Future<void> insertOutbox(SyncOutboxEntry entry) {
    return _database
        .into(_database.syncOutbox)
        .insertOnConflictUpdate(
          db.SyncOutboxCompanion.insert(
            id: Value(entry.id),
            deviceId: entry.deviceId,
            shopId: entry.shopId,
            entity: entry.entity,
            entityId: entry.entityId,
            operation: Value(entry.operation),
            payload: entry.payload,
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            lastAttemptAt: const Value(null),
            lastError: const Value(null),
          ),
        );
  }

  Future<int> pendingOutboxCount() async {
    final query = _database.selectOnly(_database.syncOutbox)
      ..addColumns([_database.syncOutbox.id.count()])
      ..where(_database.syncOutbox.status.equals('PENDING'));
    final row = await query
        .map((r) => r.read(_database.syncOutbox.id.count()))
        .getSingle();
    return row ?? 0;
  }

  Future<int> failedOutboxCount() async {
    final query = _database.selectOnly(_database.syncOutbox)
      ..addColumns([_database.syncOutbox.id.count()])
      ..where(_database.syncOutbox.status.equals('FAILED'));
    final row = await query
        .map((r) => r.read(_database.syncOutbox.id.count()))
        .getSingle();
    return row ?? 0;
  }

  Future<List<SyncOutboxEntry>> pendingOutboxBatch({int limit = 50}) async {
    final rows =
        await (_database.select(_database.syncOutbox)
              ..where((t) => t.status.equals('PENDING'))
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(limit))
            .get();
    return <SyncOutboxEntry>[for (final r in rows) _outboxFromRow(r)];
  }

  Future<void> markDone(String id) {
    return (_database.update(
      _database.syncOutbox,
    )..where((t) => t.id.equals(id))).write(
      db.SyncOutboxCompanion(
        status: const Value('DONE'),
        lastAttemptAt: Value(DateTime.now().toUtc()),
        lastError: const Value(null),
      ),
    );
  }

  /// Increments retry bookkeeping without touching status (used on failure).
  Future<void> incrementAttempt(String id, String error) {
    return _database.customUpdate(
      'UPDATE sync_outbox SET attempt_count = attempt_count + 1, '
      'last_attempt_at = ?, last_error = ?, status = ? WHERE id = ?',
      variables: [
        Variable.withDateTime(DateTime.now().toUtc()),
        Variable.withString(error),
        Variable.withString('PENDING'),
        Variable.withString(id),
      ],
      updateKind: UpdateKind.update,
    );
  }

  /// Fresh view of one entry (failure handling re-reads authoritative state).
  Future<SyncOutboxEntry?> outboxById(String id) async {
    final row = await (_database.select(
      _database.syncOutbox,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _outboxFromRow(row);
  }

  /// Terminal parking state for entries that exhausted their attempts: the
  /// payload stays locally inspectable, but the FIFO head is freed so later
  /// changes still sync. Nothing is ever silently dropped.
  Future<void> parkFailed(String id, String error) {
    return (_database.update(
      _database.syncOutbox,
    )..where((t) => t.id.equals(id))).write(
      db.SyncOutboxCompanion(
        status: const Value('FAILED'),
        lastError: Value(error),
        lastAttemptAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Revives all FAILED outbox entries by updating their [shopId] column
  /// AND the `shopId` value embedded in the JSON payload, then resetting
  /// status to PENDING and attempt counter to zero.
  ///
  /// Called after the second device resolves its local shop identity to the
  /// cloud's authoritative shop so that previously failed pushes can retry
  /// with the correct identity.
  ///
  /// Returns the number of entries revived.
  Future<int> reviveFailedEntries(String newShopId) async {
    return _database.transaction(() async {
      final failed = await (_database.select(
        _database.syncOutbox,
      )..where((t) => t.status.equals('FAILED'))).get();

      if (failed.isEmpty) return 0;

      var count = 0;
      for (final row in failed) {
        // Patch the shopId inside the payload JSON.
        String patchedPayload = row.payload;
        try {
          final decoded = jsonDecode(patchedPayload) as Map<String, dynamic>;
          if (decoded['shopId'] == newShopId) {
            // Already correct — just reset the status.
          } else {
            decoded['shopId'] = newShopId;
            patchedPayload = jsonEncode(decoded);
          }
        } catch (_) {
          // Non-JSON payload — leave as-is, only fix the column.
        }

        // Update shop_id, payload, status, and reset retry counters.
        await (_database.update(
          _database.syncOutbox,
        )..where((t) => t.id.equals(row.id))).write(
          db.SyncOutboxCompanion(
            shopId: Value(newShopId),
            payload: Value(patchedPayload),
            status: const Value('PENDING'),
            attemptCount: const Value(0),
            lastAttemptAt: const Value(null),
            lastError: const Value(null),
          ),
        );
        count++;
      }
      return count;
    });
  }

  // ---- Category reconciliation (Phase 7.4) -----------------------------------

  /// Returns all local categories (single-shop, unique by name).
  Future<List<db.Category>> localCategories() =>
      _database.select(_database.categories).get();

  /// Deterministically converges duplicate categories that share the same
  /// business key (shop_id, name) but have different UUIDs after a shop merge.
  ///
  /// The [canonical] row is the one already present on the cloud (arrival-
  /// order winner); [oldCategoryId] is the local duplicate that must be
  /// retired. All product references and outbox payloads are repointed to
  /// [canonical.id], the duplicate category's outbox entry is marked DONE
  /// (it is already represented on the server), and the old row is deleted.
  /// Idempotent: safe to call repeatedly; a second call finds no local row for
  /// [oldCategoryId] and becomes a no-op.
  Future<void> adoptCanonicalCategory({
    required String oldCategoryId,
    required SyncCategory canonical,
  }) async {
    if (oldCategoryId == canonical.id) return;
    // SQLite's UNIQUE(categories.name) would block inserting the canonical
    // while the duplicate still holds the same name, and the FK on
    // products.category_id would block repointing before the canonical exists.
    // Disable FK checks for the duration of the swap — the transaction itself
    // remains atomic (either the whole remap succeeds or it rolls back).
    await _database.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await _database.transaction(() async {
        // 1. Remove the duplicate so the business key becomes free.
        await (_database.delete(
          _database.categories,
        )..where((t) => t.id.equals(oldCategoryId))).go();

        // 2. Ensure the canonical row exists locally (so FK targets stay valid).
        await _database
            .into(_database.categories)
            .insertOnConflictUpdate(
              db.CategoriesCompanion.insert(
                id: Value(canonical.id),
                shopId: Value(canonical.shopId),
                name: canonical.name,
                isActive: Value(canonical.isActive),
                createdAt: Value(canonical.createdAt),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            );

        // 3. Repoint every local product that referenced the duplicate.
        await _database.customUpdate(
          'UPDATE products SET category_id = ? WHERE category_id = ?',
          variables: [
            Variable.withString(canonical.id),
            Variable.withString(oldCategoryId),
          ],
          updateKind: UpdateKind.update,
        );

        // 4. Patch any pending/failed product outbox payloads that still embed
        // the old categoryId. Revive FAILED entries to PENDING so they retry
        // with the corrected FK.
        final productOutbox =
            await (_database.select(_database.syncOutbox)
                  ..where((t) => t.entity.equals('PRODUCT'))
                  ..where(
                    (t) =>
                        t.status.equals('PENDING') | t.status.equals('FAILED'),
                  ))
                .get();
        for (final row in productOutbox) {
          try {
            final decoded = jsonDecode(row.payload) as Map<String, dynamic>;
            if (decoded['categoryId'] == oldCategoryId) {
              decoded['categoryId'] = canonical.id;
              final patched = jsonEncode(decoded);
              await (_database.update(
                _database.syncOutbox,
              )..where((t) => t.id.equals(row.id))).write(
                db.SyncOutboxCompanion(
                  payload: Value(patched),
                  status: const Value('PENDING'),
                  attemptCount: const Value(0),
                  lastAttemptAt: const Value(null),
                  lastError: const Value(null),
                ),
              );
            }
          } catch (_) {}
        }

        // 5. The duplicate category itself is already represented on the cloud
        // under [canonical.id]; mark its outbox entry DONE so it no longer
        // blocks the FIFO queue. Handles both PENDING and FAILED.
        await (_database.update(_database.syncOutbox)
              ..where((t) => t.entity.equals('CATEGORY'))
              ..where((t) => t.entityId.equals(oldCategoryId)))
            .write(
              const db.SyncOutboxCompanion(
                status: Value('DONE'),
                attemptCount: Value(0),
                lastError: Value(null),
                lastAttemptAt: Value(null),
              ),
            );
      });
    } finally {
      await _database.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  /// Scans all local categories against the authoritative cloud set and
  /// convergently remaps any name collision (same shop, same name, different
  /// UUID) to the cloud's canonical id. Idempotent.
  Future<void> reconcileCategoryCollisions(
    List<SyncCategory> cloudCategories,
  ) async {
    if (cloudCategories.isEmpty) return;
    final canonicalByName = <String, SyncCategory>{
      for (final c in cloudCategories) c.name: c,
    };
    final locals = await _database.select(_database.categories).get();
    for (final local in locals) {
      final canonical = canonicalByName[local.name];
      if (canonical != null && canonical.id != local.id) {
        await adoptCanonicalCategory(
          oldCategoryId: local.id,
          canonical: canonical,
        );
      }
    }
  }

  // ---- Sync state --------------------------------------------------------

  Future<db.SyncStateData?> stateFor(String deviceId) => (_database.select(
    _database.syncState,
  )..where((t) => t.deviceId.equals(deviceId))).getSingleOrNull();

  Future<void> upsertState({
    required String deviceId,
    required String shopId,
    DateTime? lastPulledAt,
    DateTime? lastPushedAt,
    String? lastError,
  }) async {
    final companion = db.SyncStateCompanion(
      deviceId: Value(deviceId),
      shopId: Value(shopId),
      lastPulledAt: lastPulledAt != null
          ? Value(lastPulledAt)
          : const Value.absent(),
      lastPushedAt: lastPushedAt != null
          ? Value(lastPushedAt)
          : const Value.absent(),
      lastError: lastError != null ? Value(lastError) : const Value.absent(),
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await _database.into(_database.syncState).insertOnConflictUpdate(companion);
  }

  RegisteredDevice _deviceFromRow(db.Device row) => RegisteredDevice(
    id: row.id,
    shopId: row.shopId,
    userId: row.userId,
    isActive: row.isActive,
    deviceName: row.deviceName,
    platform: row.platform,
  );

  SyncOutboxEntry _outboxFromRow(db.SyncOutboxData row) => SyncOutboxEntry(
    id: row.id,
    deviceId: row.deviceId,
    shopId: row.shopId,
    entity: row.entity,
    entityId: row.entityId,
    operation: row.operation,
    payload: row.payload,
    status: row.status,
    attemptCount: row.attemptCount,
  );
}
