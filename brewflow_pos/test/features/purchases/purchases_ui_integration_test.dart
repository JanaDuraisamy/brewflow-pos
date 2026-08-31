import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_detail_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';

import '../../helpers/fake_auth_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// Phase 10 Step 7 — real SQLite integration. Drives the actual UI through
/// the Purchase controller into DriftPurchaseRepository.receivePurchase()
/// against an in-memory AppDatabase, then verifies every persisted side
/// effect directly from SQLite.
void main() {
  late AppDatabase database;
  late FakeAuthRepository fakeAuth;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    fakeAuth = FakeAuthRepository();
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedShop() async {
    await database
        .into(database.categories)
        .insert(CategoriesCompanion.insert(id: Value('c1'), name: 'Coffee'));
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value('p1'),
            categoryId: 'c1',
            name: 'Coffee Beans',
            sku: const Value('CB-1'),
            sellingPricePaise: 12000,
            costPricePaise: const Value(9000),
            stockQuantity: const Value(20),
          ),
        );
    await database
        .into(database.suppliers)
        .insert(
          SuppliersCompanion.insert(
            id: Value('s1'),
            name: 'Acme Supplies',
            phone: const Value('9845012345'),
          ),
        );
  }

  Widget app() => ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      authRepositoryProvider.overrideWithValue(fakeAuth),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  GoRouter routerOf(WidgetTester tester) {
    final element = tester.element(find.byType(Scaffold).first);
    return ProviderScope.containerOf(element).read(appRouterProvider);
  }

  Future<void> scrollFormTo(WidgetTester tester, Finder finder) async {
    final scrollable = find.descendant(
      of: find.byType(PurchaseFormPage),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(finder, 200, scrollable: scrollable.first);
    await tester.pump();
  }

  testWidgets(
    'purchasing stock through the UI persists atomically and refreshes '
    'inventory, history and movement data',
    (tester) async {
      await seedShop();
      await pumpAuthenticated(tester);

      // Open the receiving form via the purchases history page.
      routerOf(tester).go(AppRoutes.purchases);
      await pumpAsync(tester);
      await tester.tap(find.text('New Purchase').first);
      await pumpAsync(tester);
      expect(find.byType(PurchaseFormPage), findsOneWidget);

      // Select the active supplier.
      await tester.tap(find.text('Walk-in / No Supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Supplies'));
      await pumpAsync(tester);

      // Add the product and set quantity 5 at ₹100.
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-p1')), '5');
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('cost-p1')), '100');
      await pumpAsync(tester);

      // Receive.
      await scrollFormTo(tester, find.text('Receive Purchase'));
      await tester.tap(find.text('Receive Purchase'));
      await pumpAsync(tester);

      expect(
        find.textContaining('Purchase received successfully.'),
        findsOneWidget,
      );
      expect(find.textContaining('PUR-000001'), findsWidgets);
      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Coffee Beans'), findsOneWidget);
      expect(find.text('CB-1'), findsOneWidget);

      // --- Verify directly from SQLite ---
      final productRow = await (database.select(
        database.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(productRow.stockQuantity, 25);

      final purchases = await database.select(database.purchases).get();
      expect(purchases, hasLength(1));
      expect(purchases.single.purchaseNumber, 'PUR-000001');
      expect(purchases.single.supplierId, 's1');
      expect(purchases.single.totalPaise, 50000);

      final items = await database.select(database.purchaseItems).get();
      expect(items, hasLength(1));
      expect(items.single.productId, 'p1');
      expect(items.single.quantity, 5);
      expect(items.single.unitCostPaise, 10000);
      expect(items.single.lineTotalPaise, 50000);

      final movements = await database.select(database.stockMovements).get();
      expect(movements, hasLength(1));
      expect(movements.single.movementType, StockMovementType.purchase.dbValue);
      expect(movements.single.quantity, 5);
      expect(movements.single.stockBefore, 20);
      expect(movements.single.stockAfter, 25);
      expect(movements.single.referenceType, 'PURCHASE');
      expect(movements.single.referenceId, purchases.single.id);
      expect(movements.single.productId, 'p1');

      // Inventory UI reflects the new stock without a restart.
      routerOf(tester).go(AppRoutes.inventory);
      await pumpAsync(tester);
      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('Coffee Beans'), findsOneWidget);
      expect(find.text('25'), findsWidgets);
      expect(tester.takeException(), isNull);

      // Purchase history shows the new purchase; its detail shows snapshots.
      routerOf(tester).go(AppRoutes.purchases);
      await pumpAsync(tester);
      expect(find.text('PUR-000001'), findsOneWidget);
      await tester.tap(find.text('PUR-000001'));
      await pumpAsync(tester);
      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('₹100.00'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a deactivated supplier rejects receiving with no partial writes',
    (tester) async {
      await seedShop();
      await pumpAuthenticated(tester);

      // First receive succeeds through the UI.
      routerOf(tester).go(AppRoutes.purchases);
      await pumpAsync(tester);
      await tester.tap(find.text('New Purchase').first);
      await pumpAsync(tester);
      await tester.tap(find.text('Walk-in / No Supplier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Acme Supplies'));
      await pumpAsync(tester);
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await scrollFormTo(tester, find.text('Receive Purchase'));
      await tester.tap(find.text('Receive Purchase'));
      await pumpAsync(tester);
      expect(find.textContaining('PUR-000001'), findsWidgets);

      // Back on the form, whose cart was cleared by the successful receive.
      await tester.pageBack();
      await pumpAsync(tester);
      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(find.text('Items to receive (0)'), findsOneWidget);

      // Let the success snackbar dismiss so it cannot cover the action.
      await tester.pump(const Duration(seconds: 5));
      await pumpAsync(tester);

      // Deactivate the supplier.
      await database
          .update(database.suppliers)
          .write(SuppliersCompanion(isActive: const Value(false)));

      // Receiving again through the UI is rejected with the safe failure and
      // the form stays open with the cart intact.
      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await scrollFormTo(tester, find.text('Receive Purchase'));
      await tester.tap(find.text('Receive Purchase'));
      await pumpAsync(tester);
      expect(
        find.textContaining('This supplier is deactivated'),
        findsOneWidget,
      );
      expect(find.byType(PurchaseFormPage), findsOneWidget);
      expect(find.text('Items to receive (1)'), findsOneWidget);

      // Receiving again through the authoritative repository is rejected too.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PurchaseFormPage)),
      );
      await expectLater(
        container
            .read(purchasesRepositoryProvider)
            .receivePurchase(
              lines: const [
                PurchaseLine(productId: 'p1', quantity: 1, unitCostPaise: 5000),
              ],
              supplierId: 's1',
            ),
        throwsA(isA<InactiveSupplierFailure>()),
      );

      // No partial writes: stock, purchases, items and movements unchanged.
      final productRow = await (database.select(
        database.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(productRow.stockQuantity, 21);
      expect(await database.select(database.purchases).get(), hasLength(1));
      expect(await database.select(database.purchaseItems).get(), hasLength(1));
      expect(
        await database.select(database.stockMovements).get(),
        hasLength(1),
      );
    },
  );
}
