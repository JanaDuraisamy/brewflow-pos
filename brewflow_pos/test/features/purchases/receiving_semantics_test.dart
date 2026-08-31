import 'package:brewflow_pos/core/database/app_database.dart' hide Purchase;
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/purchases/data/drift_purchase_repository.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Receiving semantics against the real Drift stack.
///
/// A variant receive line must land in the exact variant (never the product
/// row), write one PURCHASE movement carrying the variant id and purchase
/// reference, and — like any stock change — go through movements instead of
/// silently mutating cost prices.
void main() {
  late AppDatabase database;
  late DriftPurchaseRepository repository;
  late DriftStockMovementRepository movements;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftPurchaseRepository(database);
    movements = DriftStockMovementRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 10,
    bool active = true,
    String? sku,
    int? costPaise,
  }) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            categoryId: id,
            name: name,
            sku: Value(sku),
            sellingPricePaise: 12000,
            costPricePaise: Value(costPaise),
            stockQuantity: Value(stock),
            isActive: Value(active),
          ),
        );
  }

  Future<void> seedSupplier({required String id, bool active = true}) async {
    await database
        .into(database.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: Value(id),
            name: 'Supplier $id',
            isActive: Value(active),
          ),
        );
  }

  Future<void> seedVariant({
    required String id,
    required String productId,
    required String name,
    int stock = 10,
    int? costPaise,
  }) async {
    await database
        .into(database.productVariants)
        .insert(
          ProductVariantsCompanion.insert(
            id: Value(id),
            productId: productId,
            name: name,
            sellingPricePaise: 15000,
            costPricePaise: Value(costPaise),
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
  }

  PurchaseLine line({
    required String productId,
    required int quantity,
    int costPaise = 12000,
    String? variantId,
  }) => PurchaseLine(
    productId: productId,
    quantity: quantity,
    unitCostPaise: costPaise,
    variantId: variantId,
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

  Future<int?> rawProductCost(String productId) async {
    final row = await (database.select(
      database.products,
    )..where((t) => t.id.equals(productId))).getSingle();
    return row.costPricePaise;
  }

  Future<int?> rawVariantCost(String variantId) async {
    final row = await (database.select(
      database.productVariants,
    )..where((t) => t.id.equals(variantId))).getSingle();
    return row.costPricePaise;
  }

  group('variant receiving', () {
    test(
      'a variant receive lands in the variant, never the product row',
      () async {
        await seedSupplier(id: 's1');
        await seedProduct(id: 'p1', name: 'Coffee', stock: 1);
        await seedVariant(id: 'v1', productId: 'p1', name: 'Small', stock: 5);
        await seedVariant(id: 'v2', productId: 'p1', name: 'Large', stock: 3);

        await repository.receivePurchase(
          supplierId: 's1',
          lines: [line(productId: 'p1', quantity: 4, variantId: 'v1')],
        );

        expect(await variantStock('v1'), 9);
        expect(await variantStock('v2'), 3);
        expect(await rawProductStock('p1'), 1);
      },
    );

    test(
      'writes one PURCHASE movement per variant line with the reference',
      () async {
        await seedSupplier(id: 's1');
        await seedProduct(id: 'p1', name: 'Coffee', stock: 1);
        await seedVariant(id: 'v1', productId: 'p1', name: 'Small', stock: 5);

        final purchase = await repository.receivePurchase(
          supplierId: 's1',
          lines: [line(productId: 'p1', quantity: 4, variantId: 'v1')],
        );

        final history = await movements.movementsFor('p1', variantId: 'v1');
        expect(history, hasLength(1));
        expect(history.single.movementType, StockMovementType.purchase);
        expect(history.single.variantId, 'v1');
        expect(history.single.quantity, 4);
        expect(history.single.stockBefore, 5);
        expect(history.single.stockAfter, 9);
        expect(history.single.referenceType, 'PURCHASE');
        expect(history.single.referenceId, purchase.id);
      },
    );

    test('a mixed receive updates every stock entity exactly once', () async {
      await seedSupplier(id: 's1');
      await seedProduct(id: 'p1', name: 'Coffee', stock: 1);
      await seedVariant(id: 'v1', productId: 'p1', name: 'Small', stock: 5);
      await seedProduct(id: 'p2', name: 'Milk', stock: 4);

      await repository.receivePurchase(
        supplierId: 's1',
        lines: [
          line(productId: 'p1', quantity: 2, variantId: 'v1'),
          line(productId: 'p2', quantity: 3),
        ],
      );

      expect(await variantStock('v1'), 7);
      expect(await rawProductStock('p1'), 1);
      expect(await rawProductStock('p2'), 7);

      final variantHistory = await movements.movementsFor(
        'p1',
        variantId: 'v1',
      );
      expect(variantHistory.single.quantity, 2);
      final productHistory = await movements.movementsFor('p2');
      expect(productHistory.single.variantId, isNull);
      expect(productHistory.single.quantity, 3);
    });

    test('receiving does not mutate product or variant cost prices', () async {
      await seedSupplier(id: 's1');
      await seedProduct(id: 'p1', name: 'Coffee', stock: 1, costPaise: 9000);
      await seedVariant(id: 'v1', productId: 'p1', name: 'Small', stock: 5);

      await repository.receivePurchase(
        supplierId: 's1',
        lines: [
          line(productId: 'p1', quantity: 4, variantId: 'v1', costPaise: 5000),
        ],
      );

      // Cost price is a product-edit concern; receiving only moves stock.
      expect(await rawProductCost('p1'), 9000);
      expect(await rawVariantCost('v1'), isNull);
    });

    test('an inactive variant cannot receive and rolls back', () async {
      await seedSupplier(id: 's1');
      await seedProduct(id: 'p1', name: 'Coffee', stock: 1);
      await database
          .into(database.productVariants)
          .insert(
            ProductVariantsCompanion.insert(
              id: Value('v1'),
              productId: 'p1',
              name: 'Small',
              sellingPricePaise: 15000,
              stockQuantity: Value(5),
              isActive: Value(false),
            ),
          );

      await expectLater(
        repository.receivePurchase(
          supplierId: 's1',
          lines: [line(productId: 'p1', quantity: 4, variantId: 'v1')],
        ),
        throwsA(isA<InactiveProductFailure>()),
      );

      expect(await variantStock('v1'), 5);
      expect(await rawProductStock('p1'), 1);
      final history = await movements.movementsFor('p1', variantId: 'v1');
      expect(history, isEmpty);
    });
  });
}
