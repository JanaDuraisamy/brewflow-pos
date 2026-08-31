import 'dart:async';

import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_detail_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_form_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_purchases_repository.dart';
import '../../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakePurchasesRepository fakePurchases;
  late FakeSuppliersRepository fakeSuppliers;

  final now = DateTime.now().toUtc();

  Purchase purchase(
    String id,
    String number, {
    String? supplierId,
    int totalPaise = 0,
  }) => Purchase(
    id: id,
    supplierId: supplierId,
    purchaseNumber: number,
    subtotalPaise: totalPaise,
    totalPaise: totalPaise,
    createdAt: now,
    updatedAt: now,
  );

  Supplier supplier(String id, String name) => Supplier(
    id: id,
    name: name,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  PurchaseItem item(
    String id,
    String purchaseId, {
    required String productName,
    String? sku,
    int unitCostPaise = 10000,
    int quantity = 1,
  }) => PurchaseItem(
    id: id,
    purchaseId: purchaseId,
    productId: 'p-${productName.hashCode}',
    productName: productName,
    sku: sku,
    unitCostPaise: unitCostPaise,
    quantity: quantity,
    lineTotalPaise: unitCostPaise * quantity,
  );

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakePurchases = FakePurchasesRepository();
    fakeSuppliers = FakeSuppliersRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
      purchasesRepositoryProvider.overrideWithValue(fakePurchases),
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

  Future<void> openPurchases(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.purchases);
    await pumpAsync(tester);
  }

  group('purchase history', () {
    testWidgets('renders purchases with number, date, supplier and total', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      fakePurchases.storedPurchases.addAll([
        purchase('p1', 'PUR-000002', totalPaise: 5000),
        purchase('p2', 'PUR-000001', supplierId: 's1', totalPaise: 120000),
      ]);
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      expect(find.byType(PurchasesPage), findsOneWidget);
      expect(find.text('PUR-000001'), findsOneWidget);
      expect(find.text('PUR-000002'), findsOneWidget);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('Walk-in'), findsOneWidget);
      expect(find.text('₹50.00'), findsOneWidget);
      expect(find.text('₹1,200.00'), findsOneWidget);
    });

    testWidgets('shows the empty state when there are no purchases', (
      tester,
    ) async {
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      expect(find.text('No purchases yet'), findsOneWidget);
      expect(find.text('New Purchase'), findsWidgets);
    });

    testWidgets('new purchase opens the receiving form', (tester) async {
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      await tester.tap(find.text('New Purchase').first);
      await pumpAsync(tester);

      expect(find.byType(PurchaseFormPage), findsOneWidget);
    });

    testWidgets('search narrows by number and supplier, and clears', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      fakePurchases.storedPurchases.addAll([
        purchase('p1', 'PUR-000001', supplierId: 's1', totalPaise: 120000),
        purchase('p2', 'PUR-000002', totalPaise: 5000),
      ]);
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      await tester.enterText(find.byType(SearchField), 'PUR-000001');
      await pumpAsync(tester);
      expect(find.text('PUR-000001'), findsNWidgets(2));
      expect(find.text('PUR-000002'), findsNothing);

      await tester.enterText(find.byType(SearchField), 'acme');
      await pumpAsync(tester);
      expect(find.text('Acme Supplies'), findsOneWidget);
      expect(find.text('PUR-000002'), findsNothing);

      await tester.tap(find.byTooltip('Clear'));
      await pumpAsync(tester);
      expect(find.text('PUR-000002'), findsOneWidget);
    });

    testWidgets('a dead-end search shows the clear action', (tester) async {
      fakePurchases.storedPurchases.add(
        purchase('p1', 'PUR-000001', totalPaise: 5000),
      );
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      await tester.enterText(find.byType(SearchField), 'zzz');
      await pumpAsync(tester);

      expect(find.text('No purchases match your search'), findsOneWidget);
      expect(find.text('Clear Search'), findsOneWidget);

      await tester.tap(find.text('Clear Search'));
      await pumpAsync(tester);
      expect(find.text('PUR-000001'), findsOneWidget);
    });

    testWidgets('stays in a loading state while purchases load', (
      tester,
    ) async {
      fakePurchases.loadGate = Completer<void>();
      await pumpAuthenticated(tester);
      final element = tester.element(find.byType(Scaffold).first);
      final router = ProviderScope.containerOf(element).read(appRouterProvider);
      router.go(AppRoutes.purchases);
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(find.text('Loading purchases…'), findsOneWidget);

      fakePurchases.loadGate!.complete();
      await pumpAsync(tester);
      expect(find.text('No purchases yet'), findsOneWidget);
    });

    testWidgets('load failures show a safe error state that can retry', (
      tester,
    ) async {
      fakePurchases.loadError = Exception('boom');
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Please try again.'), findsNothing);

      fakePurchases.loadError = null;
      await tester.tap(find.text('Try Again'));
      await pumpAsync(tester);
      expect(find.text('No purchases yet'), findsOneWidget);
    });

    testWidgets('tapping a purchase opens its snapshot detail', (tester) async {
      fakePurchases.storedPurchases.add(
        purchase('p1', 'PUR-000001', supplierId: 's1', totalPaise: 60000),
      );
      fakePurchases.storedItems['p1'] = [
        item(
          'i1',
          'p1',
          productName: 'Coffee Beans',
          sku: 'CB-1',
          unitCostPaise: 10000,
          quantity: 6,
        ),
      ];
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      await tester.tap(find.text('PUR-000001'));
      await pumpAsync(tester);

      expect(find.byType(PurchaseDetailPage), findsOneWidget);
      expect(find.text('Coffee Beans'), findsOneWidget);
      expect(find.text('CB-1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('₹100.00'), findsOneWidget);
      expect(find.text('₹600.00'), findsWidgets);
      expect(find.text('Acme Supplies'), findsOneWidget);
    });
  });

  group('responsive layout', () {
    testWidgets('renders cards on mobile and a data table when wide', (
      tester,
    ) async {
      fakeSuppliers.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      fakePurchases.storedPurchases.add(
        purchase('p1', 'PUR-000001', supplierId: 's1', totalPaise: 120000),
      );
      await pumpAuthenticated(tester);
      await openPurchases(tester);

      tester.view.physicalSize = const Size(360, 640);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('PUR-000001'), findsOneWidget);

      tester.view.physicalSize = const Size(1440, 900);
      await pumpAsync(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('PUR-000001'), findsOneWidget);
    });
  });
}
