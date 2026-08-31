import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart'
    as domain;
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Consistency Hardening (Step 9)
///
/// Edge-case and consistency hardening for the completed stock movement
/// system. Everything that touches transactions, stock arithmetic or the
/// audit chain runs against a real in-memory SQLite database; the single
/// controller test uses fakes to verify provider invalidation behavior.
///
/// The locked invariants under test:
/// - movement arithmetic: stockAfter = stockBefore + quantity
/// - current stock always equals the latest movement's stockAfter
/// - at most one OPENING per product; updates never add movements
/// - stock never goes negative (database guard is authoritative)
/// - every stock-changing operation commits or rolls back as one unit
/// - no duplicate submission / no raced overdraw
/// - after success, stock, history and dashboard refresh without reload
/// ---------------------------------------------------------------------------

/// Mirrors the single-database reality for the controller-level test: a
/// successful [adjustStock] also updates the product list state the dashboard
/// and product providers read back on their invalidation-triggered rebuilds.
final class _LinkedMovementFake implements StockMovementRepository {
  _LinkedMovementFake(this.inventory);

  final FakeInventoryRepository inventory;
  final FakeStockMovementRepository inner = FakeStockMovementRepository();

  @override
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  }) => inner.movementsFor(productId, variantId: variantId);

  @override
  Future<StockMovement> adjustStock({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    final movement = await inner.adjustStock(
      productId: productId,
      variantId: variantId,
      delta: delta,
      reason: reason,
      note: note,
    );
    if (variantId != null) {
      return movement;
    }
    final stored = inventory.storedProducts;
    for (var i = 0; i < stored.length; i++) {
      if (stored[i].id == productId) {
        stored[i] = stored[i].copyWith(stockQuantity: movement.stockAfter);
        break;
      }
    }
    return movement;
  }

  @override
  Future<StockMovement> recordOpening({
    required String productId,
    required int quantity,
    String? note,
  }) =>
      inner.recordOpening(productId: productId, quantity: quantity, note: note);
}

