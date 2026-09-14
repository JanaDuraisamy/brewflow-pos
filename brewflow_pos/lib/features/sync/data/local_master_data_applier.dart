import 'dart:convert';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/settings/data/preferences_settings_repository.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Local Master-Data Applier
///
/// Applies pulled cloud rows INTO local Drift. Rules:
///
/// - Idempotent UUID upserts: replaying the same page changes nothing.
/// - Pending-local-wins guard: rows with a PENDING outbox change are skipped,
///   so an incoming pull can never revert a local edit that has not been
///   pushed yet. After the local change pushes, the next cycle reconciles.
/// - Parent order: callers apply categories → products → variants, mirroring
///   FK direction; RESTRICT violations abort the surrounding transaction and
///   therefore the whole page (no partial pages, cursors stay honest).
/// - Product images are NEVER overwritten: image paths are device-local
///   files today (see master_data_models.dart).
/// - Hard deletions land as tombstone-driven deletes where legal; when local
///   history still references the row, deletion degrades to soft
///   deactivation — data loss is never the price of convergence.
///
/// This class writes DIRECTLY to tables (no outbox enqueue): applying remote
/// truth is not a new local business change.
/// ---------------------------------------------------------------------------

final class LocalMasterDataApplier {
  LocalMasterDataApplier(this._database);

  final db.AppDatabase _database;

  /// Applies one pull page of shop rows atomically. The shop id is the
  /// identity scope shared by every synced entity, so it is NEVER changed or
  /// duplicated: this only updates the display `name` on the matching local
  /// row (inserting on a fresh device keeps exactly one shop).
  Future<void> applyShopPage(List<SyncShop> rows, DateTime appliedAt) async {
    String? appliedName;
    await _database.transaction(() async {
      for (final row in rows) {
        final existing = await (_database.select(
          _database.shops,
        )..where((t) => t.id.equals(row.id))).getSingleOrNull();
        if (existing == null) {
          // Fresh device: materialize the canonical shop row (single-shop
          // contract — a full-history bootstrap pulls exactly one SHOP row).
          await _database
              .into(_database.shops)
              .insert(
                db.ShopsCompanion.insert(
                  id: Value(row.id),
                  name: row.name,
                  createdAt: Value(row.createdAt),
                  updatedAt: Value(appliedAt),
                ),
              );
          appliedName = row.name;
        } else if (existing.name != row.name) {
          await (_database.update(
            _database.shops,
          )..where((t) => t.id.equals(row.id))).write(
            db.ShopsCompanion(
              name: Value(row.name),
              updatedAt: Value(appliedAt),
            ),
          );
          appliedName = row.name;
        }
      }
    });
    // Refresh the prefs render-cache when the authoritative shop name landed,
    // so prefs-backed surfaces (settings, shell header) show the synced value
    // on the next rebuild. Best-effort: never let a cache write fail a pull.
    if (appliedName != null) {
      await _refreshShopNameRenderCache(appliedName!);
    }
  }

  /// Mirrors the authoritative `shops.name` into the prefs render-cache.
  /// Swallows failures so an unavailable store never breaks sync.
  Future<void> _refreshShopNameRenderCache(String name) async {
    try {
      await AppStorage.preferences.writeString(
        PreferencesSettingsRepository.shopNameKey,
        name,
      );
    } catch (_) {
      // Storage not initialised (e.g. bare tests) — cache refresh is optional.
    }
  }

