import 'package:brewflow_pos/core/database/app_database.dart'
    as db
    hide Purchase, Sale, Supplier;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/data/drift_suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Cross-Module Inventory Hardening (Phase 10 Step 8)
///
/// Proves the five real stock-changing operations — OPENING, PURCHASE, SALE,
/// ADJUSTMENT_IN, ADJUSTMENT_OUT — behave as ONE inventory system when driven
/// through their real repositories against a real in-memory SQLite database.
///
/// Locked cross-module invariants:
/// - arithmetic: stockAfter = stockBefore + quantity on every movement
/// - chain: chronological stockBefore of a movement == previous stockAfter
/// - closure: the latest movement's stockAfter == products.stock_quantity
/// - semantics: OPENING (positive, no reference, no reason), PURCHASE
///   (positive, referenceType 'PURCHASE', referenceId = purchase id, no
///   reason), SALE (negative, referenceType 'SALE', referenceId = sale id, no
///   reason), ADJUSTMENT_IN/OUT (signed, no reference, reason set)
/// - isolation: a purchase never reprices a product; sale and purchase items
///   are immutable snapshots of the moment they were written
/// - atomicity: any failed cross-module operation leaves stock, documents,
///   movements AND both number sequences untouched
/// - receipt (BF-) and purchase (PUR-) numbering are separate sequences and
///   failures never consume either
///
/// Per-phase coverage that already exists and is deliberately NOT duplicated:
/// Step 2 (billing repository), Step 5 (purchase repository), Step 6
/// (supplier repository), Step 9 (adjustment repository, rollback triggers,
/// concurrent reductions). This suite exercises the boundaries between those
/// phases — the flows one phase alone could never prove.
/// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;
  late DriftPurchaseRepository purchases;
  late DriftBillingRepository billing;
  late DriftSuppliersRepository suppliers;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    inventory = DriftInventoryRepository(database);
    movements = DriftStockMovementRepository(database);
    purchases = DriftPurchaseRepository(database);
    billing = DriftBillingRepository(database);
    suppliers = DriftSuppliersRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCategory(String id) async {
    await database
        .into(database.categories)
        .insert(
          db.CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
          mode: InsertMode.insertOrIgnore,
        );
  }

  /// Seeds a product row directly (no movements) with the given stock.
  Future<db.Product> seedProduct({
    required String id,
    String categoryId = 'cat1',
    int stock = 0,
    int sellingPricePaise = 15000,
    int? costPricePaise,
  }) async {
    await seedCategory(categoryId);
    await database
        .into(database.products)
        .insert(
          db.ProductsCompanion.insert(
            id: Value(id),
            categoryId: categoryId,
            name: 'Product $id',
            sellingPricePaise: sellingPricePaise,
            costPricePaise: Value(costPricePaise),
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
    return (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
  }

  /// Creates a product through the repository, which writes its OPENING
  /// movement at the same time.
  Future<String> createProductWithOpening(String id, int stock) async {
    await seedCategory('cat1');
    final product = await inventory.createProduct(
      categoryId: 'cat1',
      name: 'Product $id',
      sku: null,
      sellingPricePaise: 15000,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: true,
    );
    return product.id;
  }

  Future<int> productStock(String id) async {
    final row = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return row.stockQuantity;
  }

  Future<int> receiptCounter() async {
    final row = await (database.select(
      database.saleSequences,
    )..where((t) => t.id.equals('receipt'))).getSingleOrNull();
    return row?.nextValue ?? 0;
  }

  Future<int> purchaseCounter() async {
    final row = await (database.select(
      database.purchaseSequences,
    )..where((t) => t.id.equals('purchase'))).getSingleOrNull();
    return row?.nextValue ?? 0;
  }

  CartLine sellLine(String productId, int quantity, {int maxQuantity = 1000}) =>
      CartLine(
        productId: productId,
        productName: 'Product $productId',
        unitPricePaise: 15000,
        quantity: quantity,
        maxQuantity: maxQuantity,
      );

  PurchaseLine buyLine(
    String productId,
    int quantity, {
    int costPaise = 8000,
  }) => PurchaseLine(
    productId: productId,
    quantity: quantity,
    unitCostPaise: costPaise,
  );

  /// Verifies the locked chain invariants over the stored history.
  Future<void> expectChainConsistent(
    String productId,
    List<int> expectedAfter,
  ) async {
    final history = await movements.movementsFor(productId);
    expect(history, hasLength(expectedAfter.length));
    final chronological = history.reversed.toList();
    for (var i = 0; i < chronological.length; i++) {
      final current = chronological[i];
      expect(
        current.stockAfter,
        current.stockBefore + current.quantity,
        reason: 'movement $i violates stockAfter = stockBefore + quantity',
      );
      if (i > 0) {
        expect(
          current.stockBefore,
          chronological[i - 1].stockAfter,
          reason: 'movement $i breaks the before/after chain',
        );
      }
    }
    expect(chronological.map((m) => m.stockAfter).toList(), expectedAfter);
  }

  group('cross-module stock flows (real database)', () {
    test(
      'the master audit chain across OPENING, PURCHASE, SALE, ADJUSTMENT_IN '
      'and ADJUSTMENT_OUT stays exact and ends at the product stock',
      () async {
        final productId = await createProductWithOpening('p1', 100);
        final firstPurchase = await purchases.receivePurchase(
          lines: [buyLine(productId, 50)],
        );
        final firstSale = await billing.completeSale(
          lines: [sellLine(productId, 20)],
          paymentMethod: PaymentMethod.cash,
        );
        await movements.adjustStock(
          productId: productId,
          delta: 10,
          reason: StockAdjustmentReason.correction,
        );
        final secondSale = await billing.completeSale(
          lines: [sellLine(productId, 30)],
          paymentMethod: PaymentMethod.cash,
        );
        await movements.adjustStock(
          productId: productId,
          delta: -15,
          reason: StockAdjustmentReason.damage,
          note: 'spilled a bag',
        );
        final secondPurchase = await purchases.receivePurchase(
          lines: [buyLine(productId, 25)],
        );

        expect(await productStock(productId), 120);

        final history = await movements.movementsFor(productId);
        expect(history, hasLength(7));
        final chronological = history.reversed.toList();
        expect(chronological.map((m) => m.movementType).toList(), [
          StockMovementType.opening,
          StockMovementType.purchase,
          StockMovementType.sale,
          StockMovementType.adjustmentIn,
          StockMovementType.sale,
          StockMovementType.adjustmentOut,
          StockMovementType.purchase,
        ]);
        expect(chronological.map((m) => m.quantity).toList(), [
          100,
          50,
          -20,
          10,
          -30,
          -15,
          25,
        ]);
        expect(chronological.map((m) => m.stockAfter).toList(), [
          100,
          150,
          130,
          140,
          110,
          95,
          120,
        ]);

        // Movement semantics per type.
        final opening = chronological[0];
        expect(opening.referenceType, isNull);
        expect(opening.referenceId, isNull);
        expect(opening.reason, isNull);
        expect(opening.note, isNull);

        final purchaseMovement = chronological[1];
        expect(purchaseMovement.referenceType, 'PURCHASE');
        expect(purchaseMovement.referenceId, firstPurchase.id);
        expect(purchaseMovement.reason, isNull);
        expect(purchaseMovement.note, isNull);

        final saleMovement = chronological[2];
        expect(saleMovement.referenceType, 'SALE');
        expect(saleMovement.referenceId, firstSale.sale.id);
        expect(saleMovement.reason, isNull);
        expect(saleMovement.note, isNull);

        final adjustmentIn = chronological[3];
        expect(adjustmentIn.referenceType, isNull);
        expect(adjustmentIn.referenceId, isNull);
        expect(adjustmentIn.reason, StockAdjustmentReason.correction);
        expect(adjustmentIn.note, isNull);

        final secondSaleMovement = chronological[4];
        expect(secondSaleMovement.referenceType, 'SALE');
        expect(secondSaleMovement.referenceId, secondSale.sale.id);
        expect(secondSaleMovement.quantity, -30);

        final adjustmentOut = chronological[5];
        expect(adjustmentOut.reason, StockAdjustmentReason.damage);
        expect(adjustmentOut.note, 'spilled a bag');
        expect(adjustmentOut.referenceType, isNull);

        final secondPurchaseMovement = chronological[6];
        expect(secondPurchaseMovement.referenceType, 'PURCHASE');
        expect(secondPurchaseMovement.referenceId, secondPurchase.id);

        // Chain invariants.
        for (var i = 1; i < chronological.length; i++) {
          expect(chronological[i].stockBefore, chronological[i - 1].stockAfter);
        }
        // Closure: latest movement closes on the current product stock.
        expect(history.first.stockAfter, await productStock(productId));
        expect(history.first.stockAfter, 120);
      },
    );

    test(
      'purchase then sale keeps snapshots and never reprices the product',
      () async {
        await seedProduct(
          id: 'p1',
          stock: 20,
          sellingPricePaise: 15000,
          costPricePaise: 7000,
        );

        final purchase = await purchases.receivePurchase(
          lines: [buyLine('p1', 10, costPaise: 8000)],
        );
        expect(purchase.purchaseNumber, 'PUR-000001');

        final sale = await billing.completeSale(
          lines: [sellLine('p1', 5)],
          paymentMethod: PaymentMethod.cash,
        );
        expect(sale.sale.receiptNumber, 'BF-000001');

        // Receiving never touches prices: the product keeps its own values.
        final product = await (database.select(
          database.products,
        )..where((t) => t.id.equals('p1'))).getSingle();
        expect(product.stockQuantity, 25);
        expect(product.sellingPricePaise, 15000);
        expect(product.costPricePaise, 7000);

        // Both documents snapshot the trade at its own moment.
        final purchaseItems = await purchases.purchaseItems(purchase.id);
        expect(purchaseItems.single.quantity, 10);
        expect(purchaseItems.single.unitCostPaise, 8000);
        final saleItems = await billing.saleItemsFor(sale.sale.id);
        expect(saleItems.single.quantity, 5);
        expect(saleItems.single.unitPricePaise, 15000);

        // Chain: 20 -> 30 -> 25.
        await expectChainConsistent('p1', [30, 25]);

        // Later product edits never rewrite history.
        await inventory.updateProduct(
          id: 'p1',
          categoryId: 'cat1',
          name: 'Product p1',
          sku: null,
          sellingPricePaise: 18000,
          costPricePaise: 9000,
          stockQuantity: 25,
          isActive: true,
        );
        final editedProduct = await (database.select(
          database.products,
        )..where((t) => t.id.equals('p1'))).getSingle();
        expect(editedProduct.sellingPricePaise, 18000);
        expect(
          (await purchases.purchaseItems(purchase.id)).single.unitCostPaise,
          8000,
        );
        expect(
          (await billing.saleItemsFor(sale.sale.id)).single.unitPricePaise,
          15000,
        );
      },
    );

    test('sale then purchase keeps the audit chain continuous', () async {
      await seedProduct(id: 'p1', stock: 20);

      final sale = await billing.completeSale(
        lines: [sellLine('p1', 8)],
        paymentMethod: PaymentMethod.cash,
      );
      final purchase = await purchases.receivePurchase(
        lines: [buyLine('p1', 15)],
      );
      final secondSale = await billing.completeSale(
        lines: [sellLine('p1', 10)],
        paymentMethod: PaymentMethod.cash,
      );

      expect(await productStock('p1'), 17);
      await expectChainConsistent('p1', [12, 27, 17]);

      final history = await movements.movementsFor('p1');
      final chronological = history.reversed.toList();
      expect(chronological.map((m) => m.referenceType).toList(), [
        'SALE',
        'PURCHASE',
        'SALE',
      ]);
      expect(chronological[0].referenceId, sale.sale.id);
      expect(chronological[1].referenceId, purchase.id);
      expect(chronological[2].referenceId, secondSale.sale.id);
      expect(chronological[0].quantity, -8);
      expect(chronological[1].quantity, 15);
      expect(chronological[2].quantity, -10);
    });

    test('purchase then adjustments keep the chain continuous', () async {
      await seedProduct(id: 'p1', stock: 20);

      await purchases.receivePurchase(lines: [buyLine('p1', 10)]);
      await movements.adjustStock(
        productId: 'p1',
        delta: -5,
        reason: StockAdjustmentReason.damage,
        note: 'spilled',
      );
      await movements.adjustStock(
        productId: 'p1',
        delta: 7,
        reason: StockAdjustmentReason.correction,
      );

      expect(await productStock('p1'), 32);
      await expectChainConsistent('p1', [30, 25, 32]);

      final history = await movements.movementsFor('p1');
      final chronological = history.reversed.toList();
      expect(chronological.map((m) => m.movementType).toList(), [
        StockMovementType.purchase,
        StockMovementType.adjustmentOut,
        StockMovementType.adjustmentIn,
      ]);
      expect(chronological[0].referenceType, 'PURCHASE');
      expect(chronological[1].reason, StockAdjustmentReason.damage);
      expect(chronological[1].note, 'spilled');
      expect(chronological[1].referenceType, isNull);
      expect(chronological[2].reason, StockAdjustmentReason.correction);
    });

    test(
      'exact zero stock and the zero-stock purchase keep the chain exact',
      () async {
        await seedProduct(id: 'p1', stock: 10);

        await billing.completeSale(
          lines: [sellLine('p1', 10)],
          paymentMethod: PaymentMethod.cash,
        );
        expect(await productStock('p1'), 0);

        final purchase = await purchases.receivePurchase(
          lines: [buyLine('p1', 5)],
        );
        expect(await productStock('p1'), 5);
        await expectChainConsistent('p1', [0, 5]);

        final history = await movements.movementsFor('p1');
        final chronological = history.reversed.toList();
        expect(chronological[0].quantity, -10);
        expect(chronological[0].stockAfter, 0);
        expect(chronological[1].quantity, 5);
        expect(chronological[1].stockBefore, 0);
        expect(chronological[1].stockAfter, 5);
        expect(chronological[1].referenceId, purchase.id);
      },
    );

    test('zero-stock purchase writes a movement from zero', () async {
      await seedProduct(id: 'p1', stock: 0);

      final purchase = await purchases.receivePurchase(
        lines: [buyLine('p1', 10)],
      );
      expect(await productStock('p1'), 10);

      final history = await movements.movementsFor('p1');
      expect(history, hasLength(1));
      expect(history.single.movementType, StockMovementType.purchase);
      expect(history.single.stockBefore, 0);
      expect(history.single.stockAfter, 10);
      expect(history.single.referenceId, purchase.id);
    });
  });

  group('cross-module isolation and lifecycle (real database)', () {
    test(
      'a zero-stock sale fails atomically and consumes no numbers',
      () async {
        await seedProduct(id: 'p1', stock: 0);

        await expectLater(
          billing.completeSale(
            lines: [sellLine('p1', 1)],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<InsufficientStockFailure>()),
        );

        expect(await productStock('p1'), 0);
        expect(await database.select(database.sales).get(), isEmpty);
        expect(await database.select(database.saleItems).get(), isEmpty);
        expect(await database.select(database.stockMovements).get(), isEmpty);
        expect(await receiptCounter(), 0);

        // The very next purchase and sale number independently from scratch.
        final purchase = await purchases.receivePurchase(
          lines: [buyLine('p1', 10)],
        );
        expect(purchase.purchaseNumber, 'PUR-000001');
        final sale = await billing.completeSale(
          lines: [sellLine('p1', 4)],
          paymentMethod: PaymentMethod.cash,
        );
        expect(sale.sale.receiptNumber, 'BF-000001');
        expect(await productStock('p1'), 6);
        expect(await receiptCounter(), 1);
        expect(await purchaseCounter(), 1);
      },
    );

    test('multi-product flows stay isolated and interleaved', () async {
      final a = await createProductWithOpening('pa', 20);
      final b = await createProductWithOpening('pb', 10);
      final c = await createProductWithOpening('pc', 7);

      // One sale touching A and B, one purchase touching all three: the
      // single-cart/single-purchase transactions interleave per product.
      await billing.completeSale(
        lines: [sellLine(a, 5), sellLine(b, 3)],
        paymentMethod: PaymentMethod.cash,
      );
      await purchases.receivePurchase(
        lines: [buyLine(a, 2), buyLine(b, 5), buyLine(c, 10)],
      );

      expect(await productStock(a), 17);
      expect(await productStock(b), 12);
      expect(await productStock(c), 17);

      await expectChainConsistent(a, [20, 15, 17]);
      await expectChainConsistent(b, [10, 7, 12]);
      await expectChainConsistent(c, [7, 17]);

      // movementsFor is strictly per product: no cross-contamination.
      for (final id in [a, b, c]) {
        final history = await movements.movementsFor(id);
        expect(
          history.every((m) => m.productId == id),
          isTrue,
          reason: 'movementsFor($id) leaked another product',
        );
      }
      final total = await database.select(database.stockMovements).get();
      expect(total, hasLength(8));

      // The multi-line purchase still issued one number for the whole cart.
      expect(await purchaseCounter(), 1);
      expect(await receiptCounter(), 1);
    });

    test('supplier lifecycle round-trips across both modules', () async {
      await seedProduct(id: 'p1', stock: 5);
      final supplier = await suppliers.createSupplier(
        name: 'Acme Supplies',
        phone: '9845012345',
      );

      // Active: receiving succeeds.
      final first = await purchases.receivePurchase(
        lines: [buyLine('p1', 2)],
        supplierId: supplier.id,
      );
      expect(first.purchaseNumber, 'PUR-000001');
      expect(await productStock('p1'), 7);

      // Deactivate: history stays readable, receiving is blocked with no
      // writes and no consumed purchase number.
      await suppliers.setSupplierActive(supplier.id, false);
      final loaded = await purchases.purchaseById(first.id);
      expect(loaded!.supplierId, supplier.id);
      expect(loaded.purchaseNumber, 'PUR-000001');
      await expectLater(
        purchases.receivePurchase(
          lines: [buyLine('p1', 1)],
          supplierId: supplier.id,
        ),
        throwsA(isA<InactiveSupplierFailure>()),
      );
      expect(await productStock('p1'), 7);
      expect(await purchases.purchases(), hasLength(1));
      expect(await purchaseCounter(), 1);

      // Reactivate: receiving succeeds again with the next number.
      await suppliers.setSupplierActive(supplier.id, true);
      final second = await purchases.receivePurchase(
        lines: [buyLine('p1', 1)],
        supplierId: supplier.id,
      );
      expect(second.purchaseNumber, 'PUR-000002');
      expect(await productStock('p1'), 8);
      expect(await purchases.purchases(), hasLength(2));
      await expectChainConsistent('p1', [7, 8]);
    });
  });

  group(
    'cross-module atomicity, concurrency and properties (real database)',
    () {
      test(
        'a committed purchase survives a failed sale with no partial writes',
        () async {
          await seedProduct(id: 'p1', stock: 5);

          final purchase = await purchases.receivePurchase(
            lines: [buyLine('p1', 5)],
          );
          expect(await productStock('p1'), 10);

          await expectLater(
            billing.completeSale(
              lines: [sellLine('p1', 11)],
              paymentMethod: PaymentMethod.cash,
            ),
            throwsA(isA<InsufficientStockFailure>()),
          );

          expect(await productStock('p1'), 10);
          expect(await database.select(database.sales).get(), isEmpty);
          expect(await database.select(database.saleItems).get(), isEmpty);
          expect(await receiptCounter(), 0);

          // The purchase and its movement are untouched.
          final history = await movements.movementsFor('p1');
          expect(history, hasLength(1));
          expect(history.single.movementType, StockMovementType.purchase);
          expect(history.single.referenceId, purchase.id);
          expect(history.single.stockBefore, 5);
          expect(history.single.stockAfter, 10);
          expect((await purchases.purchases()).single.id, purchase.id);
          expect(await purchases.purchaseItems(purchase.id), hasLength(1));
          expect(await purchaseCounter(), 1);
        },
      );

      test(
        'concurrent purchase and sale serialize without corruption',
        () async {
          // Drift's NativeDatabase runs on one connection; the two transactions
          // serialize. Both execution orders must be safe and land on 7.
          for (final order in ['sale-first', 'purchase-first', 'racing']) {
            await seedProduct(id: 'p$order', stock: 10);
            if (order == 'sale-first') {
              await billing.completeSale(
                lines: [sellLine('p$order', 8)],
                paymentMethod: PaymentMethod.cash,
              );
              await purchases.receivePurchase(lines: [buyLine('p$order', 5)]);
            } else if (order == 'purchase-first') {
              await purchases.receivePurchase(lines: [buyLine('p$order', 5)]);
              await billing.completeSale(
                lines: [sellLine('p$order', 8)],
                paymentMethod: PaymentMethod.cash,
              );
            } else {
              final outcomes = await Future.wait<Object>([
                purchases
                    .receivePurchase(lines: [buyLine('p$order', 5)])
                    .then<Object>((value) => value),
                billing
                    .completeSale(
                      lines: [sellLine('p$order', 8)],
                      paymentMethod: PaymentMethod.cash,
                    )
                    .then<Object>((value) => value),
              ]);
              expect(outcomes.whereType<Object>(), hasLength(2));
            }
            expect(await productStock('p$order'), 7);

            final history = await movements.movementsFor('p$order');
            expect(history, hasLength(2));
            expect(history.first.stockAfter, 7);
            final chronological = history.reversed.toList();
            expect(chronological.first.stockBefore, 10);
            expect(chronological.last.stockAfter, 7);
            for (var i = 0; i < chronological.length; i++) {
              expect(
                chronological[i].stockAfter,
                chronological[i].stockBefore + chronological[i].quantity,
              );
              if (i > 0) {
                expect(
                  chronological[i].stockBefore,
                  chronological[i - 1].stockAfter,
                );
              }
            }
          }
        },
      );

      test(
        'a deterministic 22-operation sequence never breaks an invariant',
        () async {
          final productId = await createProductWithOpening('p1', 10);

          // (kind, quantity); quantities chosen so stock never goes negative.
          const ops = <(String, int)>[
            ('purchase', 8),
            ('purchase', 12),
            ('sale', 5),
            ('sale', 20),
            ('in', 15),
            ('out', 7),
            ('purchase', 30),
            ('sale', 40),
            ('out', 3),
            ('purchase', 9),
            ('sale', 9),
            ('in', 4),
            ('sale', 1),
            ('in', 7),
            ('sale', 6),
            ('purchase', 16),
            ('sale', 2),
            ('sale', 18),
            ('in', 5),
            ('purchase', 5),
            ('sale', 10),
            ('in', 22),
          ];

          var expected = 10;
          for (final (kind, quantity) in ops) {
            late StockMovement movement;
            switch (kind) {
              case 'purchase':
                await purchases.receivePurchase(
                  lines: [buyLine(productId, quantity)],
                );
                movement = (await movements.movementsFor(productId)).first;
              case 'sale':
                await billing.completeSale(
                  lines: [sellLine(productId, quantity, maxQuantity: expected)],
                  paymentMethod: PaymentMethod.cash,
                );
                movement = (await movements.movementsFor(productId)).first;
              case 'in':
                movement = await movements.adjustStock(
                  productId: productId,
                  delta: quantity,
                  reason: StockAdjustmentReason.correction,
                );
              default:
                movement = await movements.adjustStock(
                  productId: productId,
                  delta: -quantity,
                  reason: StockAdjustmentReason.damage,
                );
            }
            expected = movement.stockAfter;
            expect(
              movement.stockAfter,
              movement.stockBefore + movement.quantity,
              reason:
                  'op ($kind, $quantity) broke stockAfter = stockBefore '
                  '+ quantity',
            );
            expect(
              await productStock(productId),
              movement.stockAfter,
              reason: 'op ($kind, $quantity) left the product row out of sync',
            );
          }

          // Final closure: the whole chronological chain is consistent and the
          // latest movement closes on the stored stock (10 + 22 - 2*... = 22).
          final history = await movements.movementsFor(productId);
          expect(history, hasLength(23));
          expect(history.first.stockAfter, 22);
          expect(await productStock(productId), 22);
          final chronological = history.reversed.toList();
          expect(chronological.first.stockAfter, 10);
          for (var i = 0; i < chronological.length; i++) {
            expect(
              chronological[i].stockAfter,
              chronological[i].stockBefore + chronological[i].quantity,
            );
            if (i > 0) {
              expect(
                chronological[i].stockBefore,
                chronological[i - 1].stockAfter,
              );
            }
          }
        },
      );

      test('the cross-module failure matrix leaves stock, documents and both '
          'counters untouched', () async {
        await seedProduct(id: 'p1', stock: 10);
        final supplier = await suppliers.createSupplier(name: 'Acme Supplies');

        await expectLater(
          purchases.receivePurchase(lines: const []),
          throwsA(isA<EmptyPurchaseFailure>()),
        );
        await expectLater(
          purchases.receivePurchase(lines: [buyLine('p1', 0)]),
          throwsA(isA<InvalidPurchaseQuantityFailure>()),
        );
        await expectLater(
          purchases.receivePurchase(lines: [buyLine('p1', 2, costPaise: -1)]),
          throwsA(isA<InvalidPurchaseCostFailure>()),
        );
        await expectLater(
          purchases.receivePurchase(lines: [buyLine('missing', 2)]),
          throwsA(isA<UnknownProductFailure>()),
        );
        await expectLater(
          purchases.receivePurchase(
            lines: [buyLine('p1', 2), buyLine('p1', 1)],
          ),
          throwsA(isA<DuplicateProductLineFailure>()),
        );
        await expectLater(
          purchases.receivePurchase(
            lines: [buyLine('p1', 2)],
            supplierId: 'missing-supplier',
          ),
          throwsA(isA<UnknownSupplierFailure>()),
        );
        await suppliers.setSupplierActive(supplier.id, false);
        await expectLater(
          purchases.receivePurchase(
            lines: [buyLine('p1', 1)],
            supplierId: supplier.id,
          ),
          throwsA(isA<InactiveSupplierFailure>()),
        );
        await expectLater(
          billing.completeSale(
            lines: const [],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<EmptyCartFailure>()),
        );
        await expectLater(
          billing.completeSale(
            lines: [sellLine('p1', 11)],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<InsufficientStockFailure>()),
        );
        await expectLater(
          billing.completeSale(
            lines: [sellLine('missing', 1)],
            paymentMethod: PaymentMethod.cash,
          ),
          throwsA(isA<UnavailableProductFailure>()),
        );
        await expectLater(
          movements.adjustStock(
            productId: 'p1',
            delta: 0,
            reason: StockAdjustmentReason.correction,
          ),
          throwsA(isA<InvalidAdjustmentQuantityFailure>()),
        );
        await expectLater(
          movements.adjustStock(
            productId: 'p1',
            delta: -11,
            reason: StockAdjustmentReason.damage,
          ),
          throwsA(isA<AdjustmentInsufficientStockFailure>()),
        );
        await expectLater(
          movements.adjustStock(
            productId: 'missing',
            delta: 5,
            reason: StockAdjustmentReason.correction,
          ),
          throwsA(isA<ProductNotFoundFailure>()),
        );
        await expectLater(
          inventory.createProduct(
            categoryId: 'cat1',
            name: 'Bad Product',
            sku: null,
            sellingPricePaise: 1000,
            costPricePaise: null,
            stockQuantity: -1,
            isActive: true,
          ),
          throwsA(isA<NegativeStockFailure>()),
        );

        // Every failure above wrote nothing anywhere.
        expect(await productStock('p1'), 10);
        expect(await database.select(database.purchases).get(), isEmpty);
        expect(await database.select(database.purchaseItems).get(), isEmpty);
        expect(await database.select(database.sales).get(), isEmpty);
        expect(await database.select(database.saleItems).get(), isEmpty);
        expect(await database.select(database.stockMovements).get(), isEmpty);
        expect(await database.select(database.products).get(), hasLength(1));
        expect(await receiptCounter(), 0);
        expect(await purchaseCounter(), 0);

        // The counters were not consumed: the first real purchase is 000001.
        final purchase = await purchases.receivePurchase(
          lines: [buyLine('p1', 2)],
        );
        expect(purchase.purchaseNumber, 'PUR-000001');
        expect(await productStock('p1'), 12);
      });

      test(
        'receipt and purchase numbering stay isolated across both modules',
        () async {
          await seedProduct(id: 'p1', stock: 10);

          final p1 = await purchases.receivePurchase(lines: [buyLine('p1', 2)]);
          final s1 = await billing.completeSale(
            lines: [sellLine('p1', 1)],
            paymentMethod: PaymentMethod.cash,
          );
          final p2 = await purchases.receivePurchase(lines: [buyLine('p1', 1)]);
          final s2 = await billing.completeSale(
            lines: [sellLine('p1', 2)],
            paymentMethod: PaymentMethod.cash,
          );
          expect(p1.purchaseNumber, 'PUR-000001');
          expect(p2.purchaseNumber, 'PUR-000002');
          expect(s1.sale.receiptNumber, 'BF-000001');
          expect(s2.sale.receiptNumber, 'BF-000002');
          expect(await purchaseCounter(), 2);
          expect(await receiptCounter(), 2);

          // A failed purchase consumes no purchase number, a failed sale no
          // receipt number — and neither touches the other sequence.
          await expectLater(
            purchases.receivePurchase(lines: [buyLine('missing', 1)]),
            throwsA(isA<UnknownProductFailure>()),
          );
          await expectLater(
            billing.completeSale(
              lines: [sellLine('p1', 99)],
              paymentMethod: PaymentMethod.cash,
            ),
            throwsA(isA<InsufficientStockFailure>()),
          );
          expect(await purchaseCounter(), 2);
          expect(await receiptCounter(), 2);

          final p3 = await purchases.receivePurchase(lines: [buyLine('p1', 1)]);
          final s3 = await billing.completeSale(
            lines: [sellLine('p1', 1)],
            paymentMethod: PaymentMethod.cash,
          );
          expect(p3.purchaseNumber, 'PUR-000003');
          expect(s3.sale.receiptNumber, 'BF-000003');
        },
      );
    },
  );
}
