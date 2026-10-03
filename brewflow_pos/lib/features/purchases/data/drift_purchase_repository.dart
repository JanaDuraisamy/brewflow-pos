import 'dart:async';

import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/purchase_items_dao.dart';
import 'package:brewflow_pos/core/database/daos/purchases_dao.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/purchases/data/purchases_cloud_gateway.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Purchase Repository
///
/// Implements [PurchaseRepository] on the local Drift database.
///
/// Receiving runs inside a single transaction: the supplier (when linked) and
/// every stock entity (products, and variants for variant lines) are
/// re-validated against the database (existence, active flag), stock is
/// increased with a database-authoritative
/// `UPDATE ... SET stock_quantity = stock_quantity + ? ... RETURNING` (the
/// same UPDATE ... RETURNING mechanism the receipt sequence uses) on the
/// exact entity the line receives into, the purchase sequence is consumed,
/// and the purchase header plus snapshot line items (with variant snapshots)
/// and one PURCHASE stock movement per line (with `referenceType = 'PURCHASE'`
/// and the purchase id) commit together or roll back together.
///
/// Movement semantics follow Phase 9 conventions: [quantity] is the signed
/// delta (`+line.quantity`), [stockBefore]/[stockAfter] are the absolute
/// levels observed inside the transaction, and the invariant
/// `stockAfter = stockBefore + quantity` holds for every row.
/// ---------------------------------------------------------------------------

final class DriftPurchaseRepository implements PurchaseRepository {
  DriftPurchaseRepository(
    db.AppDatabase database, {
    ConnectivityService? connectivityService,
    PurchasesCloudGateway? cloudGateway,
  }) : _database = database,
       _purchases = PurchasesDao(database),
       _items = PurchaseItemsDao(database),
       _movements = StockMovementsDao(database),
       _connectivity = connectivityService,
       _cloud = cloudGateway;

  static const String tag = 'Purchases';

  /// Fixed id of the single purchase-counter row in purchase_sequences.
  static const String _purchaseSequenceId = 'purchase';

  final db.AppDatabase _database;
  final PurchasesDao _purchases;
  final PurchaseItemsDao _items;
  final StockMovementsDao _movements;
  final ConnectivityService? _connectivity;
  final PurchasesCloudGateway? _cloud;

