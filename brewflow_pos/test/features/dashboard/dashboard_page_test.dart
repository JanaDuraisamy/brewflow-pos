import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/sales_breakdown_sheets.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:drift/native.dart';
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
import '../../helpers/test_providers.dart';

void main() {
  final owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

  Widget harness({
    FakeOrdersRepository? orders,
    FakeInventoryRepository? inventory,
    FakeCustomerLedgerRepository? ledger,
    FakeSettingsRepository? settings,
    FakeStaffRepository? staff,
    AppDatabase? syncDb,
    DriftSyncRepository? syncRepo,
    SyncStatusSnapshot? syncStatus,
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
      // Shop-scoped dashboard reads resolve their scope from the signed-in
      // profile, so the fixture must declare the owner session explicitly.
      ...businessScopeOverrides(staff: staff),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
      if (syncDb != null) appDatabaseProvider.overrideWithValue(syncDb),
      if (syncRepo != null) syncRepositoryProvider.overrideWithValue(syncRepo),
      // Pin the snapshot while keeping the real controller (and its real
      // syncNow) behind the badge.
      if (syncStatus != null)
        syncStatusProvider.overrideWithBuild((ref, notifier) => syncStatus),
    ],
    child: const MaterialApp(home: Scaffold(body: DashboardPage())),
  );

  Future<void> pumpDashboard(
    WidgetTester tester, {
    FakeOrdersRepository? orders,
    FakeInventoryRepository? inventory,
    FakeCustomerLedgerRepository? ledger,
    AppDatabase? syncDb,
    DriftSyncRepository? syncRepo,
    SyncStatusSnapshot? syncStatus,
    Size viewSize = const Size(800, 2800),
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = viewSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      harness(
        orders: orders,
        inventory: inventory,
        ledger: ledger,
        syncDb: syncDb,
        syncRepo: syncRepo,
        syncStatus: syncStatus,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty data renders honest empty states without amounts', (
    tester,
  ) async {
    await pumpDashboard(tester);

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Sales'), findsOneWidget);
    expect(find.text('Due Collected'), findsOneWidget);
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
      find.text(
        'No bills recorded yet — start one with New Sale in Quick '
        'actions below.',
      ),
      findsOneWidget,
    );
    expect(find.text('No items running low right now'), findsOneWidget);
    expect(find.text('Everything you sell is in stock'), findsOneWidget);
    expect(
      find.text('No dues right now — everyone is settled'),
      findsOneWidget,
    );
    expect(find.text('Connecting…'), findsOneWidget);

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
    // No dues were collected, so the Due Collected card shows an em dash.
    expect(
      find.descendant(of: kpis, matching: find.text('Due Collected')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kpis, matching: find.text('No dues collected')),
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

  testWidgets('due collected card opens the customer-wise breakdown', (
    tester,
  ) async {
    final ledger = FakeCustomerLedgerRepository();
    ledger.bills.addAll([
      FakeLedgerBill(
        id: 's1',
        customerId: 'c1',
        receiptNumber: 'BF-s1',
        createdAt: DateTime.utc(2026, 1, 1),
        totalPaise: 10000,
        shopId: kTestCafeShopId,
        customerName: 'Asha',
      ),
      FakeLedgerBill(
        id: 's2',
        customerId: 'c2',
        receiptNumber: 'BF-s2',
        createdAt: DateTime.utc(2026, 1, 1),
        totalPaise: 20000,
        shopId: kTestCafeShopId,
        customerName: 'Bala',
      ),
    ]);
    final now = DateTime.now();
    ledger.seedPayment(
      customerId: 'c1',
      saleId: 's1',
      amountPaise: 4000,
      paymentMethod: PaymentMethod.cash,
      paidAt: DateTime(now.year, now.month, now.day, 9).toUtc(),
    );
    ledger.seedPayment(
      customerId: 'c2',
      saleId: 's2',
      amountPaise: 7000,
      paymentMethod: PaymentMethod.upi,
      paidAt: DateTime(now.year, now.month, now.day, 18).toUtc(),
      note: 'Evening round',
    );

    await pumpDashboard(tester, ledger: ledger);

    final kpis = find.byType(KpiCard);
    expect(
      find.descendant(of: kpis, matching: find.text('₹110.00')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: kpis, matching: find.text('2 payments')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: kpis, matching: find.text('Due Collected')),
    );
    await tester.pumpAndSettle();

    // Card label plus sheet title.
    expect(find.text('Due Collected'), findsNWidgets(2));
    expect(find.text('Asha'), findsOneWidget);
    expect(find.text('Bala'), findsOneWidget);
    expect(find.text('₹40.00'), findsOneWidget);
    expect(find.text('₹70.00'), findsOneWidget);
    expect(find.textContaining('Cash ·'), findsOneWidget);
    expect(find.textContaining('UPI ·'), findsOneWidget);
    expect(find.text('Evening round'), findsOneWidget);
    // Newest first: Bala's row sits above Asha's.
    expect(
      tester.getCenter(find.text('Bala')).dy,
      lessThan(tester.getCenter(find.text('Asha')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'due collected card shows an empty state when nothing was collected',
    (tester) async {
      await pumpDashboard(tester);

      final kpis = find.byType(KpiCard);
      await tester.tap(
        find.descendant(of: kpis, matching: find.text('Due Collected')),
      );
      await tester.pumpAndSettle();

      expect(find.text('No dues collected on this day.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('bills card opens the day bill breakdown', (tester) async {
    final now = DateTime.now();
    DateTime atHour(int hour) => DateTime(now.year, now.month, now.day, hour);
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'BF-CASH',
      createdAt: atHour(9),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 10000,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          unitPricePaise: 10000,
          quantity: 1,
          lineTotalPaise: 10000,
          productId: 'product-1',
        ),
      ],
      shopId: kTestCafeShopId,
    );
    orders.add(
      receiptNumber: 'BF-SPLIT',
      createdAt: atHour(12),
      totalPaise: 30000,
      items: const [
        OrderItem(
          productName: 'Jigarthanda',
          unitPricePaise: 15000,
          quantity: 2,
          lineTotalPaise: 30000,
          productId: 'product-2',
        ),
      ],
      shopId: kTestCafeShopId,
      splitLegs: {PaymentMethod.cash: 12000, PaymentMethod.upi: 18000},
    );
    orders.add(
      receiptNumber: 'BF-CREDIT',
      createdAt: atHour(18),
      paymentStatus: PaymentStatus.notPaid,
      totalPaise: 5000,
      items: const [
        OrderItem(
          productName: 'Tea',
          unitPricePaise: 5000,
          quantity: 1,
          lineTotalPaise: 5000,
          productId: 'product-3',
        ),
      ],
      shopId: kTestCafeShopId,
    );
    orders.add(
      receiptNumber: 'BF-OLD',
      createdAt: atHour(10).subtract(const Duration(days: 1)),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 90000,
      items: const [
        OrderItem(
          productName: 'Old',
          unitPricePaise: 90000,
          quantity: 1,
          lineTotalPaise: 90000,
          productId: 'product-4',
        ),
      ],
      shopId: kTestCafeShopId,
    );

    await pumpDashboard(tester, orders: orders);

    final kpis = find.byType(KpiCard);
    expect(find.descendant(of: kpis, matching: find.text('3')), findsOneWidget);
    await tester.tap(find.descendant(of: kpis, matching: find.text('Bills')));
    await tester.pumpAndSettle();

    // Card title plus sheet title. Bill rows are scoped to the sheet: the
    // Recent Bills section repeats the same receipts and totals.
    final sheet = find.byType(BillsBreakdownSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(find.text('Bills'), findsNWidgets(2));
    expect(inSheet('BF-CASH'), findsOneWidget);
    expect(inSheet('BF-SPLIT'), findsOneWidget);
    expect(inSheet('BF-CREDIT'), findsOneWidget);
    expect(inSheet('BF-OLD'), findsNothing);
    expect(inSheet('₹100.00'), findsOneWidget);
    expect(inSheet('₹300.00'), findsOneWidget);
    expect(inSheet('₹50.00'), findsOneWidget);
    // Split sales never crash the payment column; credit reads as Not paid.
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Cash ·')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Split')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('Not paid')),
      findsOneWidget,
    );
    // Newest first: evening credit above noon split above morning cash.
    expect(
      tester.getCenter(inSheet('BF-CREDIT')).dy,
      lessThan(tester.getCenter(inSheet('BF-SPLIT')).dy),
    );
    expect(
      tester.getCenter(inSheet('BF-SPLIT')).dy,
      lessThan(tester.getCenter(inSheet('BF-CASH')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('items card opens the day item breakdown', (tester) async {
    final now = DateTime.now();
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'BF-1',
      createdAt: DateTime(now.year, now.month, now.day, 10),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 11000,
      items: const [
        OrderItem(
          productName: 'Maggi',
          variantName: 'Cheese',
          variantId: 'v-cheese',
          unitPricePaise: 5000,
          quantity: 2,
          lineTotalPaise: 10000,
          productId: 'product-1',
        ),
        OrderItem(
          productName: 'Chai',
          unitPricePaise: 1000,
          quantity: 1,
          lineTotalPaise: 1000,
          productId: 'product-2',
        ),
      ],
      shopId: kTestCafeShopId,
    );

    await pumpDashboard(tester, orders: orders);

    final kpis = find.byType(KpiCard);
    await tester.tap(find.descendant(of: kpis, matching: find.text('Items')));
    await tester.pumpAndSettle();

    final sheet = find.byType(ItemsBreakdownSheet);
    expect(sheet, findsOneWidget);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));
    expect(find.text('Items'), findsNWidgets(2));
    expect(inSheet('Maggi — Cheese'), findsOneWidget);
    expect(inSheet('Chai'), findsOneWidget);
    expect(inSheet('₹100.00'), findsOneWidget);
    expect(inSheet('₹10.00'), findsOneWidget);
    expect(inSheet('2 pcs'), findsOneWidget);
    expect(inSheet('1 pcs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bills card shows an empty state without sales', (tester) async {
    await pumpDashboard(tester);

    final kpis = find.byType(KpiCard);
    await tester.tap(find.descendant(of: kpis, matching: find.text('Bills')));
    await tester.pumpAndSettle();
    expect(find.text('No bills recorded on this day.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('items card shows an empty state without sales', (tester) async {
    await pumpDashboard(tester);

    final kpis = find.byType(KpiCard);
    await tester.tap(find.descendant(of: kpis, matching: find.text('Items')));
    await tester.pumpAndSettle();
    expect(find.text('No items sold on this day.'), findsOneWidget);
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

  testWidgets('payment summary shows Cash / UPI / Not Paid and never Bank', (
    tester,
  ) async {
    // Regression: the summary used to list a Bank row and dropped credit
    // sales entirely, so the rows did not add up to the day total.
    final orders = FakeOrdersRepository();
    orders.add(
      receiptNumber: 'BF-CASH',
      createdAt: DateTime.now(),
      paymentMethod: PaymentMethod.cash,
      totalPaise: 10000,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'SKU-1',
          unitPricePaise: 10000,
          quantity: 1,
          lineTotalPaise: 10000,
          productId: 'product-1',
        ),
      ],
    );
    orders.add(
      receiptNumber: 'BF-UPI',
      createdAt: DateTime.now(),
      paymentMethod: PaymentMethod.upi,
      totalPaise: 20000,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'SKU-1',
          unitPricePaise: 20000,
          quantity: 1,
          lineTotalPaise: 20000,
          productId: 'product-1',
        ),
      ],
    );
    orders.add(
      receiptNumber: 'BF-CREDIT',
      createdAt: DateTime.now(),
      paymentStatus: PaymentStatus.notPaid,
      totalPaise: 30000,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'SKU-1',
          unitPricePaise: 30000,
          quantity: 1,
          lineTotalPaise: 30000,
          productId: 'product-1',
        ),
      ],
    );
    // A retired-BANK historical sale must not create a Bank row.
    orders.add(
      receiptNumber: 'BF-BANK',
      createdAt: DateTime.now(),
      paymentMethod: PaymentMethod.bank,
      totalPaise: 40000,
      items: const [
        OrderItem(
          productName: 'Filter Coffee',
          sku: 'SKU-1',
          unitPricePaise: 40000,
          quantity: 1,
          lineTotalPaise: 40000,
          productId: 'product-1',
        ),
      ],
    );

    await pumpDashboard(tester, orders: orders);

    final summary = find.widgetWithText(SectionCard, 'Payment Summary');
    expect(summary, findsOneWidget);
    await tester.ensureVisible(summary);
    await tester.pumpAndSettle();

    // The three current categories are present with the right amounts.
    expect(
      find.descendant(of: summary, matching: find.text('Cash')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('UPI')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: summary, matching: find.text('Not Paid')),
      findsOneWidget,
    );
    // Cash = 10000 + 40000 (bank folded in) = 50000 = ₹500.00
    expect(
      find.descendant(of: summary, matching: find.text('₹500.00')),
      findsOneWidget,
    );
    // UPI = 20000 = ₹200.00
    expect(
      find.descendant(of: summary, matching: find.text('₹200.00')),
      findsOneWidget,
    );
    // Not Paid = 30000 = ₹300.00
    expect(
      find.descendant(of: summary, matching: find.text('₹300.00')),
      findsOneWidget,
    );
    // Bank is folded into Cash, not shown as its own row.
    expect(
      find.descendant(of: summary, matching: find.text('Bank')),
      findsNothing,
    );
    // Cash + UPI + Not Paid == Total (50000 + 20000 + 30000 = 100000).
    expect(
      find.descendant(of: summary, matching: find.text('₹1,000.00')),
      findsOneWidget,
    );
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

    // Identity sheet only: role, email and shop with no action rows.
    // Sign-out lives in the shell header/sidebar, so the sheet carries
    // no Profile/Change Account/Sign out entries.
    expect(find.text(owner.email), findsOneWidget);
    expect(find.text('Profile'), findsNothing);
    expect(find.text('Change Account'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
    // The dashboard header bell was removed: stock alerts open from the
    // global shell header bell and the Alerts section instead.
    expect(find.byType(NotificationBell), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed-sync badge opens the failures sheet and retries a change',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = DriftSyncRepository(db);
      await repo.insertOutbox(
        SyncOutboxEntry(
          id: 'obx-prod-1',
          deviceId: 'device-a',
          shopId: 'shop-1',
          entity: 'PRODUCT',
          entityId: 'prod-1',
          operation: 'UPSERT',
          payload: '{"id":"prod-1"}',
          status: 'PENDING',
          attemptCount: 0,
        ),
      );
      await repo.parkFailed('obx-prod-1', 'Network is unreachable');

      await pumpDashboard(
        tester,
        syncDb: db,
        syncRepo: repo,
        syncStatus: const SyncStatusSnapshot(
          level: SyncStatusLevel.pending,
          pendingCount: 1,
          failedCount: 1,
        ),
      );

      // The card shows the tappable failed pill.
      expect(find.text('1 failed'), findsOneWidget);

      await tester.tap(find.text('1 failed'));
      await tester.pumpAndSettle();

      // Failures sheet renders the one entry with friendly copy.
      expect(find.text('Failed changes'), findsOneWidget);
      expect(find.text('Product upload'), findsOneWidget);
      expect(find.textContaining('reach the server'), findsOneWidget);
      expect(find.textContaining('Last attempt'), findsOneWidget);
      expect(find.widgetWithText(SecondaryButton, 'Retry'), findsOneWidget);

      // Retry requeues the change and the sheet empties out.
      await tester.tap(find.widgetWithText(SecondaryButton, 'Retry'));
      await tester.pumpAndSettle();

      expect(find.text('No failed changes'), findsOneWidget);
      expect(await repo.failedOutboxBatch(), isEmpty);
      expect(await repo.pendingOutboxBatch(), hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed badge tap opens the sheet without triggering sync now', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftSyncRepository(db);
    for (final id in ['obx-1', 'obx-2']) {
      await repo.insertOutbox(
        SyncOutboxEntry(
          id: id,
          deviceId: 'device-a',
          shopId: 'shop-1',
          entity: 'SALE',
          entityId: id,
          operation: 'UPSERT',
          payload: '{"id":"$id"}',
          status: 'PENDING',
          attemptCount: 0,
        ),
      );
      await repo.parkFailed(id, 'Network is unreachable');
    }

    await pumpDashboard(
      tester,
      syncDb: db,
      syncRepo: repo,
      syncStatus: const SyncStatusSnapshot(
        level: SyncStatusLevel.synced,
        failedCount: 2,
      ),
    );

    expect(find.text('2 failed'), findsOneWidget);
    // The card's own tap would run a real sync now; the badge must open the
    // sheet instead, leaving the card's headline untouched.
    await tester.tap(find.text('2 failed'));
    await tester.pumpAndSettle();
    expect(find.text('Failed changes'), findsOneWidget);
    expect(find.text('All synced'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retry-all button requeues every failed entry', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = DriftSyncRepository(db);
    for (final id in ['obx-1', 'obx-2']) {
      await repo.insertOutbox(
        SyncOutboxEntry(
          id: id,
          deviceId: 'device-a',
          shopId: 'shop-1',
          entity: 'SALE',
          entityId: id,
          operation: 'UPSERT',
          payload: '{"id":"$id"}',
          status: 'PENDING',
          attemptCount: 0,
        ),
      );
      await repo.parkFailed(id, 'Network is unreachable');
    }

    await pumpDashboard(
      tester,
      syncDb: db,
      syncRepo: repo,
      syncStatus: const SyncStatusSnapshot(
        level: SyncStatusLevel.pending,
        failedCount: 2,
      ),
    );

    await tester.tap(find.text('2 failed'));
    await tester.pumpAndSettle();

    expect(find.text('Retry all'), findsOneWidget);
    expect(find.widgetWithText(SecondaryButton, 'Retry'), findsNWidgets(2));

    await tester.tap(find.text('Retry all'));
    await tester.pumpAndSettle();

    expect(await repo.failedOutboxBatch(), isEmpty);
    expect(await repo.pendingOutboxBatch(), hasLength(2));
    expect(find.text('No failed changes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
