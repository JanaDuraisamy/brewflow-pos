import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_settings_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Cross-Module Provider/UI Refresh (Phase 10 Step 8)
///
/// All real repositories (inventory, purchases, billing, suppliers, orders,
/// ledger, stock movements) derive from [appDatabaseProvider]; overriding it
/// with an in-memory SQLite database wires the entire real stack behind the
/// Riverpod controllers. These tests drive stock changes through the actual
/// controllers and verify that every visible surface refreshes without a
/// restart:
/// - purchase: product list, purchase history, movement history, dashboard
/// - sale: POS shelf, movement history, dashboard AND the product list (the
///   inventory page must not show stale stock after a POS sale)
/// - adjustment/opening refresh is locked by Step 9's controller test.
/// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct(String id, int stock) async {
    await database
        .into(database.categories)
        .insert(db.CategoriesCompanion.insert(id: Value('c1'), name: 'Coffee'));
    await database
        .into(database.products)
        .insert(
          db.ProductsCompanion.insert(
            id: Value(id),
            categoryId: 'c1',
            name: 'Product $id',
            sellingPricePaise: 15000,
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
  }

  Future<void> awaitUntil(
    ProviderContainer container,
    bool Function() condition, {
    String reason = 'condition was not met within the timeout',
  }) async {
    for (var i = 0; i < 300; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail(reason);
  }

  test('a purchase through the controllers refreshes products, movements, '
      'purchases and the dashboard', () async {
    await seedProduct('p1', 4);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ],
    );
    addTearDown(container.dispose);

    await awaitUntil(
      container,
      () => container.read(productsProvider) is AsyncData,
    );
    expect(
      container.read(productsProvider).requireValue.single.stockQuantity,
      4,
    );
    await awaitUntil(
      container,
      () => container.read(dashboardControllerProvider) is AsyncData,
    );
    expect(
      container.read(dashboardControllerProvider).requireValue.lowStockCount,
      1,
    );
    await awaitUntil(
      container,
      () => container.read(purchasesProvider) is AsyncData,
    );
    expect(container.read(purchasesProvider).requireValue, isEmpty);
    await awaitUntil(
      container,
      () => container.read(productMovementsProvider('p1')) is AsyncData,
    );
    expect(
      container.read(productMovementsProvider('p1')).requireValue,
      isEmpty,
    );

    final product = container.read(productsProvider).requireValue.single;
    final form = container.read(purchaseFormProvider.notifier);
    expect(
      form.addLine(product: product, quantity: 3, unitCostPaise: 8000),
      isTrue,
    );
    final purchase = await form.submit();
    expect(purchase!.purchaseNumber, 'PUR-000001');

    await awaitUntil(
      container,
      () => container.read(productsProvider).value?.single.stockQuantity == 7,
    );
    await awaitUntil(
      container,
      () =>
          (container.read(productMovementsProvider('p1')).value ??
                  const <StockMovement>[])
              .isNotEmpty,
    );
    await awaitUntil(
      container,
      () => container.read(purchasesProvider).value?.length == 1,
    );
    await awaitUntil(
      container,
      () =>
          container.read(dashboardControllerProvider).value?.lowStockCount == 0,
    );

    expect(container.read(productsProvider).value!.single.stockQuantity, 7);
    final history = container.read(productMovementsProvider('p1')).value!;
    expect(history.single.movementType, StockMovementType.purchase);
    expect(history.single.stockBefore, 4);
    expect(history.single.stockAfter, 7);
    expect(
      container.read(purchasesProvider).value!.single.purchase.purchaseNumber,
      'PUR-000001',
    );
    expect(container.read(dashboardControllerProvider).value!.lowStockCount, 0);
    expect(container.read(dashboardControllerProvider).value!.productCount, 1);
  });

  test(
    'a sale through the controllers refreshes the POS shelf, movements and '
    'dashboard, and the inventory product list shows the new stock',
    () async {
      await seedProduct('p1', 3);
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Prime the surfaces, then receive stock through the purchase flow.
      await awaitUntil(
        container,
        () => container.read(productsProvider) is AsyncData,
      );
      expect(
        container.read(productsProvider).requireValue.single.stockQuantity,
        3,
      );
      await awaitUntil(
        container,
        () => container.read(dashboardControllerProvider) is AsyncData,
      );
      expect(
        container.read(dashboardControllerProvider).requireValue.lowStockCount,
        1,
      );

      final product = container.read(productsProvider).requireValue.single;
      final form = container.read(purchaseFormProvider.notifier);
      form.addLine(product: product, quantity: 4, unitCostPaise: 8000);
      await form.submit();
      await awaitUntil(
        container,
        () => container.read(productsProvider).value?.single.stockQuantity == 7,
      );
      await awaitUntil(
        container,
        () =>
            container.read(dashboardControllerProvider).value?.lowStockCount ==
            0,
      );

      // Sell 3 of the 7 through the real billing controller.
      await awaitUntil(
        container,
        () => container.read(posProductsProvider) is AsyncData,
      );
      final sellable = container.read(posProductsProvider).requireValue.single;
      expect(sellable.stockQuantity, 7);

      final cart = container.read(cartProvider.notifier);
      cart.add(sellable);
      cart.setQuantity('p1', 3);
      final completed = await cart.checkout(PaymentMethod.cash);
      expect(completed.sale.receiptNumber, 'BF-000001');

      await awaitUntil(
        container,
        () =>
            container.read(posProductsProvider).value?.single.stockQuantity ==
            4,
      );
      await awaitUntil(
        container,
        () =>
            (container.read(productMovementsProvider('p1')).value ?? const [])
                .length ==
            2,
      );
      await awaitUntil(
        container,
        () =>
            container.read(dashboardControllerProvider).value?.lowStockCount ==
            1,
      );
      // The inventory product list must show the deducted stock too — the
      // inventory page cannot keep serving the pre-sale level after a POS sale.
      await awaitUntil(
        container,
        () => container.read(productsProvider).value?.single.stockQuantity == 4,
        reason: 'productsProvider stayed stale after a POS sale',
      );

      expect(container.read(productsProvider).value!.single.stockQuantity, 4);
      expect(
        container.read(posProductsProvider).value!.single.stockQuantity,
        4,
      );
      final history = container.read(productMovementsProvider('p1')).value!;
      final saleMovement = history.first;
      expect(saleMovement.movementType, StockMovementType.sale);
      expect(saleMovement.quantity, -3);
      expect(saleMovement.stockBefore, 7);
      expect(saleMovement.stockAfter, 4);
      expect(saleMovement.referenceType, 'SALE');
      expect(saleMovement.referenceId, completed.sale.id);
      final dashboard = container.read(dashboardControllerProvider).value!;
      expect(dashboard.lowStockCount, 1);
      expect(dashboard.dayOrderCount, 1);
      expect(dashboard.dayItemCount, 3);
    },
  );
}