  /// Applies one pull page atomically. Returns ids actually applied
  /// (excluded pending ones are not listed).
  Future<void> applyCategoryPage(
    List<SyncCategory> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.category,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        // Defensive: a local duplicate category with the same business key
        // (name) but a different UUID may exist from a pre-merge shop. The
        // incoming cloud row is canonical — converge by freeing the unique
        // name, inserting the canonical, then repointing products.
        final existingByName = await (_database.select(
          _database.categories,
        )..where((t) => t.name.equals(row.name))).getSingleOrNull();
        String? oldId;
        bool hasCollision = false;
        if (existingByName != null && existingByName.id != row.id) {
          oldId = existingByName.id;
          hasCollision = true;
          // Free the business key so the canonical insert can succeed.
          await _database.customUpdate(
            'UPDATE categories SET name = ? WHERE id = ?',
            variables: [
              Variable.withString('${row.name}__dup__$oldId'),
              Variable.withString(oldId),
            ],
            updateKind: UpdateKind.update,
          );
        }
        await _database
            .into(_database.categories)
            .insertOnConflictUpdate(
              db.CategoriesCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                name: row.name,
                isActive: Value(row.isActive),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
        if (hasCollision) {
          final String old = oldId!;
          // Canonical now exists — repoint products and retire the duplicate.
          await _database.customUpdate(
            'UPDATE products SET category_id = ? WHERE category_id = ?',
            variables: [Variable.withString(row.id), Variable.withString(old)],
            updateKind: UpdateKind.update,
          );
          final pendingProductOutbox =
              await (_database.select(_database.syncOutbox)
                    ..where((t) => t.entity.equals('PRODUCT'))
                    ..where(
                      (t) =>
                          t.status.equals('PENDING') |
                          t.status.equals('FAILED'),
                    ))
                  .get();
          for (final outRow in pendingProductOutbox) {
            try {
              final decoded =
                  const JsonDecoder().convert(outRow.payload)
                      as Map<String, dynamic>;
              if (decoded['categoryId'] == old) {
                decoded['categoryId'] = row.id;
                final patched = const JsonEncoder().convert(decoded);
                await (_database.update(
                  _database.syncOutbox,
                )..where((t) => t.id.equals(outRow.id))).write(
                  db.SyncOutboxCompanion(
                    payload: Value(patched),
                    status: const Value('PENDING'),
                    attemptCount: const Value(0),
                    lastError: const Value(null),
                    lastAttemptAt: const Value(null),
                  ),
                );
              }
            } catch (_) {}
          }
          await (_database.update(_database.syncOutbox)
                ..where((t) => t.entity.equals('CATEGORY'))
                ..where((t) => t.entityId.equals(old)))
              .write(
                const db.SyncOutboxCompanion(
                  status: Value('DONE'),
                  attemptCount: Value(0),
                  lastError: Value(null),
                  lastAttemptAt: Value(null),
                ),
              );
          await (_database.delete(
            _database.categories,
          )..where((t) => t.id.equals(old))).go();
        }
      }
    });
  }

  Future<void> applyProductPage(
    List<SyncProduct> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.product,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.products)
            .insertOnConflictUpdate(
              db.ProductsCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                categoryId: row.categoryId,
                name: row.name,
                sku: Value(row.sku),
                sellingPricePaise: row.sellingPricePaise,
                costPricePaise: Value(row.costPricePaise),
                stockQuantity: Value(row.stockQuantity),
                imagePath: const Value.absent(),
                cloudImagePath: Value(row.cloudImagePath),
                stockUnit: Value(row.stockUnit.wire),
                lowStockMode: Value(row.lowStockMode.wire),
                lowStockThreshold: Value(row.lowStockThreshold),
                membershipEnabled: Value(row.membershipEnabled),
                memberPricePaise: Value(row.memberPricePaise),
                isActive: Value(row.isActive),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applyVariantPage(
    List<SyncProductVariant> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.productVariant,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.productVariants)
            .insertOnConflictUpdate(
              db.ProductVariantsCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                productId: row.productId,
                name: row.name,
                sku: Value(row.sku),
                sellingPricePaise: row.sellingPricePaise,
                costPricePaise: Value(row.costPricePaise),
                stockQuantity: Value(row.stockQuantity),
                lowStockMode: Value(row.lowStockMode.wire),
                lowStockThreshold: Value(row.lowStockThreshold),
                membershipEnabled: Value(row.membershipEnabled),
                memberPricePaise: Value(row.memberPricePaise),
                isActive: Value(row.isActive),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applySupplierPage(
    List<SyncSupplier> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.supplier,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.suppliers)
            .insertOnConflictUpdate(
              db.SuppliersCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                name: row.name,
                phone: Value(row.phone),
                email: Value(row.email),
                address: Value(row.address),
                notes: Value(row.notes),
                isActive: Value(row.isActive),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applyCustomerPage(
    List<SyncCustomer> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.customer,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        // The local `customers.phone` column is globally UNIQUE while the
        // cloud contract scopes phone uniqueness per shop
        // (`ux_customers_shop_phone`). A cloud row can therefore collide with
        // a different local UUID carrying the same phone (pre-merge duplicate
        // or cross-device creation). `insertOnConflictUpdate` only resolves
        // PK conflicts, so without handling the whole page aborts with
        // SqliteException 2067 and the sync cycle never advances.
        //
        // Same-shop duplicates converge like categories: the incoming cloud
        // row is canonical (last-writer-wins at the server boundary), so the
        // stale local row keeps its identity/history but frees the phone.
        // Cross-shop collisions cannot both be kept under the current local
        // schema, so the incoming row is skipped (local preserved) and logged
        // — a scoped-unique migration would remove this compromise.
        final phone = row.phone?.trim();
        if (phone != null && phone.isNotEmpty) {
          final clash = await (_database.select(
            _database.customers,
          )..where((t) => t.phone.equals(phone))).getSingleOrNull();
          if (clash != null && clash.id != row.id) {
            final clashPending = await _pendingIds(MasterEntity.customer, [
              clash.id,
            ]);
            if (clashPending.contains(clash.id)) {
              // Pending-local-wins extends to the business key: never revert
              // a local phone edit that has not pushed yet.
              continue;
            }
            if (clash.shopId == row.shopId) {
              await (_database.update(
                _database.customers,
              )..where((t) => t.id.equals(clash.id))).write(
                db.CustomersCompanion(
                  phone: const Value(null),
                  updatedAt: Value(appliedAt),
                ),
              );
              AppLog.info(
                'Customer phone collision converged (same shop)',
                tag: 'SyncEngine',
              );
            } else {
              AppLog.info(
                'Customer phone collision skipped (cross-shop, local kept)',
                tag: 'SyncEngine',
              );
              continue;
            }
          }
        }
        await _database
            .into(_database.customers)
            .insertOnConflictUpdate(
              db.CustomersCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                name: row.name,
                phone: Value(row.phone),
                email: Value(row.email),
                address: Value(row.address),
                isActive: Value(row.isActive),
                membershipActive: Value(row.membershipActive),
                membershipFeePaise: Value(row.membershipFeePaise),
                whatsappStatus: Value(row.whatsappStatus),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applySalePage(List<SyncSale> rows, DateTime appliedAt) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.sale,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        // The local UNIQUE(shop_id, receipt_number) is the sale's business
        // key, but the cloud can legitimately hold the same receipt under a
        // DIFFERENT uuid (multi-device offline sales, re-seeds). A plain PK
        // upsert then aborts with SqliteException 2067 and the pull page
        // retries forever. Converge instead: the incoming cloud row is
        // canonical (server last-writer-wins) and the stale local duplicate
        // is retired only after its history is repointed — never deleted
        // silently. Pending local writes still win and just defer.
        final clash =
            await (_database.select(_database.sales)..where(
                  (t) =>
                      t.shopId.equals(row.shopId) &
                      t.receiptNumber.equals(row.receiptNumber),
                ))
                .getSingleOrNull();
        final hasClash = clash != null && clash.id != row.id;
        if (hasClash && clash!.shopId != row.shopId) {
          AppLog.info(
            'Sale receipt collision skipped (cross-shop, local kept)',
            tag: 'SyncEngine',
          );
          continue;
        }
        if (hasClash) {
          // Pending item writes defer convergence entirely: those items are
          // about to push, and dropping them would lose a local business
          // change. The next cycle reconciles after the push lands.
          final staleItemIds =
              await (_database.select(_database.saleItems)
                    ..where((t) => t.saleId.equals(clash!.id)))
                  .get()
                  .then((rows) => rows.map((r) => r.id).toList());
          if (staleItemIds.isNotEmpty) {
            final pendingItems = await _pendingIds(
              MasterEntity.saleItem,
              staleItemIds,
            );
            if (pendingItems.isNotEmpty) {
              AppLog.info(
                'Sale collision deferred (stale sale items pending)',
                tag: 'SyncEngine',
              );
              continue;
            }
          }
          // Free the business key (mirroring the category collision) so the
          // canonical insert below can commit; the stale row is retired after
          // the canonical exists, so repointing its history satisfies RESTRICT.
          await (_database.update(
            _database.sales,
          )..where((t) => t.id.equals(clash!.id))).write(
            db.SalesCompanion(
              receiptNumber: Value('${row.receiptNumber}__dup__${clash!.id}'),
            ),
          );
        }
        await _database
            .into(_database.sales)
            .insertOnConflictUpdate(
              db.SalesCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                receiptNumber: row.receiptNumber,
                customerId: Value(row.customerId),
                subtotalPaise: row.subtotalPaise,
                totalPaise: row.totalPaise,
                offerDiscountPaise: Value(row.offerDiscountPaise),
                paymentMethod: Value(row.paymentMethod),
                paymentStatus: Value(row.paymentStatus),
                voided: Value(row.voided),
                voidedAt: Value(row.voidedAt),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
        if (hasClash) {
          await _convergeSaleCollision(
            clashId: clash!.id,
            canonicalId: row.id,
            appliedAt: appliedAt,
          );
        }
      }
    });
  }

  /// Retires the stale local sale that shares the canonical cloud row's
  /// business key (shop_id, receipt_number) under a different uuid.
  ///
  /// Runs AFTER the canonical sale row has been inserted (its business key was
  /// already freed by the caller). The pulled cloud sale is canonical and its
  /// own item rows arrive later in the same pull, so the stale snapshot items
  /// are safe to drop (RESTRICT on sale_items would otherwise block the
  /// delete). Customer payments and SALE stock movements are repointed so no
  /// history is orphaned, and PENDING/FAILED outbox entries for the stale row
  /// are retired so nothing retries a push that can never land.
  Future<void> _convergeSaleCollision({
    required String clashId,
    required String canonicalId,
    required DateTime appliedAt,
  }) async {
    final staleItemIds =
        await (_database.select(_database.saleItems)
              ..where((t) => t.saleId.equals(clashId)))
            .get()
            .then((rows) => rows.map((r) => r.id).toList());
    // Payments and SALE stock movements follow the canonical sale.
    await (_database.update(
      _database.customerPayments,
    )..where((t) => t.saleId.equals(clashId))).write(
      db.CustomerPaymentsCompanion(
        saleId: Value(canonicalId),
        updatedAt: Value(appliedAt),
      ),
    );
    await (_database.update(_database.stockMovements)
          ..where((t) => t.referenceType.equals('SALE'))
          ..where((t) => t.referenceId.equals(clashId)))
        .write(db.StockMovementsCompanion(referenceId: Value(canonicalId)));
    // The stale sale can never be pushed again: retire its outbox rows.
    await (_database.update(_database.syncOutbox)
          ..where((t) => t.entity.equals(MasterEntity.sale.wire))
          ..where((t) => t.entityId.equals(clashId))
          ..where(
            (t) => t.status.equals('PENDING') | t.status.equals('FAILED'),
          ))
        .write(
          const db.SyncOutboxCompanion(
            status: Value('DONE'),
            attemptCount: Value(0),
            lastError: Value(null),
            lastAttemptAt: Value(null),
          ),
        );
    // Drop the stale snapshot items (their data re-arrives under the
    // canonical id) so the RESTRICT FK lets the stale sale row be deleted.
    if (staleItemIds.isNotEmpty) {
      await (_database.delete(
        _database.saleItems,
      )..where((t) => t.id.isIn(staleItemIds))).go();
    }
    await (_database.delete(
      _database.sales,
    )..where((t) => t.id.equals(clashId))).go();
    AppLog.info(
      'Sale receipt collision converged clash=$clashId canonical=$canonicalId',
      tag: 'SyncEngine',
    );
  }

  Future<void> applySaleItemPage(
    List<SyncSaleItem> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.saleItem,
        rows.map((r) => r.id),
      );
      // Parent-order guard: sale_items reference sales with a RESTRICT FK, so
      // a row whose parent sale is not applied yet would abort the WHOLE page
      // (SqliteException 787) and pin the cycle at its old cursor forever.
      // Pulled pages can genuinely surface such orphans on a fresh bootstrap
      // (page windows, shop-scoped pull skew, re-seeds). Defer them instead:
      // the page still commits, valid siblings still apply, and the row
      // converges on a later cycle once its parent lands. The FK constraints
      // themselves are intentionally left untouched.
      final presentParents = <String>{};
      if (rows.isNotEmpty) {
        final parents = await (_database.select(
          _database.sales,
        )..where((t) => t.id.isIn(rows.map((r) => r.saleId)))).get();
        presentParents.addAll([for (final p in parents) p.id]);
      }
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        if (!presentParents.contains(row.saleId)) {
          AppLog.info(
            'Sale item ${row.id} deferred (parent sale ${row.saleId} not applied yet)',
            tag: 'SyncEngine',
          );
          continue;
        }
        // Business-key convergence: the online checkout mirrors a cloud sale
        // under client-side UUIDs while the server mints its own item UUIDs.
        // Without this, the canonical row arriving here would be INSERTED
        // (insertOnConflictUpdate matches only on the PK id) and the same
        // logical item would live twice locally. The incoming cloud row is
        // canonical; any local row sharing its (sale, product, variant) key
        // under a different id is a stale snapshot and is retired first so
        // the canonical insert lands exactly once. The PK upsert then keeps
        // every later replay an in-place update.
        final stale =
            await (_database.select(_database.saleItems)..where(
                  (t) =>
                      t.saleId.equals(row.saleId) &
                      t.productId.equals(row.productId) &
                      (row.variantId == null
                          ? t.variantId.isNull()
                          : t.variantId.equals(row.variantId!)) &
                      t.id.isNotIn([row.id]),
                ))
                .get();
        final staleIds = stale.map((s) => s.id).toList();
        if (staleIds.isNotEmpty) {
          // Never drop an item that still has a PENDING outbox row: its push
          // is about to land and deleting the row would leak the change.
          final pendingStale = await _pendingIds(
            MasterEntity.saleItem,
            staleIds,
          );
          if (pendingStale.isNotEmpty) {
            AppLog.info(
              'Sale item collision deferred (stale item pending)',
              tag: 'SyncEngine',
            );
            continue;
          }
          await (_database.delete(
            _database.saleItems,
          )..where((t) => t.id.isIn(staleIds))).go();
          AppLog.info(
            'Sale item business-key duplicate converged: ${staleIds.join(',')} -> ${row.id}',
            tag: 'SyncEngine',
          );
        }
        await _database
            .into(_database.saleItems)
            .insertOnConflictUpdate(
              db.SaleItemsCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                saleId: row.saleId,
                productId: row.productId,
                variantId: Value(row.variantId),
                productName: row.productName,
                variantName: Value(row.variantName),
                sku: Value(row.sku),
                unitPricePaise: row.unitPricePaise,
                quantity: row.quantity,
                lineTotalPaise: row.lineTotalPaise,
                offerDiscountPaise: Value(row.offerDiscountPaise),
                appliedOfferId: Value(row.appliedOfferId),
                appliedOfferName: Value(row.appliedOfferName),
                appliedOfferType: Value(row.appliedOfferType),
              ),
            );
      }
    });
  }

  Future<void> applyExpensePage(
    List<SyncExpense> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.expense,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.expenses)
            .insertOnConflictUpdate(
              db.ExpensesCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                name: row.name,
                amountPaise: row.amountPaise,
                category: row.category,
                paymentMethod: row.paymentMethod,
                paymentStatus: Value(row.paymentStatus),
                expenseDate: row.expenseDate,
                note: Value(row.note),
                isActive: Value(row.isActive),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applyCustomerPaymentPage(
    List<SyncCustomerPayment> rows,
    DateTime appliedAt,
  ) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.customerPayment,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.customerPayments)
            .insertOnConflictUpdate(
              db.CustomerPaymentsCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                customerId: row.customerId,
                saleId: Value(row.saleId),
                amountPaise: row.amountPaise,
                paymentMethod: row.paymentMethod,
                note: Value(row.note),
                paidAt: row.paidAt,
                reversed: Value(row.reversed),
                reversedAt: Value(row.reversedAt),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  Future<void> applyOfferPage(List<SyncOffer> rows, DateTime appliedAt) async {
    await _database.transaction(() async {
      final skipped = await _pendingIds(
        MasterEntity.offer,
        rows.map((r) => r.id),
      );
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
        await _database
            .into(_database.offers)
            .insertOnConflictUpdate(
              db.OffersCompanion.insert(
                id: Value(row.id),
                shopId: Value(row.shopId),
                name: row.name,
                type: row.type,
                configJson: row.configJson,
                isActive: Value(row.isActive),
                startAt: Value(row.startAt),
                endAt: Value(row.endAt),
                createdAt: Value(row.createdAt),
                updatedAt: Value(appliedAt),
              ),
            );
      }
    });
  }

  /// Applies a pulled deletion. Categories hard-delete when unreferenced and
  /// soft-deactivate otherwise; every other entity soft-deactivates (their
  /// local semantics never hard-delete).
  Future<void> applyDeletion(SyncDeletion deletion) async {
    switch (deletion.entity) {
      case MasterEntity.category:
        try {
          await _database.transaction(() async {
            await (_database.delete(
              _database.categories,
            )..where((t) => t.id.equals(deletion.id))).go();
          });
        } on Exception {
          await _deactivate(_database.categories, deletion.id);
        }
      case MasterEntity.product:
        await _deactivate(_database.products, deletion.id);
      case MasterEntity.productVariant:
        await _deactivate(_database.productVariants, deletion.id);
      case MasterEntity.supplier:
        await _deactivate(_database.suppliers, deletion.id);
      case MasterEntity.customer:
        await _deactivate(_database.customers, deletion.id);
      case MasterEntity.sale:
      case MasterEntity.saleItem:
      case MasterEntity.customerPayment:
        // Immutable append-only: sync never deletes these.
        break;
      case MasterEntity.shop:
        // Single identity row, never deleted by sync (only renamed).
        break;
      case MasterEntity.expense:
        await _deactivate(_database.expenses, deletion.id);
      case MasterEntity.offer:
        await (_database.delete(
          _database.offers,
        )..where((t) => t.id.equals(deletion.id))).go();
    }
  }

  Future<void> _deactivate(TableInfo table, String id) async {
    // Table-specific active columns; drift forces concrete statements here.
    if (table == _database.products) {
      await (_database.update(
        _database.products,
      )..where((t) => t.id.equals(id))).write(
        db.ProductsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } else if (table == _database.productVariants) {
      await (_database.update(
        _database.productVariants,
      )..where((t) => t.id.equals(id))).write(
        db.ProductVariantsCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } else if (table == _database.suppliers) {
      await (_database.update(
        _database.suppliers,
      )..where((t) => t.id.equals(id))).write(
        db.SuppliersCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } else if (table == _database.customers) {
      await (_database.update(
        _database.customers,
      )..where((t) => t.id.equals(id))).write(
        db.CustomersCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } else if (table == _database.categories) {
      await (_database.update(
        _database.categories,
      )..where((t) => t.id.equals(id))).write(
        db.CategoriesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    } else if (table == _database.expenses) {
      await (_database.update(
        _database.expenses,
      )..where((t) => t.id.equals(id))).write(
        db.ExpensesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
    }
  }

  /// Entity ids among [ids] carrying a PENDING local change — those rows are
  /// NOT overwritten by pulls until their push lands.
  Future<Set<String>> _pendingIds(
    MasterEntity entity,
    Iterable<String> ids,
  ) async {
    final idList = ids.toList();
    if (idList.isEmpty) return const {};
    final query = _database.selectOnly(_database.syncOutbox)
      ..addColumns([_database.syncOutbox.entityId])
      ..where(
        _database.syncOutbox.entity.equals(entity.wire) &
            _database.syncOutbox.status.equals('PENDING') &
            _database.syncOutbox.entityId.isIn(idList),
      );
    final found = await query
        .map((row) => row.read(_database.syncOutbox.entityId))
        .get();
    return found.whereType<String>().toSet();
  }
}