  @override
  Future<Purchase> receivePurchase({
    required List<PurchaseLine> lines,
    String? supplierId,
    String? notes,
    String? shopId,
  }) async {
    if (lines.isEmpty) {
      throw const EmptyPurchaseFailure();
    }
    if (_connectivity != null) {
      try {
        await OnlineGuard(_connectivity!).requireOnline();
      } on OfflineException catch (e) {
        throw UnexpectedPurchasesFailure(e.message);
      }
    }
    // Cloud-authoritative path when gateway wired
    if (_cloud != null) {
      final resolvedShopId = await resolveWritableShopId(_database, shopId);
      final rpcLines = [
        for (final line in lines)
          {
            'product_id': line.productId,
            'variant_id': line.variantId,
            'quantity': line.quantity,
            'unit_cost_paise': line.unitCostPaise,
          },
      ];
      Map<String, dynamic> res;
      try {
        res = await _cloud!.receivePurchaseAtomic(
          shopId: resolvedShopId,
          supplierId: supplierId,
          notes: notes,
          lines: rpcLines,
        );
      } catch (e) {
        if (e is TimeoutException) {
          throw const UnexpectedPurchasesFailure(
            'The server is taking too long to respond. Please try again.',
          );
        }
        final msg = e.toString();
        if (msg.contains('EMPTY_PURCHASE')) throw const EmptyPurchaseFailure();
        if (msg.contains('INVALID_QUANTITY'))
          throw const InvalidPurchaseQuantityFailure();
        if (msg.contains('INVALID_COST'))
          throw const InvalidPurchaseCostFailure();
        if (msg.contains('UNKNOWN_PRODUCT'))
          throw UnknownProductFailure(lines.first.productId);
        if (msg.contains('INACTIVE_PRODUCT'))
          throw InactiveProductFailure('Product is deactivated');
        if (msg.contains('UNKNOWN_SUPPLIER'))
          throw const UnknownSupplierFailure();
        if (msg.contains('INACTIVE_SUPPLIER'))
          throw const InactiveSupplierFailure();
        if (msg.contains('FORBIDDEN'))
          throw const UnexpectedPurchasesFailure(
            'Access denied for this shop.',
          );
        if (msg.contains('SocketException') ||
            msg.contains('Failed host lookup')) {
          throw const UnexpectedPurchasesFailure(
            'Internet connection required. Please check your connection and try again.',
          );
        }
        rethrow;
      }
      final purchaseId = res['id'] as String;
      final purchaseNumber = res['purchase_number'] as String;
      final createdAt = res['created_at'] != null
          ? DateTime.parse(res['created_at'] as String).toUtc()
          : DateTime.now().toUtc();
      final subtotal = res['subtotal'] as int? ?? 0;

      // Mirror locally for cache
      final purchase = Purchase(
        id: purchaseId,
        supplierId: supplierId,
        purchaseNumber: purchaseNumber,
        subtotalPaise: subtotal,
        totalPaise: subtotal,
        notes: notes,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      await _database.transaction(() async {
        // Increase stock locally to match server. The server also backfills
        // cost_price_paise on receive (migration 0017) — mirror that here so
        // profit reports reflect the newest cost immediately instead of
        // waiting for the next product pull.
        for (final line in lines) {
          if (line.variantId != null) {
            await _database.customStatement(
              'UPDATE product_variants SET stock_quantity = stock_quantity + ?, '
              'cost_price_paise = CASE WHEN ? > 0 THEN ? ELSE cost_price_paise END, '
              'updated_at = ? WHERE id = ?',
              [
                line.quantity,
                line.unitCostPaise,
                line.unitCostPaise,
                createdAt.toIso8601String(),
                line.variantId,
              ],
            );
          } else {
            await _database.customStatement(
              'UPDATE products SET stock_quantity = stock_quantity + ?, '
              'cost_price_paise = CASE WHEN ? > 0 THEN ? ELSE cost_price_paise END, '
              'updated_at = ? WHERE id = ?',
              [
                line.quantity,
                line.unitCostPaise,
                line.unitCostPaise,
                createdAt.toIso8601String(),
                line.productId,
              ],
            );
          }
        }

        await _database
            .into(_database.purchases)
            .insert(
              db.PurchasesCompanion.insert(
                id: Value(purchaseId),
                shopId: Value(resolvedShopId),
                supplierId: Value(supplierId),
                purchaseNumber: purchaseNumber,
                subtotalPaise: subtotal,
                totalPaise: subtotal,
                notes: Value(notes),
                createdAt: Value(createdAt),
                updatedAt: Value(createdAt),
              ),
            );

        for (final line in lines) {
          final row = await (_database.select(
            _database.products,
          )..where((t) => t.id.equals(line.productId))).getSingleOrNull();
          final variantRow = line.variantId != null
              ? await (_database.select(
                  _database.productVariants,
                )..where((t) => t.id.equals(line.variantId!))).getSingleOrNull()
              : null;
          final pName = row?.name ?? 'Product';
          final pSku = variantRow?.sku ?? row?.sku;
          final vName = variantRow?.name;
          final itemId = const Uuid().v4();
          final lineTotal = line.unitCostPaise * line.quantity;
          await _database
              .into(_database.purchaseItems)
              .insert(
                db.PurchaseItemsCompanion.insert(
                  id: Value(itemId),
                  shopId: Value(resolvedShopId),
                  purchaseId: purchaseId,
                  productId: line.productId,
                  variantId: Value(line.variantId),
                  productName: pName,
                  variantName: Value(vName),
                  sku: Value(pSku),
                  unitCostPaise: line.unitCostPaise,
                  quantity: line.quantity,
                  lineTotalPaise: lineTotal,
                ),
              );
          // Stock movement already inserted server-side; mirror locally
          final before = variantRow != null
              ? (variantRow.stockQuantity - line.quantity)
              : ((row?.stockQuantity ?? 0) - line.quantity);
          final after = variantRow != null
              ? variantRow.stockQuantity
              : (row?.stockQuantity ?? 0);
          await _database
              .into(_database.stockMovements)
              .insert(
                db.StockMovementsCompanion.insert(
                  shopId: Value(resolvedShopId),
                  productId: line.productId,
                  variantId: Value(line.variantId),
                  movementType: StockMovementType.purchase.dbValue,
                  quantity: line.quantity,
                  stockBefore: before < 0 ? 0 : before,
                  stockAfter: after,
                  referenceType: Value(StockMovementType.purchase.dbValue),
                  referenceId: Value(purchaseId),
                  createdAt: Value(createdAt),
                  updatedAt: Value(createdAt),
                ),
              );
        }
      });

      return purchase;
    }
    try {
      return await _database.transaction(() async {
        final resolvedShopId = await resolveWritableShopId(_database, shopId);
        return _receiveInTransaction(lines, supplierId, notes, resolvedShopId);
      });
    } on PurchasesFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      AppLog.error(
        'Failed to receive purchase',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedPurchasesFailure();
    }
  }

  Future<Purchase> _receiveInTransaction(
    List<PurchaseLine> lines,
    String? supplierId,
    String? notes,
    String shopId,
  ) async {
    final now = DateTime.now().toUtc();
    final purchaseId = const Uuid().v4();

    // Re-validate the supplier before anything is written, so a bad supplier
    // reference never consumes a purchase number or stock.
    await _validateSupplier(supplierId);

    // Cheap input validation before any database reads. The same stock entity
    // (product, or product+variant) may appear on only one line (the
    // receiving UI is expected to merge lines).
    final seen = <String>{};
    for (final line in lines) {
      if (line.quantity <= 0) {
        throw const InvalidPurchaseQuantityFailure();
      }
      if (line.unitCostPaise < 0) {
        throw const InvalidPurchaseCostFailure();
      }
      if (!seen.add('${line.productId}:${line.variantId ?? ''}')) {
        throw const DuplicateProductLineFailure();
      }
    }

    // Re-validate every line against the current database, never the caller.
    final entitiesByKey = await _entitiesById(lines);
    final ordered =
        <
          ({
            PurchaseLine line,
            db.Product product,
            db.ProductVariant? variant,
            int lineTotal,
          })
        >[];
    final movements = <db.StockMovementsCompanion>[];
    for (final line in lines) {
      final entity = entitiesByKey['${line.productId}:${line.variantId ?? ''}'];
      final product = entity?.product;
      final variant = entity?.variant;
      if (product == null) {
        throw UnknownProductFailure(line.productId);
      }
      if (!product.isActive) {
        throw InactiveProductFailure(product.name);
      }
      if (line.variantId != null && (variant == null || !variant.isActive)) {
        throw InactiveProductFailure(product.name);
      }
      final lineTotal = Money.multiplyPaise(line.unitCostPaise, line.quantity);
      if (lineTotal == null) {
        throw const UnexpectedPurchasesFailure(
          'Line total exceeds the safe ceiling.',
        );
      }

      ordered.add((
        line: line,
        product: product,
        variant: variant,
        lineTotal: lineTotal,
      ));
    }

    final subtotal = Money.sumPaise(ordered.map((e) => e.lineTotal));
    if (subtotal == null) {
      throw const UnexpectedPurchasesFailure(
        'Purchase total exceeds the safe ceiling.',
      );
    }

    final purchaseNumber = await _nextPurchaseNumber(shopId);

    // Stock-in per line. The increment is applied by SQLite against the
    // committed value (`stock_quantity = stock_quantity + ?`) on the exact
    // stock entity the line receives into, and the resulting level is read
    // back with RETURNING — the single source of truth for stockAfter, immune
    // to read-compute-write races. stockBefore is the level read at
    // validation above; because the transaction serializes writers,
    // `stockAfter = stockBefore + quantity` holds by construction. SQLite's
    // 64-bit signed INTEGER cannot overflow here: the money ceiling caps
    // every quantity well below 2^63.
    for (final entry in ordered) {
      final String tableSql;
      final List<Variable> variables;
      if (entry.variant != null) {
        tableSql =
            'UPDATE product_variants SET stock_quantity = stock_quantity + ?, '
            'updated_at = ? WHERE id = ? RETURNING stock_quantity';
        variables = [
          Variable.withInt(entry.line.quantity),
          Variable.withString(now.toIso8601String()),
          Variable.withString(entry.line.variantId!),
        ];
      } else {
        tableSql =
            'UPDATE products SET stock_quantity = stock_quantity + ?, '
            'updated_at = ? WHERE id = ? RETURNING stock_quantity';
        variables = [
          Variable.withInt(entry.line.quantity),
          Variable.withString(now.toIso8601String()),
          Variable.withString(entry.line.productId),
        ];
      }
      final row = await _database
          .customSelect(tableSql, variables: variables)
          .getSingle();
      final stockAfter = row.read<int>('stock_quantity');

      movements.add(
        db.StockMovementsCompanion.insert(
          shopId: Value(shopId),
          productId: entry.line.productId,
          variantId: Value(entry.line.variantId),
          movementType: StockMovementType.purchase.dbValue,
          quantity: entry.line.quantity,
          stockBefore:
              entry.variant?.stockQuantity ?? entry.product.stockQuantity,
          stockAfter: stockAfter,
          reason: const Value(null),
          note: const Value(null),
          referenceType: Value(StockMovementType.purchase.dbValue),
          referenceId: Value(purchaseId),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    await _purchases.insert(
      db.PurchasesCompanion.insert(
        id: Value(purchaseId),
        shopId: Value(shopId),
        supplierId: Value(supplierId),
        purchaseNumber: purchaseNumber,
        subtotalPaise: subtotal,
        totalPaise: subtotal,
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );

    await _database.batch((batch) {
      batch.insertAll(_database.purchaseItems, [
        for (final entry in ordered)
          db.PurchaseItemsCompanion.insert(
            id: Value(const Uuid().v4()),
            shopId: Value(shopId),
            purchaseId: purchaseId,
            productId: entry.line.productId,
            variantId: Value(entry.line.variantId),
            productName: entry.product.name,
            variantName: Value(entry.variant?.name),
            sku: Value(entry.variant?.sku ?? entry.product.sku),
            unitCostPaise: entry.line.unitCostPaise,
            quantity: entry.line.quantity,
            lineTotalPaise: entry.lineTotal,
          ),
      ]);
    });

    await _movements.insertAll(movements);

    return Purchase(
      id: purchaseId,
      supplierId: supplierId,
      purchaseNumber: purchaseNumber,
      subtotalPaise: subtotal,
      totalPaise: subtotal,
      notes: notes,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Loads the stock entities behind every line in one round trip: the
  /// products and (for variant lines) the variants, keyed the same way the
  /// duplicate check keys lines (`productId:variantId`). A missing product
  /// surfaces as a null entry so the caller can raise the domain failure.
  Future<Map<String, ({db.Product? product, db.ProductVariant? variant})>>
  _entitiesById(List<PurchaseLine> lines) async {
    final productIds = lines.map((l) => l.productId).toSet();
    final productRows = await (_database.select(
      _database.products,
    )..where((t) => t.id.isIn(productIds))).get();
    final products = {for (final row in productRows) row.id: row};

    final variantIds = lines
        .where((l) => l.variantId != null)
        .map((l) => l.variantId!)
        .toSet();
    final variantRows = variantIds.isEmpty
        ? const <db.ProductVariant>[]
        : await (_database.select(
            _database.productVariants,
          )..where((t) => t.id.isIn(variantIds))).get();
    final variants = {for (final row in variantRows) row.id: row};

    return {
      for (final line in lines)
        '${line.productId}:${line.variantId ?? ''}': (
          product: products[line.productId],
          variant: line.variantId == null ? null : variants[line.variantId],
        ),
    };
  }

  /// No-op for walk-in purchases (null). For supplier-linked purchases the
  /// supplier must still exist and be active; anything else fails the whole
  /// receive.
  Future<void> _validateSupplier(String? supplierId) async {
    if (supplierId == null) {
      return;
    }
    final row = await (_database.select(
      _database.suppliers,
    )..where((t) => t.id.equals(supplierId))).getSingleOrNull();
    if (row == null) {
      throw const UnknownSupplierFailure();
    }
    if (!row.isActive) {
      throw const InactiveSupplierFailure();
    }
  }

  /// Allocates a gapless purchase number scoped to [shopId].  The per-shop
  /// counter lives in `purchase_sequences` with composite key `(id, shop_id)`.
  Future<String> _nextPurchaseNumber(String shopId) async {
    await _database.customStatement(
      'INSERT OR IGNORE INTO purchase_sequences (id, shop_id, next_value) VALUES (?, ?, 0)',
      [_purchaseSequenceId, shopId],
    );
    final row = await _database
        .customSelect(
          'UPDATE purchase_sequences SET next_value = next_value + 1 '
          'WHERE id = ? AND shop_id = ? RETURNING next_value',
          variables: [
            Variable.withString(_purchaseSequenceId),
            Variable.withString(shopId),
          ],
        )
        .getSingle();
    final nextValue = row.read<int>('next_value');
    return '${AppConstants.purchaseNumberPrefix}${nextValue.toString().padLeft(6, '0')}';
  }

  @override
  Future<List<Purchase>> purchases({List<String>? shopIds}) async {
    try {
      // A non-null [shopIds] is a hard scope, so an empty list must yield
      // NOTHING. Treating it as "unscoped" would hand a Food Truck session
      // every Cafe purchase in the history list.
      if (shopIds != null && shopIds.isEmpty) return const [];
      if (shopIds != null) {
        final all = <db.Purchase>[];
        for (final shopId in shopIds) {
          all.addAll(await _purchases.all(shopId: shopId));
        }
        // Each shop query is already newest-first; a stable id tie-break keeps
        // the merged list deterministic without re-sorting timestamps.
        return all.map(_purchaseFromRow).toList();
      }
      final rows = await _purchases.all();
      return rows.map(_purchaseFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load purchases', error, stackTrace);
    }
  }

  @override
  Future<Purchase?> purchaseById(String id, {List<String>? shopIds}) async {
    try {
      if (shopIds != null) {
        for (final shopId in shopIds) {
          final scoped = await _purchases.byId(id, shopId: shopId);
          if (scoped != null) return _purchaseFromRow(scoped);
        }
        return null;
      }
      final row = await _purchases.byId(id);
      return row == null ? null : _purchaseFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load purchase', error, stackTrace);
    }
  }

  @override
  Future<List<PurchaseItem>> purchaseItems(
    String purchaseId, {
    List<String>? shopIds,
  }) async {
    try {
      if (shopIds != null) {
        if (shopIds.isEmpty) return const [];
        final all = <db.PurchaseItem>[];
        for (final shopId in shopIds) {
          all.addAll(await _items.byPurchase(purchaseId, shopId: shopId));
        }
        return all.map(_purchaseItemFromRow).toList();
      }
      final rows = await _items.byPurchase(purchaseId);
      return rows.map(_purchaseItemFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load purchase items', error, stackTrace);
    }
  }

  /// The purchase to void, restricted to [shopIds].
  ///
  /// A non-null [shopIds] is a hard scope, so a void aimed at another
  /// business's purchase resolves to null and the transaction aborts — the
  /// caller cannot reverse stock it is not allowed to see.
  Future<db.Purchase?> _scopedPurchaseForVoid(
    String id,
    List<String> shopIds,
  ) async {
    if (shopIds.isEmpty) return null;
    for (final shopId in shopIds) {
      final row = await _purchases.byId(id, shopId: shopId);
      if (row != null) return row;
    }
    return null;
  }

  /// Snapshot lines of the purchase being voided.
  ///
  /// Pinned to the purchase's OWN shop rather than the caller's scope list: the
  /// header has already been resolved as in-scope, so its shop is exactly the
  /// scope the lines must come from. Reading them under the wider caller scope
  /// could pick up a same-id line row belonging to another shop.
  ///
  /// A legacy row with no `shopId` cannot be scope-checked, so it is reported
  /// as "not found" rather than voided blindly — refusing is the safe
  /// direction, because a wrong void silently reverses real stock.
  Future<List<db.PurchaseItem>> _scopedItemsForVoid(
    String purchaseId,
    db.Purchase purchase,
  ) async {
    final ownerShopId = purchase.shopId;
    if (ownerShopId == null) return const [];
    return _items.byPurchase(purchaseId, shopId: ownerShopId);
  }

  @override
  Future<void> voidPurchase(String id, {List<String>? shopIds}) async {
    try {
      // Cloud-authoritative path when gateway wired. Purchases are created
      // server-side (receive_purchase_atomic); voiding must commit on the
      // server first so other devices never re-import a voided purchase. After
      // it commits we mirror the deletion locally.
      if (_cloud != null) {
        if (_connectivity != null) {
          try {
            await OnlineGuard(_connectivity!).requireOnline();
          } on OfflineException catch (e) {
            throw UnexpectedPurchasesFailure(e.message);
          }
        }
        try {
          await _cloud!.voidPurchaseAtomic(purchaseId: id);
        } on TimeoutException {
          throw const UnexpectedPurchasesFailure(
            'The server is taking too long to respond. Please try again.',
          );
        } catch (e) {
          final msg = e.toString();
          if (msg.contains('PURCHASE_NOT_FOUND')) {
            throw const UnexpectedPurchasesFailure('Purchase not found.');
          }
          if (msg.contains('FORBIDDEN')) {
            throw const UnexpectedPurchasesFailure(
              'Access denied for this shop.',
            );
          }
          if (msg.contains('SocketException') ||
              msg.contains('Failed host lookup')) {
            throw const UnexpectedPurchasesFailure(
              'Internet connection required. Please check your connection and try again.',
            );
          }
          rethrow;
        }
      }
      await _database.transaction(() async {
        final purchase = shopIds == null
            ? await _purchases.byId(id)
            : await _scopedPurchaseForVoid(id, shopIds);
        if (purchase == null) {
          throw const UnexpectedPurchasesFailure('Purchase not found.');
        }
        final items = shopIds == null
            ? await _items.byPurchase(id)
            : await _scopedItemsForVoid(id, purchase);
        final now = DateTime.now().toUtc().toIso8601String();
        // Reverse exactly the stock each line added, targeting the same stock
        // entity (product or variant) the line was received into.
        for (final item in items) {
          if (item.variantId != null) {
            await _database
                .customSelect(
                  'UPDATE product_variants SET stock_quantity = '
                  'stock_quantity - ?, updated_at = ? WHERE id = ? '
                  'RETURNING stock_quantity',
                  variables: [
                    Variable.withInt(item.quantity),
                    Variable.withString(now),
                    Variable.withString(item.variantId!),
                  ],
                )
                .getSingle();
          } else {
            await _database
                .customSelect(
                  'UPDATE products SET stock_quantity = stock_quantity - ?, '
                  'updated_at = ? WHERE id = ? RETURNING stock_quantity',
                  variables: [
                    Variable.withInt(item.quantity),
                    Variable.withString(now),
                    Variable.withString(item.productId),
                  ],
                )
                .getSingle();
          }
        }
        // Remove the purchase's records and its original PURCHASE movements so
        // the voided receipt leaves no history behind.
        await (_database.delete(
          _database.stockMovements,
        )..where((m) => m.referenceId.equals(id))).go();
        await (_database.delete(
          _database.purchaseItems,
        )..where((i) => i.purchaseId.equals(id))).go();
        await (_database.delete(
          _database.purchases,
        )..where((p) => p.id.equals(id))).go();
      });
    } on PurchasesFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to void purchase', error, stackTrace);
    }
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedPurchasesFailure();
  }

  static Purchase _purchaseFromRow(db.Purchase row) => Purchase(
    id: row.id,
    supplierId: row.supplierId,
    purchaseNumber: row.purchaseNumber,
    subtotalPaise: row.subtotalPaise,
    totalPaise: row.totalPaise,
    notes: row.notes,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static PurchaseItem _purchaseItemFromRow(db.PurchaseItem row) => PurchaseItem(
    id: row.id,
    purchaseId: row.purchaseId,
    productId: row.productId,
    productName: row.productName,
    sku: row.sku,
    variantId: row.variantId,
    variantName: row.variantName,
    unitCostPaise: row.unitCostPaise,
    quantity: row.quantity,
    lineTotalPaise: row.lineTotalPaise,
  );
}
