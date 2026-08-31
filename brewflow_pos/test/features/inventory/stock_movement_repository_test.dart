import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> seedProduct({
    required String id,
    int stock = 10,
    bool active = true,
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
            name: 'Product $id',
            sellingPricePaise: 10000,
            stockQuantity: Value(stock),
            isActive: Value(active),
          ),
        );
  }

  Future<int> productStock(String id) async {
    final product = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return product.stockQuantity;
  }

  StockMovementsCompanion movementRow({
    required String productId,
    required String movementType,
    required int quantity,
    required int stockBefore,
    required int stockAfter,
    required DateTime createdAt,
    String? reason,
    String? note,
  }) => StockMovementsCompanion.insert(
    productId: productId,
    movementType: movementType,
    quantity: quantity,
    stockBefore: stockBefore,
    stockAfter: stockAfter,
    reason: Value(reason),
    note: Value(note),
    createdAt: Value(createdAt),
    updatedAt: Value(createdAt),
  );

  group('adjustStock', () {
    test('adds stock for a positive delta', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.purchase,
      );

      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(movement.quantity, 5);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 15);
      expect(await productStock('p1'), 15);
    });

    test('removes stock for a negative delta', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: -3,
        reason: StockAdjustmentReason.damage,
      );

      expect(movement.movementType, StockMovementType.adjustmentOut);
      expect(movement.quantity, -3);
      expect(movement.stockBefore, 10);
      expect(movement.stockAfter, 7);
      expect(await productStock('p1'), 7);
    });

    test('allows an exact-zero result after a reduction', () async {
      await seedProduct(id: 'p1', stock: 4);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: -4,
        reason: StockAdjustmentReason.wastage,
      );

      expect(movement.stockAfter, 0);
      expect(await productStock('p1'), 0);
    });

    test('rejects a reduction that would make stock negative', () async {
      await seedProduct(id: 'p1', stock: 4);

      await expectLater(
        repository.adjustStock(
          productId: 'p1',
          delta: -5,
          reason: StockAdjustmentReason.damage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );
      expect(await productStock('p1'), 4);
    });

    test('rejects a missing product', () async {
      await expectLater(
        repository.adjustStock(
          productId: 'ghost',
          delta: 5,
          reason: StockAdjustmentReason.purchase,
        ),
        throwsA(isA<ProductNotFoundFailure>()),
      );
    });

    test('rejects a zero delta', () async {
      await seedProduct(id: 'p1', stock: 10);

      await expectLater(
        repository.adjustStock(
          productId: 'p1',
          delta: 0,
          reason: StockAdjustmentReason.correction,
        ),
        throwsA(isA<InvalidAdjustmentQuantityFailure>()),
      );
      expect(await productStock('p1'), 10);
    });

    test('allows an adjustment on an inactive product', () async {
      await seedProduct(id: 'p1', stock: 10, active: false);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 2,
        reason: StockAdjustmentReason.correction,
      );

      expect(movement.movementType, StockMovementType.adjustmentIn);
      expect(await productStock('p1'), 12);
    });

    test('persists the reason', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.purchase,
      );

      expect(movement.reason, StockAdjustmentReason.purchase);
    });

    test('persists a non-blank note', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.other,
        note: '   Supplier delivery   ',
      );

      expect(movement.note, 'Supplier delivery');
    });

    test('converts a blank note to null', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: 5,
        reason: StockAdjustmentReason.other,
        note: '   ',
      );

      expect(movement.note, isNull);
    });

    test('does not write a movement when the reduction is rejected', () async {
      await seedProduct(id: 'p1', stock: 4);

      await expectLater(
        repository.adjustStock(
          productId: 'p1',
          delta: -5,
          reason: StockAdjustmentReason.damage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );
      expect(await repository.movementsFor('p1'), isEmpty);
    });

    test('sequential competing reductions cannot overdraw stock', () async {
      await seedProduct(id: 'p1', stock: 10);

      await repository.adjustStock(
        productId: 'p1',
        delta: -7,
        reason: StockAdjustmentReason.damage,
      );
      await expectLater(
        repository.adjustStock(
          productId: 'p1',
          delta: -5,
          reason: StockAdjustmentReason.damage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );

      expect(await productStock('p1'), 3);
      expect(await repository.movementsFor('p1'), hasLength(1));
    });
  });

  group('movementsFor', () {
    test('returns newest first by createdAt', () async {
      await seedProduct(id: 'p1', stock: 10);
      final older = DateTime.utc(2025, 1, 1);
      final newer = DateTime.utc(2025, 2, 1);
      final newest = DateTime.utc(2025, 3, 1);
      await database.batch((batch) {
        batch.insertAll(database.stockMovements, [
          movementRow(
            productId: 'p1',
            movementType: 'ADJUSTMENT_IN',
            quantity: 5,
            stockBefore: 0,
            stockAfter: 5,
            createdAt: older,
          ),
          movementRow(
            productId: 'p1',
            movementType: 'ADJUSTMENT_OUT',
            quantity: -2,
            stockBefore: 5,
            stockAfter: 3,
            createdAt: newest,
          ),
          movementRow(
            productId: 'p1',
            movementType: 'ADJUSTMENT_IN',
            quantity: 3,
            stockBefore: 3,
            stockAfter: 6,
            createdAt: newer,
          ),
        ]);
      });

      final movements = await repository.movementsFor('p1');

      expect(movements.map((m) => m.createdAt), [newest, newer, older]);
      expect(movements.first.movementType, StockMovementType.adjustmentOut);
    });

    test('round-trips movement type and reason enum values', () async {
      await seedProduct(id: 'p1', stock: 10);

      final movement = await repository.adjustStock(
        productId: 'p1',
        delta: -4,
        reason: StockAdjustmentReason.missing,
      );
      final fetched = (await repository.movementsFor('p1')).first;

      expect(fetched.movementType, StockMovementType.adjustmentOut);
      expect(fetched.reason, StockAdjustmentReason.missing);
      expect(fetched.quantity, movement.quantity);
      expect(fetched.stockAfter, movement.stockAfter);
    });

    test('returns nothing for a product with no movements', () async {
      await seedProduct(id: 'p1', stock: 10);

      expect(await repository.movementsFor('p1'), isEmpty);
    });
  });
}
