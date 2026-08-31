import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
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

/// Phase 10 Step 8 — end-to-end cross-module UI flow against real in-memory
/// SQLite: receive stock through the Purchase UI, watch the Inventory UI
/// increase, sell through the POS UI, and watch the Inventory UI decrease —
/// all without a restart, with receipt/purchase numbers isolated.
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
            sellingPricePaise: 15000,
            costPricePaise: const Value(8000),
            stockQuantity: const Value(20),
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

  Finder addButtonFor(String productName) => find.descendant(
    of: find.ancestor(of: find.text(productName), matching: find.byType(Card)),
    matching: find.widgetWithText(FilledButton, 'Add'),
  );

  testWidgets(
    'purchase UI then sale UI: inventory rises, falls, and numbers stay '
    'isolated',
    (tester) async {
      await seedShop();
      await pumpAuthenticated(tester);

      // ---- 1. Receive 5 units through the Purchase UI (20 -> 25).
      routerOf(tester).go(AppRoutes.purchases);
      await pumpAsync(tester);
      await tester.tap(find.text('New Purchase').first);
      await pumpAsync(tester);
      expect(find.byType(PurchaseFormPage), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-p1')));
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('qty-p1')), '5');
      await pumpAsync(tester);
      await tester.enterText(find.byKey(const Key('cost-p1')), '80');
      await pumpAsync(tester);
      await scrollFormTo(tester, find.text('Receive Purchase'));
      await tester.tap(find.text('Receive Purchase'));
      await pumpAsync(tester);
      expect(find.textContaining('PUR-000001'), findsWidgets);
      expect(find.byType(PurchaseDetailPage), findsOneWidget);

      // ---- 2. The Inventory UI shows the increased stock without restart.
      routerOf(tester).go(AppRoutes.inventory);
      await pumpAsync(tester);
      expect(find.byType(InventoryPage), findsOneWidget);
      expect(find.text('Coffee Beans'), findsOneWidget);
      expect(find.text('25'), findsWidgets);

      // ---- 3. Sell 5 units through the POS UI (25 -> 20).
      routerOf(tester).go(AppRoutes.billing);
      await pumpAsync(tester);
      expect(find.byType(PosPage), findsOneWidget);
      for (var i = 0; i < 5; i++) {
        await tester.tap(addButtonFor('Coffee Beans'));
        await pumpAsync(tester);
      }
      expect(find.text('5 in cart'), findsOneWidget);
      await tester.tap(find.text('UPI'));
      await pumpAsync(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
      await pumpAsync(tester);

      expect(find.text('Sale Complete'), findsOneWidget);
      expect(find.text('Receipt BF-000001'), findsOneWidget);
      expect(
        find.textContaining('Stock 20'),
        findsOneWidget,
        reason: 'POS shelf refreshes with the deducted stock',
      );
      await tester.tap(find.text('New Sale'));
      await pumpAsync(tester);
      expect(find.text('Your cart is empty'), findsOneWidget);

      // ---- 4. The Inventory UI shows the decreased stock without restart.
      routerOf(tester).go(AppRoutes.inventory);
      await pumpAsync(tester);
      expect(find.byType(InventoryPage), findsOneWidget);
      expect(
        find.text('20'),
        findsWidgets,
        reason: 'inventory page must not keep the pre-sale stock of 25',
      );
      expect(tester.takeException(), isNull);

      // ---- 5. Verify everything directly from SQLite.
      final productRow = await (database.select(
        database.products,
      )..where((t) => t.id.equals('p1'))).getSingle();
      expect(productRow.stockQuantity, 20);
      expect(
        productRow.sellingPricePaise,
        15000,
        reason: 'receiving never reprices the product',
      );

      final purchases = await database.select(database.purchases).get();
      expect(purchases, hasLength(1));
      expect(purchases.single.purchaseNumber, 'PUR-000001');
      expect(purchases.single.totalPaise, 40000);

      final sales = await database.select(database.sales).get();
      expect(sales, hasLength(1));
      expect(sales.single.receiptNumber, 'BF-000001');

      final movementsQuery = database.select(database.stockMovements)
        ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
      final movements = await movementsQuery.get();
      expect(movements, hasLength(2));
      expect(movements[0].movementType, StockMovementType.purchase.dbValue);
      expect(movements[0].quantity, 5);
      expect(movements[0].stockBefore, 20);
      expect(movements[0].stockAfter, 25);
      expect(movements[1].movementType, StockMovementType.sale.dbValue);
      expect(movements[1].quantity, -5);
      expect(movements[1].stockBefore, 25);
      expect(movements[1].stockAfter, 20);
      expect(movements[1].referenceType, 'SALE');
      expect(movements[1].referenceId, sales.single.id);

      // Let any trailing snackbar timers elapse so the test ends cleanly.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );
}