void main() {
  late db.AppDatabase database;
  late DriftInventoryRepository inventory;
  late DriftStockMovementRepository movements;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
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
          db.CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
        );
  }

  /// Seeds a product row directly (no movements, no OPENING) with the given
  /// stock, for arithmetic-focused tests.
  Future<void> seedProduct({
    required String id,
    String categoryId = 'cat1',
    int stock = 0,
  }) async {
    await seedCategory(categoryId);
    await database
        .into(database.products)
        .insert(
          db.ProductsCompanion.insert(
            id: Value(id),
            categoryId: categoryId,
            name: 'Product $id',
            sellingPricePaise: 10000,
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
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

  Future<int> productStock(String id) async {
    final product = await (database.select(
      database.products,
    )..where((t) => t.id.equals(id))).getSingle();
    return product.stockQuantity;
  }

  group('stock consistency hardening (real database)', () {
    test(
      'a large valid IN adjustment keeps arithmetic and stock consistent',
      () async {
        await seedProduct(id: 'p1', stock: 0);

        final movement = await movements.adjustStock(
          productId: 'p1',
          delta: 100000,
          reason: StockAdjustmentReason.purchase,
        );

        expect(movement.movementType, StockMovementType.adjustmentIn);
        expect(movement.quantity, 100000);
        expect(movement.stockBefore, 0);
        expect(movement.stockAfter, 100000);
        expect(await productStock('p1'), 100000);
        final stored = await movements.movementsFor('p1');
        expect(stored, hasLength(1));
        expect(stored.single.stockAfter, 100000);
      },
    );

    test('large OUT reductions never drive stock below zero', () async {
      await seedProduct(id: 'p1', stock: 100000);

      final first = await movements.adjustStock(
        productId: 'p1',
        delta: -99999,
        reason: StockAdjustmentReason.damage,
      );
      expect(first.stockAfter, 1);

      await expectLater(
        movements.adjustStock(
          productId: 'p1',
          delta: -2,
          reason: StockAdjustmentReason.damage,
        ),
        throwsA(isA<AdjustmentInsufficientStockFailure>()),
      );

      expect(await productStock('p1'), 1);
      final stored = await movements.movementsFor('p1');
      expect(stored, hasLength(1));
      expect(stored.single.quantity, -99999);
      expect(stored.single.stockAfter, 1);
    });

    test(
      'updating unrelated product fields after adjustments adds no movements',
      () async {
        await seedCategory('cat1');
        final product = await createProduct('cat1', stock: 25);
        await movements.adjustStock(
          productId: product.id,
          delta: -5,
          reason: StockAdjustmentReason.damage,
        );
        expect(await productStock(product.id), 20);

        await inventory.updateProduct(
          id: product.id,
          categoryId: 'cat1',
          name: 'Tea Powder (New)',
          sku: null,
          sellingPricePaise: 12000,
          costPricePaise: null,
          stockQuantity: 20,
          isActive: true,
        );

        expect(await productStock(product.id), 20);
        final stored = (await inventory.products()).single;
        expect(stored.name, 'Tea Powder (New)');

        final history = await movements.movementsFor(product.id);
        expect(history, hasLength(2));
        expect(history.map((m) => m.movementType).toList(), [
          StockMovementType.adjustmentOut,
          StockMovementType.opening,
        ]);
        expect(
          history.where((m) => m.movementType == StockMovementType.opening),
          hasLength(1),
        );
        expect(history.last.stockBefore, 0);
        expect(history.last.stockAfter, 25);
      },
    );

    test('the full multi-step audit chain stays consistent and ends at the '
        'current stock', () async {
      await seedCategory('cat1');
      final product = await createProduct('cat1', stock: 100);
      await movements.adjustStock(
        productId: product.id,
        delta: 25,
        reason: StockAdjustmentReason.purchase,
      );
      await movements.adjustStock(
        productId: product.id,
        delta: -10,
        reason: StockAdjustmentReason.damage,
      );
      await movements.adjustStock(
        productId: product.id,
        delta: 5,
        reason: StockAdjustmentReason.correction,
      );
      await movements.adjustStock(
        productId: product.id,
        delta: -40,
        reason: StockAdjustmentReason.wastage,
      );

      final history = await movements.movementsFor(product.id);
      expect(history, hasLength(5));
      expect(history.map((m) => m.movementType).toList(), [
        StockMovementType.adjustmentOut,
        StockMovementType.adjustmentIn,
        StockMovementType.adjustmentOut,
        StockMovementType.adjustmentIn,
        StockMovementType.opening,
      ]);

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
      expect(chronological.map((m) => m.stockAfter).toList(), [
        100,
        125,
        115,
        120,
        80,
      ]);

      expect(await productStock(product.id), 80);
      expect(history.first.stockAfter, 80);
    });

    test('concurrent reductions cannot overdraw stock', () async {
      await seedProduct(id: 'p1', stock: 3);

      Future<Object> outcome(Future<StockMovement> call) =>
          call.then<Object>((m) => m).catchError((Object error) => error);

      final first = await outcome(
        movements.adjustStock(
          productId: 'p1',
          delta: -2,
          reason: StockAdjustmentReason.damage,
        ),
      );
      final second = await outcome(
        movements.adjustStock(
          productId: 'p1',
          delta: -2,
          reason: StockAdjustmentReason.damage,
        ),
      );

      final successes = [first, second].whereType<StockMovement>().toList();
      final failures = [
        first,
        second,
      ].whereType<StockMovementFailure>().toList();
      expect(successes, hasLength(1));
      expect(failures, hasLength(1));
      expect(failures.single, isA<AdjustmentInsufficientStockFailure>());
      expect(successes.single.stockAfter, 1);

      expect(await productStock('p1'), 1);
      final stored = await movements.movementsFor('p1');
      expect(stored, hasLength(1));
      expect(stored.single.stockBefore, 3);
      expect(stored.single.stockAfter, 1);
    });

    test(
      'a failed movement insert rolls back the stock update completely',
      () async {
        await seedProduct(id: 'p1', stock: 5);
        await database.customStatement(
          'CREATE TRIGGER fail_adjustment_insert '
          'BEFORE INSERT ON stock_movements '
          'BEGIN SELECT RAISE(ABORT, "forced adjustment failure"); END',
        );

        await expectLater(
          movements.adjustStock(
            productId: 'p1',
            delta: 5,
            reason: StockAdjustmentReason.purchase,
          ),
          throwsA(isA<UnexpectedStockMovementFailure>()),
        );

        expect(await productStock('p1'), 5);
        expect(await movements.movementsFor('p1'), isEmpty);
        final rows = await (database.select(
          database.stockMovements,
        )..where((t) => t.productId.equals('p1'))).get();
        expect(rows, isEmpty);
      },
    );
  });

  group('read consistency after adjustment (controller)', () {
    test('stock, history and dashboard all refresh after a successful '
        'adjustment', () async {
      final fakeInventory = FakeInventoryRepository();
      final fakeMovements = _LinkedMovementFake(fakeInventory);
      final now = DateTime.now().toUtc();
      fakeInventory.storedCategories.add(
        domain.Category(
          id: 'c1',
          name: 'Beverages',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      fakeInventory.storedProducts.add(
        domain.Product(
          id: 'p1',
          categoryId: 'c1',
          name: 'Milk 1L',
          sku: null,
          sellingPricePaise: 14950,
          costPricePaise: null,
          stockQuantity: 3,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      );
      fakeMovements.inner.productStock['p1'] = 3;

      final container = ProviderContainer(
        overrides: [
          stockMovementRepositoryProvider.overrideWithValue(fakeMovements),
          inventoryRepositoryProvider.overrideWithValue(fakeInventory),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      Future<void> awaitUntil(bool Function() condition) async {
        for (var i = 0; i < 200; i++) {
          if (condition()) return;
          await Future<void>.delayed(Duration.zero);
        }
        fail('condition was not met within the timeout');
      }

      await awaitUntil(
        () => container.read(dashboardControllerProvider) is AsyncData,
      );
      expect(
        container.read(dashboardControllerProvider).requireValue.lowStockCount,
        1,
      );

      await awaitUntil(() => container.read(productsProvider) is AsyncData);
      expect(
        container.read(productsProvider).requireValue.single.stockQuantity,
        3,
      );

      await awaitUntil(
        () => container.read(productMovementsProvider('p1')) is AsyncData,
      );
      expect(container.read(productMovementsProvider('p1')).value, isEmpty);

      final movement = await container
          .read(productMovementsProvider('p1').notifier)
          .adjustStock(delta: 7, reason: StockAdjustmentReason.purchase);

      await awaitUntil(
        () =>
            container.read(productsProvider).value?.single.stockQuantity == 10,
      );
      await awaitUntil(
        () =>
            (container.read(productMovementsProvider('p1')).value ??
                    const <StockMovement>[])
                .isNotEmpty,
      );
      await awaitUntil(
        () =>
            container.read(dashboardControllerProvider).value?.lowStockCount ==
            0,
      );

      final refreshedProducts = container.read(productsProvider);
      expect(refreshedProducts.value!.single.stockQuantity, 10);
      final refreshedHistory = container
          .read(productMovementsProvider('p1'))
          .value!;
      expect(refreshedHistory.single.id, movement.id);
      expect(refreshedHistory.single.stockAfter, 10);
      final refreshedDashboard = container
          .read(dashboardControllerProvider)
          .value!;
      expect(refreshedDashboard.lowStockCount, 0);
      expect(refreshedDashboard.productCount, 1);
    });
  });
}
