import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart'
    as domain;
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart'
    as domain;
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movement History Read-Side (Step 7)
///
/// Verifies the audit trail produced by the real operations (Step 6 product
/// creation with OPENING, Step 4 adjustments) is read back correctly through
/// the existing [DriftStockMovementRepository.movementsFor] boundary: full
/// trail content, newest-first ordering, empty history and per-product
/// isolation. The controller path (provider, ordering, typed failures,
/// unexpected-error mapping) is already covered by the Step 3 tests.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    inventory = DriftInventoryRepository(database);
    movements = DriftStockMovementRepository(database);
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
  }) => inventory.createProduct(
    categoryId: categoryId,
    name: name,
    sku: null,
    sellingPricePaise: 10000,
    costPricePaise: null,
    stockQuantity: stock,
    isActive: true,
  );

  Future<List<domain.StockMovement>> history(String productId) =>
      movements.movementsFor(productId);

  group('movement history read-side', () {
    test('a product with no movements has empty history', () async {
      await seedCategory('cat1');
      final product = await createProduct('cat1', stock: 0);

      expect(await history(product.id), isEmpty);
    });

    test(
      'the OPENING movement from product creation appears in history',
      () async {
        await seedCategory('cat1');
        final product = await createProduct('cat1', stock: 25);

        final rows = await history(product.id);
        expect(rows, hasLength(1));
        final opening = rows.single;
        expect(opening.movementType, domain.StockMovementType.opening);
        expect(opening.quantity, 25);
        expect(opening.stockBefore, 0);
        expect(opening.stockAfter, 25);
        expect(opening.reason, isNull);
      },
    );

    test('the full OPENING + ADJUSTMENT_IN + ADJUSTMENT_OUT trail is '
        'returned newest first', () async {
      await seedCategory('cat1');
      final product = await createProduct('cat1', stock: 25);
      await movements.adjustStock(
        productId: product.id,
        delta: 10,
        reason: domain.StockAdjustmentReason.purchase,
      );
      await movements.adjustStock(
        productId: product.id,
        delta: -5,
        reason: domain.StockAdjustmentReason.damage,
      );

      final rows = await history(product.id);
      expect(rows, hasLength(3));
      expect(rows.map((m) => m.movementType), [
        domain.StockMovementType.adjustmentOut,
        domain.StockMovementType.adjustmentIn,
        domain.StockMovementType.opening,
      ]);
      expect(rows.map((m) => m.quantity), [-5, 10, 25]);
      expect(rows.map((m) => m.stockBefore), [35, 25, 0]);
      expect(rows.map((m) => m.stockAfter), [30, 35, 25]);
    });

    test('history is isolated per product', () async {
      await seedCategory('cat1');
      final first = await createProduct('cat1', stock: 10, name: 'Milk');
      final second = await createProduct('cat1', stock: 5, name: 'Coffee');
      await movements.adjustStock(
        productId: first.id,
        delta: 5,
        reason: domain.StockAdjustmentReason.purchase,
      );
      await movements.adjustStock(
        productId: second.id,
        delta: -2,
        reason: domain.StockAdjustmentReason.wastage,
      );
      await movements.adjustStock(
        productId: first.id,
        delta: -3,
        reason: domain.StockAdjustmentReason.damage,
      );

      final firstRows = await history(first.id);
      expect(firstRows, hasLength(3));
      expect(firstRows.map((m) => m.productId), everyElement(first.id));
      expect(firstRows.map((m) => m.movementType), [
        domain.StockMovementType.adjustmentOut,
        domain.StockMovementType.adjustmentIn,
        domain.StockMovementType.opening,
      ]);
      expect(firstRows.map((m) => m.stockAfter), [12, 15, 10]);

      final secondRows = await history(second.id);
      expect(secondRows, hasLength(2));
      expect(secondRows.map((m) => m.productId), everyElement(second.id));
      expect(secondRows.map((m) => m.movementType), [
        domain.StockMovementType.adjustmentOut,
        domain.StockMovementType.opening,
      ]);
      expect(secondRows.map((m) => m.stockAfter), [3, 5]);
    });
  });
}
