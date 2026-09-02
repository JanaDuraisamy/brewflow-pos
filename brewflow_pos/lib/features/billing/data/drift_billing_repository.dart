import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/sale_items_dao.dart';
import 'package:brewflow_pos/core/database/daos/sales_dao.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Billing Repository
///
/// Implements [BillingRepository] on the local Drift database.
///
/// Checkout runs inside a single transaction: stock entities (products, and
/// variants for variant lines) are re-validated against the database
/// (existence, active flag, stock), stock is deducted with a database-level
/// `WHERE stock_quantity >= ?` guard on the exact entity the line sells, the
/// receipt sequence is consumed with UPDATE ... RETURNING, the sale header
/// plus snapshot line items are inserted, and one SALE stock movement per
/// line (with `referenceType = 'SALE'`, the sale id and the variant id when
/// the line sells a variant) is appended to the audit trail — everything
/// commits together or rolls back together.
///
/// Sync: when a [SyncOutboxCoordinator] is provided, the sale and sale items
/// are appended to the durable outbox IN THE SAME TRANSACTION as the business
/// change; without one the repository behaves exactly as before.
///
/// Movement semantics follow Phase 9 conventions: [quantity] is the signed
/// delta (`-line.quantity`), [stockBefore]/[stockAfter] are the absolute
/// levels observed inside the transaction, and the invariant
/// `stockAfter = stockBefore + quantity` holds for every row.
/// ---------------------------------------------------------------------------

final class DriftBillingRepository implements BillingRepository {
  DriftBillingRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _database = database,
       _sales = SalesDao(database),
       _saleItems = SaleItemsDao(database),
       _movements = StockMovementsDao(database),
       _outbox = outboxCoordinator;

  static const String tag = 'Billing';

  /// Fixed id of the single receipt-counter row in sale_sequences.
  static const String _receiptSequenceId = 'receipt';

  final db.AppDatabase _database;
  final SalesDao _sales;
  final SaleItemsDao _saleItems;
  final StockMovementsDao _movements;
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<CompletedSale> completeSale({
    required List<CartLine> lines,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod? paymentMethod,
    String? customerId,
    String? shopId,
  }) async {
    if (lines.isEmpty) {
      throw const EmptyCartFailure();
    }
    if (paymentStatus == PaymentStatus.notPaid && customerId == null) {
      throw const MissingCustomerForCreditSaleFailure();
    }
    if (paymentStatus == PaymentStatus.paid && paymentMethod == null) {
      throw const InvalidPaymentFailure();
    }
    try {
      final resolvedShopId = await resolveWritableShopId(_database, shopId);
      if (_outbox == null) {
        return await _database.transaction(
          () => _checkoutCore(
            lines,
            paymentStatus,
            paymentMethod,
            customerId,
            resolvedShopId,
          ),
        );
      }
      return await _outbox.run(
        write: () => _checkoutCore(
          lines,
          paymentStatus,
          paymentMethod,
          customerId,
          resolvedShopId,
        ),
        snapshots: (result, ctx) async {
          final appends = <OutboxAppend>[
            OutboxAppend(
              entity: MasterEntity.sale,
              entityId: result.sale.id,
              payload: SyncSale(
                id: result.sale.id,
                shopId: ctx.shopId,
                customerId: result.sale.customerId,
                receiptNumber: result.sale.receiptNumber,
                subtotalPaise: result.sale.subtotalPaise,
                totalPaise: result.sale.totalPaise,
                paymentMethod: result.sale.paymentMethod?.dbValue,
                paymentStatus: result.sale.paymentStatus.dbValue,
                createdAt: result.sale.createdAt,
              ).toJson(),
            ),
          ];
          for (final item in result.items) {
            appends.add(
              OutboxAppend(
                entity: MasterEntity.saleItem,
                entityId: item.id,
                payload: SyncSaleItem(
                  id: item.id,
                  shopId: ctx.shopId,
                  saleId: item.saleId,
                  productId: item.productId,
                  variantId: item.variantId,
                  productName: item.productName,
                  variantName: item.variantName,
                  sku: item.sku,
                  unitPricePaise: item.unitPricePaise,
                  quantity: item.quantity,
                  lineTotalPaise: item.lineTotalPaise,
                ).toJson(),
              ),
            );
          }

          // The checkout deducted inventory for every tracked line. Those
          // stock changes live only on this device unless a Product /
          // ProductVariant row is enqueued with the reduced levels, so append
          // them here — inside the same transaction — to propagate to the
          // cloud and, from there, to the other device. Untracked (NONE) lines
          // were never deducted and contribute nothing.
          final productIds = result.items.map((i) => i.productId).toSet();
          final affectedProducts = <String, db.Product>{
            for (final row in await (_database.select(
              _database.products,
            )..where((t) => t.id.isIn(productIds))).get())
              row.id: row,
          };
          final variantIds = result.items
              .where((i) => i.variantId != null)
              .map((i) => i.variantId!)
              .toSet();
          final variants = variantIds.isEmpty
              ? const <db.ProductVariant>[]
              : await (_database.select(
                  _database.productVariants,
                )..where((t) => t.id.isIn(variantIds))).get();
          final variantsById = {for (final v in variants) v.id: v};

          for (final product in affectedProducts.values) {
            final tracked = product.stockUnit != StockUnit.none.dbValue;
            final hasVariants = variantsById.values.any(
              (v) => v.productId == product.id,
            );
            if (!tracked) {
              continue;
            }
            if (hasVariants) {
              for (final variant in variantsById.values.where(
                (v) => v.productId == product.id,
              )) {
                appends.add(_stockVariantAppend(variant, ctx));
              }
            } else {
              appends.add(_stockProductAppend(product, ctx));
            }
          }
          return appends;
        },
      );
    } on BillingFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      AppLog.error(
        'Failed to complete sale',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedBillingFailure();
    }
  }

