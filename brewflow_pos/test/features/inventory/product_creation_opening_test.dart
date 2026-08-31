import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart'
    as domain;
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Creation + OPENING Integration (Step 6)
///
/// Exercises [DriftInventoryRepository.createProduct] against a real
/// in-memory SQLite database so transaction behavior is real: a product with
/// opening stock must be created together with exactly one OPENING movement
/// (or not at all), and any failure inside the transaction must roll back
/// both the product and the movement. Failures are forced with database
/// triggers so a partial product can never survive unnoticed.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftInventoryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInventoryRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCategory(String id) async {
    await database
        .into(database.categories)
        .insert(
          CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
  }

  Future<domain.Product> createProduct(
    String categoryId, {
    int stock = 0,
    String name = 'Tea Powder',
    String? sku,
    bool isActive = true,
  }) => repository.createProduct(
    categoryId: categoryId,
    name: name,
    sku: sku,
    sellingPricePaise: 10000,
    costPricePaise: null,
    stockQuantity: stock,
    isActive: isActive,
  );

  Future<List<StockMovement>> openingRows(String productId) async {
    return (database.select(
      database.stockMovements,
    )..where((t) => t.productId.equals(productId))).get();
  }

  Future<int> productCount() async {
    return (await database.select(database.products).get()).length;
  }

  Future<int> movementCount() async {
    return (await database.select(database.stockMovements).get()).length;
  }

  group('product creation with opening stock', () {
    test(
      'creates the product and exactly one OPENING movement for stock 25',
      () async {
        await seedCategory('cat1');

        final product = await createProduct(
          'cat1',
          stock: 25,
          name: 'Tea Powder',
        );

        expect(product.stockQuantity, 25);
        final movements = await openingRows(product.id);
        expect(movements, hasLength(1));
        final opening = movements.single;
        expect(opening.movementType, 'OPENING');
        expect(opening.quantity, 25);
        expect(opening.stockBefore, 0);
        expect(opening.stockAfter, 25);
        expect(opening.reason, isNull);
      },
    );

    test(
      'zero opening stock creates the product without any movement',
      () async {
        await seedCategory('cat1');

        final product = await createProduct('cat1', stock: 0);

        expect(product.stockQuantity, 0);
        expect(await openingRows(product.id), isEmpty);
        expect(await movementCount(), 0);
      },
    );

    test(
      'negative opening stock is rejected without creating anything',
      () async {
        await seedCategory('cat1');

        await expectLater(
          createProduct('cat1', stock: -1),
          throwsA(isA<NegativeStockFailure>()),
        );

        expect(await productCount(), 0);
        expect(await movementCount(), 0);
      },
    );

    test(
      'a failed OPENING insert rolls back the product and the movement',
      () async {
        await seedCategory('cat1');
        await database.customStatement(
          'CREATE TRIGGER fail_opening_insert '
          'BEFORE INSERT ON stock_movements '
          'BEGIN SELECT RAISE(ABORT, "forced opening failure"); END',
        );

        await expectLater(
          createProduct('cat1', stock: 25),
          throwsA(isA<UnexpectedInventoryFailure>()),
        );

        expect(await productCount(), 0);
        expect(await movementCount(), 0);
      },
    );

    test('a failed product insert rolls back everything', () async {
      await seedCategory('cat1');
      await database.customStatement(
        'CREATE TRIGGER fail_product_insert '
        'AFTER INSERT ON products '
        'BEGIN SELECT RAISE(ABORT, "forced product failure"); END',
      );

      await expectLater(
        createProduct('cat1', stock: 25),
        throwsA(isA<UnexpectedInventoryFailure>()),
      );

      expect(await productCount(), 0);
      expect(await movementCount(), 0);
    });

    test('each created product gets exactly one OPENING movement', () async {
      await seedCategory('cat1');

      final first = await createProduct('cat1', stock: 10, name: 'Milk');
      final second = await createProduct('cat1', stock: 20, name: 'Coffee');

      expect(await productCount(), 2);
      expect(await movementCount(), 2);
      final firstOpening = (await openingRows(first.id)).single;
      final secondOpening = (await openingRows(second.id)).single;
      expect(firstOpening.movementType, 'OPENING');
      expect(firstOpening.stockAfter, 10);
      expect(secondOpening.movementType, 'OPENING');
      expect(secondOpening.stockAfter, 20);
    });

    test(
      'updating a product does not create another OPENING movement',
      () async {
        await seedCategory('cat1');
        final product = await createProduct(
          'cat1',
          stock: 25,
          name: 'Tea Powder',
        );

        await repository.updateProduct(
          id: product.id,
          categoryId: 'cat1',
          name: 'Tea Powder (New)',
          sku: product.sku,
          sellingPricePaise: 12000,
          costPricePaise: null,
          stockQuantity: 25,
          isActive: true,
        );

        final stored = (await repository.products()).single;
        expect(stored.name, 'Tea Powder (New)');
        expect(stored.stockQuantity, 25);
        final movements = await openingRows(product.id);
        expect(movements, hasLength(1));
        expect(movements.single.movementType, 'OPENING');
        expect(movements.single.stockAfter, 25);
      },
    );
  });
}
