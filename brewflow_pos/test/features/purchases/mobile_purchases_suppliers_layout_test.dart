import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
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
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_page.dart';
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

/// All logical phone widths the phone-only layouts must survive without
/// overflow.
const _phoneWidths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

void main() {
  for (final width in _phoneWidths) {
    testWidgets(
      'purchases and suppliers phone layouts have zero overflow at ${width}dp',
      (tester) async {
        tester.view.devicePixelRatio = 1.0;
        tester.view.physicalSize = Size(width, 800);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);

        final now = DateTime.now().toUtc();
        final fakeAuth = FakeAuthRepository();
        final fakePurchases = FakePurchasesRepository();
        final fakeSuppliers = FakeSuppliersRepository();

        fakeSuppliers.storedSuppliers.addAll([
          Supplier(
            id: 's1',
            name: 'Acme Supplies',
            phone: '9845012345',
            email: 'orders@acmesupplydistributors.example.com',
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          Supplier(
            id: 's2',
            name: 'Brew Traders',
            phone: '9000012345',
            isActive: true,
            createdAt: now,
            updatedAt: now,
          ),
          Supplier(
            id: 's3',
            name: 'Old Mills',
            isActive: false,
            createdAt: now,
            updatedAt: now,
          ),
        ]);
        fakePurchases.storedPurchases.addAll([
          Purchase(
            id: 'p2',
            supplierId: 's1',
            purchaseNumber: 'PUR-000002',
            subtotalPaise: 5000,
            totalPaise: 5000,
            createdAt: now,
            updatedAt: now,
          ),
          Purchase(
            id: 'p1',
            purchaseNumber: 'PUR-000001',
            subtotalPaise: 120000,
            totalPaise: 120000,
            createdAt: now,
            updatedAt: now,
          ),
        ]);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(fakeAuth),
              customersRepositoryProvider.overrideWithValue(
                FakeCustomersRepository(),
              ),
              customerLedgerRepositoryProvider.overrideWithValue(
                FakeCustomerLedgerRepository(),
              ),
              inventoryRepositoryProvider.overrideWithValue(
                FakeInventoryRepository(),
              ),
              ordersRepositoryProvider.overrideWithValue(
                FakeOrdersRepository(),
              ),
              suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
              purchasesRepositoryProvider.overrideWithValue(fakePurchases),
            ],
            child: const BrewFlowApp(),
          ),
        );
        fakeAuth.emit(_owner);
        await tester.pumpAndSettle();
        await tester.pumpAndSettle();

        final element = tester.element(find.byType(Scaffold).first);
        final router = ProviderScope.containerOf(
          element,
        ).read(appRouterProvider);

        router.go(AppRoutes.purchases);
        for (var i = 0; i < 10; i++) {
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byType(PurchasesPage), findsOneWidget);
        expect(find.byType(DataTable), findsNothing);
        expect(find.text('PUR-000002'), findsOneWidget);
        expect(find.text('Walk-in'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');

        router.go(AppRoutes.suppliers);
        for (var i = 0; i < 10; i++) {
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(find.byType(SuppliersPage), findsOneWidget);
        expect(find.byType(DataTable), findsNothing);
        expect(find.text('Acme Supplies'), findsOneWidget);
        expect(find.text('Brew Traders'), findsOneWidget);
        expect(find.text('Old Mills'), findsOneWidget);
        expect(find.textContaining('9845012345'), findsOneWidget);
        expect(tester.takeException(), isNull, reason: 'no layout overflow');
      },
    );
  }

  testWidgets('long-press on a phone purchase card opens View Details', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now().toUtc();
    final fakeAuth = FakeAuthRepository();
    final fakePurchases = FakePurchasesRepository();
    fakePurchases.storedPurchases.add(
      Purchase(
        id: 'p2',
        supplierId: 's1',
        purchaseNumber: 'PUR-000002',
        subtotalPaise: 5000,
        totalPaise: 5000,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          suppliersRepositoryProvider.overrideWithValue(
            FakeSuppliersRepository(),
          ),
          purchasesRepositoryProvider.overrideWithValue(fakePurchases),
        ],
        child: const BrewFlowApp(),
      ),
    );
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.purchases);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final card = find.ancestor(
      of: find.text('PUR-000002'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('View Details'), findsOneWidget);
    await tester.tap(find.text('View Details'));
    await tester.pumpAndSettle();

    expect(find.byType(PurchaseDetailPage), findsOneWidget);
  });

  testWidgets('long-press on a phone supplier card opens sheet and deactivate '
      'confirms', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now().toUtc();
    final fakeAuth = FakeAuthRepository();
    final fakeSuppliers = FakeSuppliersRepository();
    fakeSuppliers.storedSuppliers.addAll([
      Supplier(
        id: 's1',
        name: 'Acme Supplies',
        phone: '9845012345',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
      Supplier(
        id: 's3',
        name: 'Old Mills',
        isActive: false,
        createdAt: now,
        updatedAt: now,
      ),
    ]);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
          purchasesRepositoryProvider.overrideWithValue(
            FakePurchasesRepository(),
          ),
        ],
        child: const BrewFlowApp(),
      ),
    );
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.suppliers);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    final card = find.ancestor(
      of: find.text('Acme Supplies'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);

    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    expect(find.text('Deactivate supplier'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();

    final acme = fakeSuppliers.storedSuppliers.firstWhere(
      (supplier) => supplier.id == 's1',
    );
    expect(acme.isActive, isFalse);
  });

  testWidgets('long-press on a tablet supplier card opens the sheet', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(700, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final now = DateTime.now().toUtc();
    final fakeAuth = FakeAuthRepository();
    final fakeSuppliers = FakeSuppliersRepository();
    fakeSuppliers.storedSuppliers.add(
      Supplier(
        id: 's1',
        name: 'Acme Supplies',
        phone: '9845012345',
        isActive: true,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(fakeAuth),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          suppliersRepositoryProvider.overrideWithValue(fakeSuppliers),
          purchasesRepositoryProvider.overrideWithValue(
            FakePurchasesRepository(),
          ),
        ],
        child: const BrewFlowApp(),
      ),
    );
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.suppliers);
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();

    // Tablet (600-799dp) renders the wider _SupplierCard, not the table.
    expect(find.byType(DataTable), findsNothing);

    final card = find.ancestor(
      of: find.text('Acme Supplies'),
      matching: find.byType(AppCard),
    );
    expect(card, findsOneWidget);
    await tester.longPress(card);
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Deactivate'), findsOneWidget);
  });
}
