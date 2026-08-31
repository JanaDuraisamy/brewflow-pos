import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Variant checkout tests against the real Drift stack: the checkout must
/// deduct from the exact variant the line sells, write one SALE movement per
/// variant line and roll back completely (stock, movements, receipt number)
/// when any variant line cannot be fulfilled.
void main() {
  late AppDatabase database;
  late DriftBillingRepository repository;
  late DriftStockMovementRepository movements;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftBillingRepository(database);
    movements = DriftStockMovementRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedVariantProduct({
    required String id,
    required String name,
    required List<({String id, String name, int stock, bool active})> variants,
    int productStock = 0,
  }) async {
    await database
        .into(database.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: 'Category'));
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sellingPricePaise: 20000,
            stockQuantity: Value(productStock),
            isActive: const Value(true),
          ),
        );
    for (final variant in variants) {
      await database
          .into(database.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: Value(variant.id),
              productId: id,
              name: variant.name,
              sellingPricePaise: 15000,
              stockQuantity: Value(variant.stock),
              isActive: Value(variant.active),
            ),
          );
    }
  }

  CartLine variantLine({
    required String productId,
    required String productName,
    required String variantId,
    required String variantName,
    required int quantity,
    int pricePaise = 15000,
    int maxQuantity = 99,
    int? memberPricePaise,
  }) => CartLine(
    productId: productId,
    productName: productName,
    variantId: variantId,
    variantName: variantName,
    unitPricePaise: pricePaise,
    quantity: quantity,
    maxQuantity: maxQuantity,
    memberPricePaise: memberPricePaise,
  );

  CartLine productLine({
    required String productId,
    required String productName,
    required int quantity,
    int pricePaise = 12000,
    int maxQuantity = 99,
  }) => CartLine(
    productId: productId,
    productName: productName,
    unitPricePaise: pricePaise,
    quantity: quantity,
    maxQuantity: maxQuantity,
  );

  Future<int> variantStock(String variantId) async {
    final row = await (database.select(
      database.productVariants,
    )..where((t) => t.id.equals(variantId))).getSingle();
    return row.stockQuantity;
  }

  Future<int> rawProductStock(String productId) async {
    final row = await (database.select(
      database.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    return row.stockQuantity;
  }

  Future<int> countSales() async {
    final query = database.selectOnly(database.sales)
      ..addColumns([database.sales.id.count()]);
    return query.map((row) => row.read(database.sales.id.count())!).getSingle();
  }

  Future<int> countSaleItems() async {
    final query = database.selectOnly(database.saleItems)
      ..addColumns([database.saleItems.id.count()]);
    return query
        .map((row) => row.read(database.saleItems.id.count())!)
        .getSingle();
  }

  Future<int> countMovements() async {
    final query = database.selectOnly(database.stockMovements)
      ..addColumns([database.stockMovements.id.count()]);
    return query
        .map((row) => row.read(database.stockMovements.id.count())!)
        .getSingle();
  }

  group('variant checkout', () {
    test('a variant sale deducts only the variant it sells', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [
          (id: 'v1', name: 'Small', stock: 5, active: true),
          (id: 'v2', name: 'Large', stock: 3, active: true),
        ],
      );

      final completed = await repository.completeSale(
        lines: [
          variantLine(
            productId: 'p1',
            productName: 'Coffee',
            variantId: 'v1',
            variantName: 'Small',
            quantity: 2,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      expect(completed.items.single.variantId, 'v1');
      expect(await variantStock('v1'), 3);
      expect(await variantStock('v2'), 3);
      expect(await rawProductStock('p1'), 0);
    });

    test(
      'writes one SALE movement per variant line with the sale reference',
      () async {
        await seedVariantProduct(
          id: 'p1',
          name: 'Coffee',
          variants: [
            (id: 'v1', name: 'Small', stock: 5, active: true),
            (id: 'v2', name: 'Large', stock: 3, active: true),
          ],
        );

        final completed = await repository.completeSale(
          lines: [
            variantLine(
              productId: 'p1',
              productName: 'Coffee',
              variantId: 'v1',
              variantName: 'Small',
              quantity: 2,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );

        final history = await movements.movementsFor('p1', variantId: 'v1');
        expect(history, hasLength(1));
        expect(history.single.movementType, StockMovementType.sale);
        expect(history.single.variantId, 'v1');
        expect(history.single.quantity, -2);
        expect(history.single.stockBefore, 5);
        expect(history.single.stockAfter, 3);
        expect(history.single.referenceType, 'SALE');
        expect(history.single.referenceId, completed.sale.id);
      },
    );

    test('the sale item snapshots the variant identity and name', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [(id: 'v1', name: 'Small', stock: 5, active: true)],
      );

      final completed = await repository.completeSale(
        lines: [
          variantLine(
            productId: 'p1',
            productName: 'Coffee',
            variantId: 'v1',
            variantName: 'Small',
            quantity: 1,
          ),
        ],
        paymentMethod: PaymentMethod.upi,
      );

      final item = completed.items.single;
      expect(item.variantId, 'v1');
      expect(item.variantName, 'Small');
      expect(item.productId, 'p1');
      expect(item.unitPricePaise, 15000);
      expect(item.lineTotalPaise, 15000);
      expect(completed.sale.totalPaise, 15000);
    });

    test('selling the last units of a variant is allowed', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [(id: 'v1', name: 'Small', stock: 2, active: true)],
      );

      final completed = await repository.completeSale(
        lines: [
          variantLine(
            productId: 'p1',
            productName: 'Coffee',
            variantId: 'v1',
            variantName: 'Small',
            quantity: 2,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      expect(await variantStock('v1'), 0);
      expect(completed.items.single.quantity, 2);
      final history = await movements.movementsFor('p1', variantId: 'v1');
      expect(history.single.stockAfter, 0);
    });

    test('insufficient variant stock rolls back everything', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [
          (id: 'v1', name: 'Small', stock: 1, active: true),
          (id: 'v2', name: 'Large', stock: 3, active: true),
        ],
      );

      await expectLater(
        repository.completeSale(
          lines: [
            variantLine(
              productId: 'p1',
              productName: 'Coffee',
              variantId: 'v1',
              variantName: 'Small',
              quantity: 2,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(await countSales(), 0);
      expect(await countSaleItems(), 0);
      expect(await countMovements(), 0);
      expect(await variantStock('v1'), 1);
      expect(await variantStock('v2'), 3);

      // The failed attempt must not have consumed a receipt number.
      final later = await repository.completeSale(
        lines: [
          variantLine(
            productId: 'p1',
            productName: 'Coffee',
            variantId: 'v2',
            variantName: 'Large',
            quantity: 1,
          ),
        ],
        paymentMethod: PaymentMethod.cash,
      );
      expect(later.sale.receiptNumber, 'BF-000001');
    });

    test('an inactive variant cannot be sold and rolls back', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [(id: 'v1', name: 'Small', stock: 5, active: false)],
      );

      await expectLater(
        repository.completeSale(
          lines: [
            variantLine(
              productId: 'p1',
              productName: 'Coffee',
              variantId: 'v1',
              variantName: 'Small',
              quantity: 1,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        ),
        throwsA(isA<UnavailableProductFailure>()),
      );

      expect(await countSales(), 0);
      expect(await countMovements(), 0);
      expect(await variantStock('v1'), 5);
    });

    test('a mixed cart deducts each stock entity exactly once', () async {
      await seedVariantProduct(
        id: 'p1',
        name: 'Coffee',
        variants: [(id: 'v1', name: 'Small', stock: 5, active: true)],
      );
      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p2'),
              categoryId: 'p1',
              name: 'Milk',
              sellingPricePaise: 12000,
              stockQuantity: Value(4),
              isActive: const Value(true),
            ),
          );

      final completed = await repository.completeSale(
        lines: [
          variantLine(
            productId: 'p1',
            productName: 'Coffee',
            variantId: 'v1',
            variantName: 'Small',
            quantity: 2,
          ),
          productLine(productId: 'p2', productName: 'Milk', quantity: 1),
        ],
        paymentMethod: PaymentMethod.cash,
      );

      expect(await variantStock('v1'), 3);
      expect(await rawProductStock('p2'), 3);
      expect(completed.sale.totalPaise, 15000 * 2 + 12000);

      final variantMovements = await movements.movementsFor(
        'p1',
        variantId: 'v1',
      );
      expect(variantMovements.single.variantId, 'v1');
      final productMovements = await movements.movementsFor('p2');
      expect(productMovements.single.variantId, isNull);
    });

    test(
      'a member-priced variant line is charged at its member price',
      () async {
        await seedVariantProduct(
          id: 'p1',
          name: 'Coffee',
          variants: [(id: 'v1', name: 'Small', stock: 5, active: true)],
        );

        final completed = await repository.completeSale(
          lines: [
            variantLine(
              productId: 'p1',
              productName: 'Coffee',
              variantId: 'v1',
              variantName: 'Small',
              quantity: 2,
              pricePaise: 7500,
              memberPricePaise: 7500,
            ),
          ],
          paymentMethod: PaymentMethod.cash,
        );

        final item = completed.items.single;
        expect(item.unitPricePaise, 7500);
        expect(item.lineTotalPaise, 15000);
        expect(completed.sale.totalPaise, 15000);
        expect(await variantStock('v1'), 3);
      },
    );
  });
}
