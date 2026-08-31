import 'package:brewflow_pos/core/database/app_database.dart' show AppDatabase;
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Variant-layer repository tests against a real in-memory Drift database.
///
/// These lock the variant stock contract end to end: variants own the stock,
/// every variant stock change is an audited movement on the exact variant,
/// edits never touch stock, and the product's domain stock is always the sum
/// of its variant stock.
void main() {
  late AppDatabase database;
  late DriftInventoryRepository repository;
  late DriftStockMovementRepository movements;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInventoryRepository(database);
    movements = DriftStockMovementRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Category> createCategory(String name) =>
      repository.createCategory(name);

  ProductVariantInput variant({
    String? id,
    required String name,
    String? sku,
    int pricePaise = 15000,
    int? costPaise,
    int stock = 0,
    bool membershipEnabled = false,
    int? memberPricePaise,
    bool isActive = true,
  }) => ProductVariantInput(
    id: id,
    name: name,
    sku: sku,
    sellingPricePaise: pricePaise,
    costPricePaise: costPaise,
    stockQuantity: stock,
    membershipEnabled: membershipEnabled,
    memberPricePaise: memberPricePaise,
    isActive: isActive,
  );

  Future<Product> createVariantProduct({
    required Category category,
    List<ProductVariantInput> variants = const [],
    int stockQuantity = 0,
    String name = 'Coffee',
  }) => repository.createProduct(
    categoryId: category.id,
    name: name,
    sellingPricePaise: 20000,
    stockQuantity: stockQuantity,
    isActive: true,
    variants: variants,
  );

  Future<int> variantStock(String variantId) async {
    final row = await (database.select(
      database.productVariants,
    )..where((t) => t.id.equals(variantId))).getSingle();
    return row.stockQuantity;
  }

  Future<Product> productById(String id) async {
    final all = await repository.products();
    return all.singleWhere((p) => p.id == id);
  }

  group('variant creation', () {
    test(
      'each variant opening stock becomes its own OPENING movement',
      () async {
        final category = await createCategory('Beverages');
        final product = await createVariantProduct(
          category: category,
          variants: [
            variant(name: 'Small', stock: 5),
            variant(name: 'Large', stock: 3),
          ],
        );

        expect(product.stockQuantity, 8);
        expect(product.variants, hasLength(2));
        expect(product.variants[0].stockQuantity, 5);
        expect(product.variants[1].stockQuantity, 3);

        final small = product.variants[0];
        final smallMovements = await movements.movementsFor(
          product.id,
          variantId: small.id,
        );
        expect(smallMovements, hasLength(1));
        expect(smallMovements.single.movementType, StockMovementType.opening);
        expect(smallMovements.single.variantId, small.id);
        expect(smallMovements.single.quantity, 5);
        expect(smallMovements.single.stockBefore, 0);
        expect(smallMovements.single.stockAfter, 5);
      },
    );

    test('zero-stock variants write no movement', () async {
      final category = await createCategory('Beverages');
      final product = await createVariantProduct(
        category: category,
        variants: [variant(name: 'Small', stock: 0)],
      );

      final movementsList = await movements.movementsFor(
        product.id,
        variantId: product.variants.single.id,
      );
      expect(movementsList, isEmpty);
      expect((await productById(product.id)).stockQuantity, 0);
    });

    test('a product-level opening alongside variants is rejected', () async {
      final category = await createCategory('Beverages');

      await expectLater(
        createVariantProduct(
          category: category,
          stockQuantity: 4,
          variants: [variant(name: 'Small', stock: 5)],
        ),
        throwsA(isA<UnexpectedInventoryFailure>()),
      );
      expect(await repository.products(), isEmpty);
    });
  });

  group('variant stock adjustments', () {
    late Product product;
    late ProductVariant small;
    late ProductVariant large;

    setUp(() async {
      final category = await createCategory('Beverages');
      product = await createVariantProduct(
        category: category,
        variants: [
          variant(name: 'Small', stock: 5),
          variant(name: 'Large', stock: 3),
        ],
      );
      small = product.variants[0];
      large = product.variants[1];
    });

    test(
      'an adjustment writes the movement on the exact variant only',
      () async {
        final movement = await movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: 5,
          reason: StockAdjustmentReason.purchase,
        );

        expect(movement.variantId, small.id);
        expect(movement.movementType, StockMovementType.adjustmentIn);
        expect(movement.quantity, 5);
        expect(movement.stockBefore, 5);
        expect(movement.stockAfter, 10);
        expect(movement.reason, StockAdjustmentReason.purchase);

        expect(await variantStock(small.id), 10);
        expect(await variantStock(large.id), 3);
      },
    );

    test('a reduction never takes the variant below zero', () async {
      final movement = await movements.adjustStock(
        productId: product.id,
        variantId: small.id,
        delta: -5,
        reason: StockAdjustmentReason.wastage,
      );

      expect(movement.stockAfter, 0);
      expect(await variantStock(small.id), 0);

      await expectLater(
        movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: -1,
          reason: StockAdjustmentReason.wastage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );
      expect(await variantStock(small.id), 0);
    });

    test('an insufficient reduction leaves no movement behind', () async {
      await expectLater(
        movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: -99,
          reason: StockAdjustmentReason.damage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );

      expect(await variantStock(small.id), 5);
      expect(await variantStock(large.id), 3);
      final history = await movements.movementsFor(
        product.id,
        variantId: small.id,
      );
      expect(history, hasLength(1));
      expect(history.single.movementType, StockMovementType.opening);
    });

    test('the product domain stock is the sum of variant stock', () async {
      await movements.adjustStock(
        productId: product.id,
        variantId: small.id,
        delta: 5,
        reason: StockAdjustmentReason.purchase,
      );

      final refreshed = await productById(product.id);
      expect(refreshed.stockQuantity, 13);
      expect(refreshed.variants.fold(0, (sum, v) => sum + v.stockQuantity), 13);
    });

    test(
      'product-level and variant movements are isolated by filter',
      () async {
        await movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: 2,
          reason: StockAdjustmentReason.purchase,
        );
        await movements.adjustStock(
          productId: product.id,
          delta: 9,
          reason: StockAdjustmentReason.damage,
        );

        final productLevel = await movements.movementsFor(product.id);
        expect(productLevel, hasLength(1));
        expect(productLevel.single.variantId, isNull);

        final smallHistory = await movements.movementsFor(
          product.id,
          variantId: small.id,
        );
        expect(smallHistory, hasLength(2));
        expect(smallHistory.first.variantId, small.id);
        expect(smallHistory.first.movementType, StockMovementType.adjustmentIn);
        expect(smallHistory.last.movementType, StockMovementType.opening);
      },
    );

    test(
      'the movement chain stays consistent with the variant stock',
      () async {
        await movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: 4,
          reason: StockAdjustmentReason.purchase,
        );
        await movements.adjustStock(
          productId: product.id,
          variantId: small.id,
          delta: -2,
          reason: StockAdjustmentReason.damage,
        );

        final history = await movements.movementsFor(
          product.id,
          variantId: small.id,
        );
        expect(history.first.stockAfter, 7);
        expect(await variantStock(small.id), 7);
      },
    );
  });

  group('variant editing', () {
    test('editing a variant never changes stock or writes movements', () async {
      final category = await createCategory('Beverages');
      final product = await createVariantProduct(
        category: category,
        variants: [variant(name: 'Small', stock: 5)],
      );
      final small = product.variants.single;

      await repository.updateProduct(
        id: product.id,
        categoryId: category.id,
        name: 'Coffee',
        sellingPricePaise: 25000,
        stockQuantity: 0,
        isActive: true,
        variants: [
          variant(
            id: small.id,
            name: 'Small 250ml',
            pricePaise: 18000,
            stock: 999,
          ),
        ],
      );

      final refreshed = await productById(product.id);
      expect(refreshed.variants.single.name, 'Small 250ml');
      expect(refreshed.variants.single.sellingPricePaise, 18000);
      expect(refreshed.variants.single.stockQuantity, 5);

      final history = await movements.movementsFor(
        product.id,
        variantId: small.id,
      );
      expect(history, hasLength(1));
      expect(history.single.movementType, StockMovementType.opening);
    });

    test('adding a variant on edit writes only its opening movement', () async {
      final category = await createCategory('Beverages');
      final product = await createVariantProduct(
        category: category,
        variants: [variant(name: 'Small', stock: 5)],
      );
      final small = product.variants.single;

      await repository.updateProduct(
        id: product.id,
        categoryId: category.id,
        name: 'Coffee',
        sellingPricePaise: 20000,
        stockQuantity: 0,
        isActive: true,
        variants: [
          variant(id: small.id, name: 'Small', stock: 999),
          variant(name: 'Large', stock: 7),
        ],
      );

      final refreshed = await productById(product.id);
      expect(refreshed.variants, hasLength(2));
      expect(refreshed.stockQuantity, 12);
      final large = refreshed.variants.firstWhere((v) => v.name == 'Large');
      expect(large.stockQuantity, 7);

      final largeHistory = await movements.movementsFor(
        product.id,
        variantId: large.id,
      );
      expect(largeHistory, hasLength(1));
      expect(largeHistory.single.movementType, StockMovementType.opening);
      expect(largeHistory.single.stockAfter, 7);
    });

    test('a removed variant is soft-deactivated with history intact', () async {
      final category = await createCategory('Beverages');
      final product = await createVariantProduct(
        category: category,
        variants: [
          variant(name: 'Small', stock: 5),
          variant(name: 'Large', stock: 3),
        ],
      );
      final small = product.variants[0];

      await repository.updateProduct(
        id: product.id,
        categoryId: category.id,
        name: 'Coffee',
        sellingPricePaise: 20000,
        stockQuantity: 0,
        isActive: true,
        variants: [variant(id: small.id, name: 'Small', stock: 999)],
      );

      final refreshed = await productById(product.id);
      expect(refreshed.variants, hasLength(2));
      expect(
        refreshed.variants.firstWhere((v) => v.name == 'Large').isActive,
        isFalse,
      );
      expect(
        refreshed.variants.firstWhere((v) => v.name == 'Large').stockQuantity,
        3,
      );
      expect(refreshed.stockQuantity, 8);

      final large = refreshed.variants.firstWhere((v) => v.name == 'Large');
      final history = await movements.movementsFor(
        product.id,
        variantId: large.id,
      );
      expect(history, hasLength(1));
      expect(history.single.movementType, StockMovementType.opening);
    });

    test('a stale variant id from another product is rejected', () async {
      final category = await createCategory('Beverages');
      final first = await createVariantProduct(
        category: category,
        name: 'First',
        variants: [variant(name: 'Small', stock: 5)],
      );
      final second = await createVariantProduct(
        category: category,
        name: 'Second',
        variants: [variant(name: 'Small', stock: 2)],
      );

      await expectLater(
        repository.updateProduct(
          id: second.id,
          categoryId: category.id,
          name: 'Second',
          sellingPricePaise: 20000,
          stockQuantity: 0,
          isActive: true,
          variants: [
            variant(id: first.variants.single.id, name: 'Small', stock: 999),
          ],
        ),
        throwsA(isA<UnexpectedInventoryFailure>()),
      );

      expect(await variantStock(first.variants.single.id), 5);
      expect(await variantStock(second.variants.single.id), 2);
    });
  });

  group('variant validation', () {
    late Category category;

    setUp(() async {
      category = await createCategory('Beverages');
    });

    test('a variant without a name is rejected', () async {
      await expectLater(
        createVariantProduct(
          category: category,
          variants: [variant(name: '  ')],
        ),
        throwsA(isA<VariantNameRequiredFailure>()),
      );
      expect(await repository.products(), isEmpty);
    });

    test(
      'a variant with membership pricing but no member price is rejected',
      () async {
        await expectLater(
          createVariantProduct(
            category: category,
            variants: [variant(name: 'Small', membershipEnabled: true)],
          ),
          throwsA(isA<MissingMemberPriceFailure>()),
        );
        expect(await repository.products(), isEmpty);
      },
    );

    test('negative variant stock is rejected', () async {
      await expectLater(
        createVariantProduct(
          category: category,
          variants: [variant(name: 'Small', stock: -1)],
        ),
        throwsA(isA<NegativeStockFailure>()),
      );
    });

    test('variant SKUs share the catalog namespace', () async {
      await createVariantProduct(
        category: category,
        variants: [variant(name: 'Small', sku: 'CB-S')],
      );

      await expectLater(
        createVariantProduct(
          category: category,
          name: 'Other',
          variants: [variant(name: 'Large', sku: 'cb-s')],
        ),
        throwsA(isA<DuplicateVariantSkuFailure>()),
      );

      await expectLater(
        repository.createProduct(
          categoryId: category.id,
          name: 'Plain',
          sku: 'CB-S',
          sellingPricePaise: 10000,
          stockQuantity: 1,
          isActive: true,
        ),
        throwsA(isA<DuplicateSkuFailure>()),
      );
    });
  });
}