  Future<CompletedSale> _checkoutCore(
    List<CartLine> lines,
    PaymentStatus paymentStatus,
    PaymentMethod? paymentMethod,
    String? customerId,
    String shopId,
  ) async {
    final now = DateTime.now().toUtc();
    final saleId = const Uuid().v4();

    // Re-validate the customer before anything is written, so a bad
    // customer reference never consumes a receipt number or stock.
    await _validateCustomer(customerId);

    // Re-validate every line against the current database, never the cart.
    final entitiesByKey = await _entitiesById(lines);
    final ordered = <({CartLine line, int lineTotal})>[];
    final movements = <db.StockMovementsCompanion>[];
    for (final line in lines) {
      final entity = entitiesByKey[line.keyId];
      final product = entity?.product;
      final variant = entity?.variant;
      if (product == null || !product.isActive) {
        throw UnavailableProductFailure(line.productName);
      }
      // A variant line must reference an existing, active variant; a plain
      // line must not be double-deducted through a stale variant reference.
      if (line.variantId != null && (variant == null || !variant.isActive)) {
        throw UnavailableProductFailure(line.productName);
      }
      // stockUnit NONE = made-to-order / untracked: never stock-guarded,
      // never deducted, never moved. The schema documents this semantic;
      // checkout simply skips the inventory leg for such products.
      final tracked = product.stockUnit != StockUnit.none.dbValue;
      final int stockEntityStock;
      if (tracked) {
        stockEntityStock = variant?.stockQuantity ?? product.stockQuantity;
        if (stockEntityStock < line.quantity) {
          throw InsufficientStockFailure(line.productName);
        }
      } else {
        stockEntityStock = 0;
      }
      final lineTotal = Money.multiplyPaise(line.unitPricePaise, line.quantity);
      if (lineTotal == null) {
        throw const UnexpectedBillingFailure(
          'Line total exceeds the safe ceiling.',
        );
      }

      // Conditional, race-safe deduction on the exact stock entity the line
      // sells: the guard is re-evaluated by SQLite against the committed
      // value at write time. A concurrent change that leaves insufficient
      // stock makes this update match zero rows. Untracked (NONE) products
      // skip deduction and the SALE movement entirely — no artificial
      // inventory is ever created for made-to-order items.
      if (tracked) {
        final int updated;
        if (variant != null) {
          updated =
              await (_database.update(_database.productVariants)..where(
                    (t) =>
                        t.id.equals(variant.id) &
                        t.stockQuantity.isBiggerOrEqualValue(line.quantity),
                  ))
                  .write(
                    db.ProductVariantsCompanion(
                      stockQuantity: Value(
                        variant.stockQuantity - line.quantity,
                      ),
                      updatedAt: Value(now),
                    ),
                  );
        } else {
          updated =
              await (_database.update(_database.products)..where(
                    (t) =>
                        t.id.equals(line.productId) &
                        t.stockQuantity.isBiggerOrEqualValue(line.quantity),
                  ))
                  .write(
                    db.ProductsCompanion(
                      stockQuantity: Value(
                        product.stockQuantity - line.quantity,
                      ),
                      updatedAt: Value(now),
                    ),
                  );
        }
        if (updated != 1) {
          throw InsufficientStockFailure(line.productName);
        }
      }

      ordered.add((line: line, lineTotal: lineTotal));

      // One SALE movement per tracked line, inside the same transaction.
      // stockBefore is the level read at validation (the cart guarantees each
      // stock entity appears in exactly one line), and stockAfter is the
      // value the deduction just committed to — so
      // `stockAfter = stockBefore + quantity` holds by construction. The sale
      // id links the movement to its sale for audit purposes (no FK by
      // design). Untracked lines record no movement at all.
      if (tracked) {
        movements.add(
          db.StockMovementsCompanion.insert(
            shopId: Value(shopId),
            productId: line.productId,
            variantId: Value(line.variantId),
            movementType: StockMovementType.sale.dbValue,
            quantity: -line.quantity,
            stockBefore: stockEntityStock,
            stockAfter: stockEntityStock - line.quantity,
            reason: const Value(null),
            note: const Value(null),
            referenceType: Value(StockMovementType.sale.dbValue),
            referenceId: Value(saleId),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }
    }

    final subtotal = Money.sumPaise(ordered.map((e) => e.lineTotal));
    if (subtotal == null) {
      throw const UnexpectedBillingFailure(
        'Sale total exceeds the safe ceiling.',
      );
    }

    final receiptNumber = await _nextReceiptNumber(shopId);
    await _database
        .into(_database.sales)
        .insert(
          db.SalesCompanion.insert(
            id: Value(saleId),
            shopId: Value(shopId),
            receiptNumber: receiptNumber,
            customerId: Value(customerId),
            subtotalPaise: subtotal,
            totalPaise: subtotal,
            // Credit sales persist no payment method — the debt lives in the
            // customer ledger, derived from this sale's total minus payments.
            paymentMethod: Value(
              paymentStatus == PaymentStatus.notPaid
                  ? null
                  : paymentMethod!.dbValue,
            ),
            paymentStatus: Value(paymentStatus.dbValue),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    await _database.batch((batch) {
      batch.insertAll(_database.saleItems, [
        for (final entry in ordered)
          db.SaleItemsCompanion.insert(
            id: Value(const Uuid().v4()),
            shopId: Value(shopId),
            saleId: saleId,
            productId: entry.line.productId,
            variantId: Value(entry.line.variantId),
            productName: entry.line.productName,
            variantName: Value(entry.line.variantName),
            sku: Value(entry.line.sku),
            unitPricePaise: entry.line.unitPricePaise,
            quantity: entry.line.quantity,
            lineTotalPaise: entry.lineTotal,
          ),
      ]);
    });

    await _movements.insertAll(movements);

    final sale = Sale(
      id: saleId,
      receiptNumber: receiptNumber,
      subtotalPaise: subtotal,
      totalPaise: subtotal,
      paymentStatus: paymentStatus,
      paymentMethod: paymentStatus == PaymentStatus.notPaid
          ? null
          : paymentMethod,
      createdAt: now,
      updatedAt: now,
      customerId: customerId,
    );
    final persistedItems = (await _saleItems.bySale(
      saleId,
    )).map(_saleItemFromRow).toList();
    return CompletedSale(sale: sale, items: persistedItems);
  }

  /// Loads the stock entities behind every line in one round trip: the
  /// products and (for variant lines) the variants, keyed by the line's
  /// stock-entity id ([CartLine.keyId]). A missing product surfaces as a
  /// null entry so the caller can raise the domain failure.
  Future<Map<String, ({db.Product? product, db.ProductVariant? variant})>>
  _entitiesById(List<CartLine> lines) async {
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
        line.keyId: (
          product: products[line.productId],
          variant: line.variantId == null ? null : variants[line.variantId],
        ),
    };
  }

  /// No-op for walk-in sales (null). For customer-linked sales the customer
  /// must still exist and be active; anything else fails the whole checkout.
  Future<void> _validateCustomer(String? customerId) async {
    if (customerId == null) {
      return;
    }
    final row = await (_database.select(
      _database.customers,
    )..where((t) => t.id.equals(customerId))).getSingleOrNull();
    if (row == null) {
      throw const CustomerNotFoundFailure();
    }
    if (!row.isActive) {
      throw const InactiveCustomerFailure();
    }
  }

  /// Builds the post-checkout Product outbox entry for a tracked, non-variant
  /// line whose stock was just deducted. Carries the reduced level so the
  /// cloud and the other device converge on the exact same stock.
  static OutboxAppend _stockProductAppend(
    db.Product product,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.product,
    entityId: product.id,
    payload: SyncProduct(
      id: product.id,
      shopId: context.shopId,
      categoryId: product.categoryId,
      name: product.name,
      sku: product.sku,
      sellingPricePaise: product.sellingPricePaise,
      costPricePaise: product.costPricePaise,
      stockQuantity: product.stockQuantity,
      stockUnit: switch (product.stockUnit) {
        'NONE' => SyncStockUnit.none,
        'ML' => SyncStockUnit.ml,
        'GRAM' => SyncStockUnit.gram,
        'KG' => SyncStockUnit.kg,
        _ => SyncStockUnit.count,
      },
      lowStockMode: switch (product.lowStockMode) {
        'CUSTOM' => SyncLowStockMode.custom,
        'OFF' => SyncLowStockMode.off,
        _ => SyncLowStockMode.useDefault,
      },
      lowStockThreshold: product.lowStockThreshold,
      membershipEnabled: product.membershipEnabled,
      memberPricePaise: product.memberPricePaise,
      isActive: product.isActive,
      createdAt: product.createdAt,
    ).toJson(),
  );

  /// Builds the post-checkout ProductVariant outbox entry for a tracked
  /// variant line whose stock was just deducted on the variant entity.
  static OutboxAppend _stockVariantAppend(
    db.ProductVariant variant,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.productVariant,
    entityId: variant.id,
    payload: SyncProductVariant(
      id: variant.id,
      shopId: context.shopId,
      productId: variant.productId,
      name: variant.name,
      sku: variant.sku,
      sellingPricePaise: variant.sellingPricePaise,
      costPricePaise: variant.costPricePaise,
      stockQuantity: variant.stockQuantity,
      lowStockMode: switch (variant.lowStockMode) {
        'CUSTOM' => SyncLowStockMode.custom,
        'OFF' => SyncLowStockMode.off,
        _ => SyncLowStockMode.useDefault,
      },
      lowStockThreshold: variant.lowStockThreshold,
      membershipEnabled: variant.membershipEnabled,
      memberPricePaise: variant.memberPricePaise,
      isActive: variant.isActive,
      createdAt: variant.createdAt,
    ).toJson(),
  );

  /// Allocates a gapless receipt number scoped to [shopId].  The per-shop
  /// counter lives in `sale_sequences` with composite key `(id, shop_id)`.
  /// On first allocation we seed the counter and heal forward to the highest
  /// receipt number already in use.  Runs inside the checkout transaction,
  /// so a rolled-back checkout never consumes a value.
  Future<String> _nextReceiptNumber(String shopId) async {
    await _database.customStatement(
      'INSERT OR IGNORE INTO sale_sequences (id, shop_id, next_value) VALUES (?, ?, 0)',
      [_receiptSequenceId, shopId],
    );
    final row = await _database
        .customSelect(
          'UPDATE sale_sequences SET next_value = ('
          '  SELECT MAX(x) FROM ('
          '    SELECT next_value + 1 AS x FROM sale_sequences WHERE id = ? AND shop_id = ?'
          '    UNION ALL'
          '    SELECT MAX(CAST(SUBSTR(receipt_number, ?) AS INTEGER)) + 1 AS x'
          '      FROM sales'
          '     WHERE receipt_number IS NOT NULL AND receipt_number LIKE ?'
          '       AND shop_id = ?'
          '    UNION ALL'
          '    SELECT 0 AS x'
          '  )'
          ') WHERE id = ? AND shop_id = ? RETURNING next_value',
          variables: [
            Variable.withString(_receiptSequenceId),
            Variable.withString(shopId),
            Variable.withInt(AppConstants.receiptPrefix.length + 1),
            Variable.withString('${AppConstants.receiptPrefix}%'),
            Variable.withString(shopId),
            Variable.withString(_receiptSequenceId),
            Variable.withString(shopId),
          ],
        )
        .getSingle();
    final nextValue = row.read<int>('next_value');
    return '${AppConstants.receiptPrefix}${nextValue.toString().padLeft(6, '0')}';
  }

  @override
  Future<Sale?> saleById(String id) async {
    try {
      final row = await _sales.byId(id);
      return row == null ? null : _saleFromRow(row);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sale', error, stackTrace);
    }
  }

  @override
  Future<List<SaleItem>> saleItemsFor(String saleId) async {
    try {
      final rows = await _saleItems.bySale(saleId);
      return rows.map(_saleItemFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sale items', error, stackTrace);
    }
  }

  @override
  Future<List<Sale>> sales() async {
    try {
      final rows = await _sales.all();
      return rows.map(_saleFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load sales', error, stackTrace);
    }
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedBillingFailure();
  }

  @override
  Future<void> voidSale(String saleId) async {
    Future<void> write() async {
      final saleRow = await _sales.byId(saleId);
      if (saleRow == null) {
        throw const SaleNotFoundFailure();
      }
      if (saleRow.voided) {
        throw const SaleAlreadyVoidedFailure();
      }
      final now = DateTime.now().toUtc();
      final nowStr = now.toIso8601String();
      final items = await _saleItems.bySale(saleId);
      for (final item in items) {
        if (item.variantId != null) {
          await _database.customStatement(
            'UPDATE product_variants SET stock_quantity = '
            'stock_quantity + ?, updated_at = ? WHERE id = ?',
            [item.quantity, nowStr, item.variantId],
          );
        } else {
          await _database.customStatement(
            'UPDATE products SET stock_quantity = stock_quantity + ?, '
            'updated_at = ? WHERE id = ?',
            [item.quantity, nowStr, item.productId],
          );
        }
      }
      final payments =
          await (_database.select(_database.customerPayments)..where(
                (t) => t.saleId.equals(saleId) & t.reversed.equals(false),
              ))
              .get();
      for (final payment in payments) {
        await (_database.update(
          _database.customerPayments,
        )..where((t) => t.id.equals(payment.id))).write(
          db.CustomerPaymentsCompanion(
            reversed: const Value(true),
            reversedAt: Value(now),
          ),
        );
      }
      await (_database.update(
        _database.sales,
      )..where((t) => t.id.equals(saleId))).write(
        db.SalesCompanion(
          voided: const Value(true),
          voidedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    }

    try {
      final outbox = _outbox;
      if (outbox == null) {
        await _database.transaction(write);
        return;
      }
      await outbox.run(
        write: () => _database.transaction(write),
        snapshots: (context, ctx) async {
          // Read the voided sale row and any reversed payments after the
          // transaction so the outbox payload reflects the committed state.
          final saleRow = await (_database.select(
            _database.sales,
          )..where((t) => t.id.equals(saleId))).getSingle();
          final salePayload = SyncSale(
            id: saleRow.id,
            shopId: ctx.shopId,
            customerId: saleRow.customerId,
            receiptNumber: saleRow.receiptNumber,
            subtotalPaise: saleRow.subtotalPaise,
            totalPaise: saleRow.totalPaise,
            paymentMethod: saleRow.paymentMethod,
            paymentStatus: saleRow.paymentStatus,
            createdAt: saleRow.createdAt,
            voided: saleRow.voided,
            voidedAt: saleRow.voidedAt,
          ).toJson();
          final out = <OutboxAppend>[
            OutboxAppend(
              entity: MasterEntity.sale,
              entityId: saleId,
              payload: salePayload,
            ),
          ];
          final payments = await (_database.select(
            _database.customerPayments,
          )..where((t) => t.saleId.equals(saleId))).get();
          for (final p in payments.where((e) => e.reversed)) {
            out.add(
              OutboxAppend(
                entity: MasterEntity.customerPayment,
                entityId: p.id,
                payload: SyncCustomerPayment(
                  id: p.id,
                  shopId: ctx.shopId,
                  customerId: p.customerId,
                  saleId: p.saleId,
                  amountPaise: p.amountPaise,
                  paymentMethod: p.paymentMethod,
                  note: p.note,
                  paidAt: p.paidAt,
                  reversed: p.reversed,
                  reversedAt: p.reversedAt,
                  createdAt: p.createdAt,
                ).toJson(),
              ),
            );
          }
          return out;
        },
      );
    } on BillingFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to void sale', error, stackTrace);
    }
  }

  static Sale _saleFromRow(db.Sale row) => Sale(
    id: row.id,
    receiptNumber: row.receiptNumber,
    subtotalPaise: row.subtotalPaise,
    totalPaise: row.totalPaise,
    paymentStatus: PaymentStatus.fromDbValue(row.paymentStatus)!,
    paymentMethod: row.paymentMethod == null
        ? null
        : PaymentMethod.fromDbValue(row.paymentMethod!),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    customerId: row.customerId,
    voided: row.voided,
    voidedAt: row.voidedAt,
  );

  static SaleItem _saleItemFromRow(db.SaleItem row) => SaleItem(
    id: row.id,
    saleId: row.saleId,
    productId: row.productId,
    productName: row.productName,
    sku: row.sku,
    variantId: row.variantId,
    variantName: row.variantName,
    unitPricePaise: row.unitPricePaise,
    quantity: row.quantity,
    lineTotalPaise: row.lineTotalPaise,
  );
}
