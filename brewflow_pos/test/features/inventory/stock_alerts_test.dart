import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_alerts_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_alerts_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock notification center contract.
///
/// The panel reuses the SAME stock rules as dashboard/inventory filters
/// (no second engine): out-of-stock vs low-stock are distinct, variants are
/// per-entity, OFF/none excluded, one row per shop/product/variant, taps
/// focus Inventory on exactly that product.
/// ---------------------------------------------------------------------------

void main() {
  final now = DateTime.now().toUtc();

  Product product(
    String id,
    String name, {
    int stock = 0,
    int? threshold,
    LowStockMode mode = LowStockMode.custom,
    bool isActive = true,
    String? shopId = 'shop-1',
    StockUnit unit = StockUnit.count,
    List<ProductVariant> variants = const [],
  }) => Product(
    id: id,
    categoryId: 'c1',
    name: name,
    sellingPricePaise: 100,
    stockQuantity: stock,
    lowStockMode: mode,
    lowStockThreshold: threshold,
    isActive: isActive,
    shopId: shopId,
    stockUnit: unit,
    createdAt: now,
    updatedAt: now,
    variants: variants,
  );

  ProductVariant variant(
    String id,
    String productId,
    String name, {
    int stock = 0,
    int? threshold,
    LowStockMode mode = LowStockMode.custom,
    bool isActive = true,
  }) => ProductVariant(
    id: id,
    productId: productId,
    name: name,
    sellingPricePaise: 100,
    stockQuantity: stock,
    lowStockMode: mode,
    lowStockThreshold: threshold,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  group('buildStockAlerts', () {
    test('out-of-stock and low-stock are distinct states', () {
      final alerts = buildStockAlerts([
        product('p-out', 'Maggi Packet', stock: 0, threshold: 10),
        product('p-low', 'Amul Ice Cream', stock: 4, threshold: 10),
        product('p-ok', 'Milk', stock: 50, threshold: 10),
      ], 5);
      expect(alerts.map((a) => a.productId).toSet(), {'p-out', 'p-low'});
      final byId = {for (final a in alerts) a.productId: a};
      expect(byId['p-out']!.kind, StockAlertKind.outOfStock);
      expect(byId['p-low']!.kind, StockAlertKind.lowStock);
      expect(byId['p-low']!.stock, 4);
      expect(byId['p-low']!.threshold, 10);
    });

    test('variant entities alert per variant', () {
      final alerts = buildStockAlerts([
        product(
          'p-shirt',
          'Shirt',
          stock: 0,
          variants: [
            variant('v-s', 'p-shirt', 'S', stock: 0, threshold: 5),
            variant('v-m', 'p-shirt', 'M', stock: 3, threshold: 5),
            variant('v-l', 'p-shirt', 'L', stock: 50, threshold: 5),
          ],
        ),
      ], 5);
      expect(alerts, hasLength(2));
      expect(alerts.map((a) => a.variantId).toSet(), {'v-s', 'v-m'});
      expect(
        alerts.firstWhere((a) => a.variantId == 'v-s').kind,
        StockAlertKind.outOfStock,
      );
      expect(
        alerts.firstWhere((a) => a.variantId == 'v-m').kind,
        StockAlertKind.lowStock,
      );
    });

    test('OFF mode and untracked units never alert', () {
      final alerts = buildStockAlerts([
        product('p-off', 'Off Item', stock: 0, mode: LowStockMode.off),
        product(
          'p-none',
          'Made To Order',
          stock: 0,
          unit: StockUnit.none,
          threshold: 5,
        ),
        product('p-inactive', 'Old', stock: 0, isActive: false, threshold: 5),
      ], 5);
      expect(alerts, isEmpty);
    });

    test('no duplicate rows for the same entity', () {
      final alerts = buildStockAlerts([
        product('p-dup', 'Dup', stock: 0, threshold: 10),
        product('p-dup', 'Dup', stock: 0, threshold: 10),
      ], 5);
      expect(alerts, hasLength(1));
      expect(alerts.single.key, 'shop-1|p-dup|-');
    });

    test('same product in two shops stays isolated', () {
      final alerts = buildStockAlerts([
        product(
          'p-same',
          'Naren Special',
          stock: 0,
          threshold: 5,
          shopId: 'cafe',
        ),
        product(
          'p-same',
          'Naren Special',
          stock: 0,
          threshold: 5,
          shopId: 'truck',
        ),
      ], 5);
      expect(alerts, hasLength(2));
      expect(alerts.map((a) => a.shopId).toSet(), {'cafe', 'truck'});
    });

    test('empty when nothing needs attention', () {
      expect(buildStockAlerts([], 5), isEmpty);
      expect(
        buildStockAlerts([
          product('p-ok', 'Milk', stock: 50, threshold: 10),
        ], 5),
        isEmpty,
      );
    });
  });

  group('stockAlertsProvider', () {
    test('surfaces low and out alerts from the scoped catalogue', () async {
      final fake = FakeInventoryRepository()
        ..storedProducts.addAll([
          product('p-out', 'Maggi Packet', stock: 0, threshold: 10),
          product('p-low', 'Amul Ice Cream', stock: 4, threshold: 10),
          product('p-ok', 'Milk', stock: 50, threshold: 10),
        ]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fake),
          ...businessScopeOverrides(),
        ],
      );
      addTearDown(container.dispose);

      final alerts = await container.read(stockAlertsProvider.future);
      expect(alerts.map((a) => a.productId).toSet(), {'p-out', 'p-low'});
    });

    test('staff sees only the assigned shop', () async {
      final fake = FakeInventoryRepository()
        ..storedProducts.addAll([
          product(
            'p-cafe',
            'Cafe Milk',
            stock: 0,
            threshold: 5,
            shopId: 'shop-1',
          ),
          product(
            'p-truck',
            'Truck Milk',
            stock: 0,
            threshold: 5,
            shopId: 'shop-2',
          ),
        ]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fake),
          ...businessScopeOverrides(
            profile: testStaffProfile(shopId: 'shop-2'),
          ),
        ],
      );
      addTearDown(container.dispose);

      final alerts = await container.read(stockAlertsProvider.future);
      expect(alerts.map((a) => a.productId), ['p-truck']);
    });
  });

  group('alert deep-link', () {
    test('focus narrows Inventory to exactly one product', () async {
      final fake = FakeInventoryRepository()
        ..storedProducts.addAll([
          product('p-out', 'Maggi Packet', stock: 0, threshold: 10),
          product('p-low', 'Amul Ice Cream', stock: 4, threshold: 10),
        ]);
      final container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(fake),
          ...businessScopeOverrides(),
        ],
      );
      addTearDown(container.dispose);

      container
          .read(inventoryFilterProvider.notifier)
          .focusOn(productId: 'p-low');
      final listed = await container.read(productsProvider.future);
      expect(listed.map((p) => p.id), ['p-low']);
    });
  });

  group('alert panel widget', () {
    Future<void> pumpSheet(
      WidgetTester tester,
      FakeInventoryRepository fake,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fake),
            ...businessScopeOverrides(),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => ElevatedButton(
                    onPressed: () => showStockAlertsSheet(context, ref),
                    child: const Text('Open alerts'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open alerts'));
      await tester.pumpAndSettle();
    }

    testWidgets('bell opens the panel with low and out alerts', (tester) async {
      final fake = FakeInventoryRepository()
        ..storedProducts.addAll([
          product('p-out', 'Maggi Packet', stock: 0, threshold: 10),
          product('p-low', 'Amul Ice Cream', stock: 4, threshold: 10),
        ]);
      await pumpSheet(tester, fake);

      expect(find.text('Stock Alerts'), findsOneWidget);
      expect(find.text('OUT OF STOCK'), findsOneWidget);
      expect(find.text('LOW STOCK'), findsOneWidget);
      expect(find.text('Maggi Packet'), findsOneWidget);
      expect(find.text('Amul Ice Cream'), findsOneWidget);
      expect(find.text('Stock: 0'), findsOneWidget);
      expect(find.text('Stock: 4 · Minimum: 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping an alert focuses Inventory on that product', (
      tester,
    ) async {
      final fake = FakeInventoryRepository()
        ..storedProducts.addAll([
          product('p-out', 'Maggi Packet', stock: 0, threshold: 10),
          product('p-low', 'Amul Ice Cream', stock: 4, threshold: 10),
        ]);
      await pumpSheet(tester, fake);

      await tester.tap(find.text('Amul Ice Cream'));
      await tester.pumpAndSettle();

      // Sheet closed and the router attempted the inventory deep-link; the
      // focus filter is the contract the inventory list honors.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
        listen: false,
      );
      expect(container.read(inventoryFilterProvider).focusProductId, 'p-low');
    });

    testWidgets('empty catalogue shows the empty state', (tester) async {
      await pumpSheet(tester, FakeInventoryRepository());

      expect(find.text('No stock alerts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('narrow 360dp phone has no horizontal overflow', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final fake = FakeInventoryRepository()
        ..storedProducts.add(
          product(
            'p-long',
            'Extra Long Product Name For Narrow Phone Wrapping Test Case',
            stock: 0,
            threshold: 10,
          ),
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(fake),
            ...businessScopeOverrides(),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => ElevatedButton(
                    onPressed: () => showStockAlertsSheet(context, ref),
                    child: const Text('Open alerts'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Stock Alerts'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
