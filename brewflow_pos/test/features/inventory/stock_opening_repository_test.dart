import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Opening Repository (Step 5, real database)
///
/// Exercises [DriftStockMovementRepository.recordOpening] against a real
/// in-memory SQLite database so transaction behavior is exercised: the stock
/// update and the OPENING insert must succeed or fail together, and every
/// rejection path must leave stock and the audit trail untouched.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftStockMovementRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftStockMovementRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({required String id, int stock = 0}) async {
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
            name: 'Product $id',
            sellingPricePaise: 10000,
            stockQuantity: Value(stock),
          ),
        );
  }

  Future<int> productStock(String id) async {
    final product = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return product.stockQuantity;
  }

  group('recordOpening', () {
    test('records an OPENING movement and updates stock atomically', () async {
      await seedProduct(id: 'p1', stock: 0);

      final movement = await repository.recordOpening(
        productId: 'p1',
        quantity: 25,
        note: 'Initial stock',
      );

      expect(movement.movementType, StockMovementType.opening);
      expect(movement.quantity, 25);
      expect(movement.stockBefore, 0);
      expect(movement.stockAfter, 25);
      expect(movement.reason, isNull);
      expect(movement.note, 'Initial stock');
      expect(await productStock('p1'), 25);

      final stored = await repository.movementsFor('p1');
      expect(stored, hasLength(1));
      expect(stored.single.id, movement.id);
      expect(stored.single.movementType, StockMovementType.opening);
      expect(stored.single.stockAfter, 25);
    });

    test('a second opening is rejected and leaves stock and history '
        'untouched', () async {
      await seedProduct(id: 'p1', stock: 0);
      await repository.recordOpening(productId: 'p1', quantity: 25);

      await expectLater(
        repository.recordOpening(productId: 'p1', quantity: 5),
        throwsA(isA<DuplicateOpeningFailure>()),
      );

      expect(await productStock('p1'), 25);
      final stored = await repository.movementsFor('p1');
      expect(stored, hasLength(1));
      expect(stored.single.movementType, StockMovementType.opening);
    });

    test('a missing product is rejected without writing anything', () async {
      await expectLater(
        repository.recordOpening(productId: 'ghost', quantity: 25),
        throwsA(isA<ProductNotFoundFailure>()),
      );

      expect(await repository.movementsFor('ghost'), isEmpty);
    });

    test(
      'a zero quantity is rejected without touching stock or history',
      () async {
        await seedProduct(id: 'p1', stock: 0);

        await expectLater(
          repository.recordOpening(productId: 'p1', quantity: 0),
          throwsA(isA<InvalidOpeningQuantityFailure>()),
        );

        expect(await productStock('p1'), 0);
        expect(await repository.movementsFor('p1'), isEmpty);
      },
    );

    test(
      'a negative quantity is rejected without touching stock or history',
      () async {
        await seedProduct(id: 'p1', stock: 0);

        await expectLater(
          repository.recordOpening(productId: 'p1', quantity: -25),
          throwsA(isA<InvalidOpeningQuantityFailure>()),
        );

        expect(await productStock('p1'), 0);
        expect(await repository.movementsFor('p1'), isEmpty);
      },
    );

    test('opening on a product with existing stock is additive', () async {
      await seedProduct(id: 'p1', stock: 0);
      await repository.recordOpening(productId: 'p1', quantity: 25);
      await repository.adjustStock(
        productId: 'p1',
        delta: 10,
        reason: StockAdjustmentReason.purchase,
      );
      expect(await productStock('p1'), 35);

      final movements = await repository.movementsFor('p1');
      expect(movements, hasLength(2));
      expect(movements.map((m) => m.movementType), [
        StockMovementType.adjustmentIn,
        StockMovementType.opening,
      ]);
      final opening = movements.last;
      expect(opening.stockBefore, 0);
      expect(opening.stockAfter, 25);
    });

    test('a failed duplicate leaves no partial OPENING row behind', () async {
      await seedProduct(id: 'p1', stock: 0);
      await repository.recordOpening(productId: 'p1', quantity: 25);

      await expectLater(
        repository.recordOpening(productId: 'p1', quantity: 100),
        throwsA(isA<DuplicateOpeningFailure>()),
      );

      final rows = await (database.select(
        database.stockMovements,
      )..where((t) => t.productId.equals('p1'))).get();
      expect(rows, hasLength(1));
      expect(rows.single.movementType, 'OPENING');
      expect(rows.single.stockAfter, 25);
      expect(await productStock('p1'), 25);
    });
  });
}
