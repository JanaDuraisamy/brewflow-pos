import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

void main() {
  final owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

  Widget harness({
    FakeOrdersRepository? orders,
    FakeInventoryRepository? inventory,
    FakeCustomerLedgerRepository? ledger,
    FakeSettingsRepository? settings,
    FakeStaffRepository? staff,
  }) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: owner)),
      ordersRepositoryProvider.overrideWithValue(
        orders ?? FakeOrdersRepository(),
      ),
      inventoryRepositoryProvider.overrideWithValue(
        inventory ?? FakeInventoryRepository(),
      ),
      customerLedgerRepositoryProvider.overrideWithValue(
        ledger ?? FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        settings ?? FakeSettingsRepository(),
      ),
      if (staff != null) staffRepositoryProvider.overrideWithValue(staff),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
    ],
    child: const MaterialApp(home: Scaffold(body: DashboardPage())),
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    FakeOrdersRepository? orders,
    FakeInventoryRepository? inventory,
    FakeCustomerLedgerRepository? ledger,
    Size viewSize = const Size(800, 2800),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      harness(orders: orders, inventory: inventory, ledger: ledger),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty data renders honest empty states without amounts', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Profit'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Items'), findsOneWidget);
    expect(find.text('Sales Overview'), findsOneWidget);
    expect(find.text('Payment Summary'), findsOneWidget);
    expect(find.text('Alerts'), findsOneWidget);
    expect(find.text('Recent Bills'), findsOneWidget);
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Business at a Glance'), findsOneWidget);
    expect(find.text('No sales recorded in this window'), findsOneWidget);
    expect(
      find.text('No bills recorded yet — your first sale will appear here.'),
      findsOneWidget,
    );
    expect(find.text('No items running low right now'), findsOneWidget);
    expect(find.text('Everything you sell is in stock'), findsOneWidget);
    expect(
      find.text('No dues right now — everyone is settled'),
      findsOneWidget,
    );
    expect(find.text('Not signed in'), findsOneWidget);

    final amounts = RegExp(r'\d[\d,]*\.\d{2}');
    final currencies = RegExp(r'[₹$€£]');
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.data, isNot(matches(amounts)), reason: text.data);
      expect(text.data, isNot(matches(currencies)), reason: text.data);
    }
    expect(find.textContaining('₹'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seeded data renders real KPIs, chart, payments and bills', (
    tester,
  ) async {
    final inventory = FakeInventoryRepository();
    await inventory.createCategory('Drinks');
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Filter Coffee',
      sellingPricePaise: 1000,
      costPricePaise: 400,
      stockQuantity: 3,
      isActive: true,
    );
    await inventory.createProduct(
      categoryId: 'category-1',
      name: 'Jigarthanda',
      sellingPricePaise: 1500,
      costPricePaise: 700,
      stockQuantity: 20,
      isActive: true,
    );
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'BF-0001',
      createdAt: DateTime.now(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 3500,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'SKU-1',
          unitPricePaise: 1000,
          quantity: 2,
          lineTotalPaise: 2000,
          productId: 'product-1',
        ),
        OrderItem(
          productName: 'Jigarthanda',
          sku: 'SKU-2',
          unitPricePaise: 1500,
          quantity: 1,
          lineTotalPaise: 1500,
          productId: 'product-2',
        ),
      ],
    );

    await pumpDashboard(tester, orders: orders, inventory: inventory);

    final kpis = find.byType(KpiCard);
    expect(
      find.descendant(of: kpis, matching: find.text('₹35.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kpis, matching: find.text('₹20.00')),
      findsOneWidget,
    );
    expect(find.descendant(of: kpis, matching: find.text('1')), findsOneWidget);
    expect(find.descendant(of: kpis, matching: find.text('3')), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(SectionCard, 'Payment Summary'),
        matching: find.text('₹35.00'),
      ),
      findsNWidgets(2), // Cash row + Total
    );
    expect(find.text('BF-0001'), findsOneWidget);
    expect(find.textContaining('Cash · 3 items'), findsOneWidget);
    final alerts = find.byType(AlertCard);
    expect(
      find.descendant(of: alerts, matching: find.text('1')),
      findsOneWidget,
    );
    expect(find.text('No items running low right now'), findsNothing);
    expect(
      find.text('Everything you sell is in stock'),
      findsOneWidget, // nothing in the seeded data is out of stock
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment summary shows em dashes when the day has no sales', (
    tester,
  ) async {
    await pumpDashboard(tester);

    final dashes = find.text('—');
    expect(dashes, findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('date chip opens the date picker', (tester) async {
    await pumpDashboard(tester);

    expect(find.textContaining('Today ·'), findsOneWidget);
    await tester.tap(find.textContaining('Today ·'));
    await tester.pumpAndSettle();

    expect(find.byType(DatePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('due reminders reflect customers with outstanding dues', (
    tester,
  ) async {
    final ledger = FakeCustomerLedgerRepository();
    ledger.bills.addAll([
      FakeLedgerBill(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        totalPaise: 8000,
      ),
      FakeLedgerBill(
        id: 's2',
        customerId: 'c2',
        receiptNumber: 'BF-000002',
        createdAt: DateTime.utc(2026, 1, 2),
        totalPaise: 2000,
      ),
    ]);
    await pumpDashboard(tester, ledger: ledger);

    expect(find.text('Due Reminders'), findsOneWidget);
    expect(find.text('₹100.00 outstanding across 2 customers'), findsOneWidget);
    expect(find.text('No dues right now — everyone is settled'), findsNothing);
    final alerts = find.byType(AlertCard);
    expect(
      find.descendant(of: alerts, matching: find.text('2')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('due reminder message singularizes a single customer', (
    tester,
  ) async {
    final ledger = FakeCustomerLedgerRepository();
    ledger.bills.add(
      FakeLedgerBill(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-000001',
        createdAt: DateTime.utc(2026, 1, 1),
        totalPaise: 8000,
      ),
    );
    await pumpDashboard(tester, ledger: ledger);

    expect(find.text('₹80.00 outstanding across 1 customer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error state offers a working retry', (tester) async {
    final orders = FakeOrdersRepository()..ordersError = Exception('db');
    await pumpDashboard(tester, orders: orders);

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Try Again'), findsOneWidget);

    orders.ordersError = null;
    await tester.tap(find.text('Try Again'));
    await tester.pumpAndSettle();

    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('Something went wrong'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page supports pull-to-refresh and scrolls without overflow', (
    tester,
  ) async {
    await pumpDashboard(tester, viewSize: const Size(320, 568));

    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.fling(find.byType(ListView), const Offset(0, 300), 1000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the avatar opens the account menu, not Settings', (
    tester,
  ) async {
    await pumpDashboard(tester);

    // The avatar no longer jumps straight to Settings.
    await tester.tap(find.byType(AppAvatar));
    await tester.pumpAndSettle();

    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Change Account'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text(owner.email), findsOneWidget);

    // Profile reveals the signed-in identity without leaving the page.
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsWidgets);
    expect(find.textContaining(owner.email), findsWidgets);
  });
}
