import 'dart:convert';

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
      }
    });
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
      for (final row in rows) {
        if (skipped.contains(row.id)) continue;
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
