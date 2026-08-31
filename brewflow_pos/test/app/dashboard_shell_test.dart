import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/pages/module_placeholder_page.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_page.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_page.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_page.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_expenses_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_purchases_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_suppliers_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  Widget app(
    FakeAuthRepository fake, {
    FakeCustomerLedgerRepository? ledger,
  }) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        ledger ?? FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
      purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
    ],
    child: const BrewFlowApp(),
  );

  /// Wide + tall viewport so the extended sidebar shows labels and every
  /// dashboard section is built by the lazy list.
  Future<FakeAuthRepository> pumpAuthenticated(
    WidgetTester tester, {
    FakeCustomerLedgerRepository? ledger,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake, ledger: ledger));
    fake.emit(_owner);
    await tester.pumpAndSettle();
    return fake;
  }

  GoRouter routerOf(WidgetTester tester) {
    final element = tester.element(find.byType(Scaffold).first);
    return ProviderScope.containerOf(element).read(appRouterProvider);
  }

  String currentPath(WidgetTester tester) =>
      routerOf(tester).routeInformationProvider.value.uri.path;

  Finder railLabel(String label) =>
      find.descendant(of: find.byType(AppSidebar), matching: find.text(label));

  Finder inPage(String text) => find.descendant(
    of: find.byType(DashboardPage),
    matching: find.text(text),
  );

  int sidebarIndex(WidgetTester tester) =>
      tester.widget<AppSidebar>(find.byType(AppSidebar)).selectedIndex;

  testWidgets(
    'authenticated users land in the application shell on /dashboard',
    (tester) async {
      await pumpAuthenticated(tester);

      expect(currentPath(tester), AppRoutes.dashboard);
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.byType(AppSidebar), findsOneWidget);
      expect(find.byType(AuthShell), findsNothing);
    },
  );

  testWidgets('dashboard route renders its structural sections', (
    tester,
  ) async {
    await pumpAuthenticated(tester);

    expect(inPage('Dashboard'), findsOneWidget);
    expect(inPage('Quick actions'), findsOneWidget);
    expect(inPage('New Sale'), findsOneWidget);
    expect(inPage('Manage Inventory'), findsOneWidget);
    expect(inPage('Review Orders'), findsOneWidget);
    expect(inPage('Sales'), findsOneWidget);
    expect(inPage('Profit'), findsOneWidget);
    expect(inPage('Bills'), findsOneWidget);
    expect(inPage('Items'), findsOneWidget);
    expect(inPage('Sales Overview'), findsOneWidget);
    expect(inPage('Payment Summary'), findsOneWidget);
    expect(inPage('Alerts'), findsOneWidget);
    expect(inPage('Recent Bills'), findsOneWidget);
    expect(inPage('Business at a Glance'), findsOneWidget);
  });

  testWidgets('all ten navigation destinations resolve', (tester) async {
    await pumpAuthenticated(tester);

    const destinations = [
      ('Dashboard', AppRoutes.dashboard),
      ('Inventory', AppRoutes.inventory),
      ('Billing', AppRoutes.billing),
      ('Orders', AppRoutes.orders),
      ('Customers', AppRoutes.customers),
      ('Suppliers', AppRoutes.suppliers),
      ('Purchases', AppRoutes.purchases),
      ('Expenses', AppRoutes.expenses),
      ('Reports', AppRoutes.reports),
      ('Settings', AppRoutes.settings),
    ];

    for (final (label, route) in destinations) {
      final index = AppRoutes.destinations.indexOf(route);

      await tester.tap(railLabel(label));
      await tester.pumpAndSettle();

      expect(currentPath(tester), route, reason: '$label lands on $route');
      expect(
        sidebarIndex(tester),
        index,
        reason: '$label is the active branch',
      );

      if (index == 0) {
        expect(find.byType(DashboardPage), findsOneWidget);
      } else if (index == 1) {
        expect(find.byType(InventoryPage), findsOneWidget);
      } else if (index == 2) {
        expect(
          find.byType(PosPage),
          findsOneWidget,
          reason: 'Billing lands on the POS page',
        );
      } else if (index == 3) {
        expect(
          find.byType(OrdersPage),
          findsOneWidget,
          reason: 'Orders lands on the orders history page',
        );
      } else if (index == 4) {
        expect(
          find.byType(CustomersPage),
          findsOneWidget,
          reason: 'Customers lands on the real customers page',
        );
        expect(
          find.text('Maintain customer profiles for your shop.'),
          findsOneWidget,
          reason: 'Customers page renders its header',
        );
      } else if (index == 5) {
        expect(
          find.byType(SuppliersPage),
          findsOneWidget,
          reason: 'Suppliers lands on the real suppliers page',
        );
        expect(
          find.text('Manage the suppliers you purchase stock from.'),
          findsOneWidget,
          reason: 'Suppliers page renders its header',
        );
      } else if (index == 6) {
        expect(
          find.byType(PurchasesPage),
          findsOneWidget,
          reason: 'Purchases lands on the real purchases page',
        );
        expect(
          find.text('Receive and review stock purchases.'),
          findsOneWidget,
          reason: 'Purchases page renders its header',
        );
      } else if (index == 7) {
        expect(
          find.byType(ExpensesPage),
          findsOneWidget,
          reason: 'Expenses lands on the real expenses page',
        );
        expect(
          find.text('Record and review business expenses.'),
          findsOneWidget,
          reason: 'Expenses page renders its header',
        );
      } else if (index == 8) {
        expect(
          find.byType(ReportsPage),
          findsOneWidget,
          reason: 'Reports lands on the real reports page',
        );
        expect(
          find.text('Sales, expenses and profit for a date range.'),
          findsOneWidget,
          reason: 'Reports page renders its header',
        );
      } else if (index == 9) {
        expect(
          find.byType(SettingsPage),
          findsOneWidget,
          reason: 'Settings lands on the real settings page',
        );
        expect(
          find.text('Business Name'),
          findsOneWidget,
          reason: 'Settings form renders the shop identity fields',
        );
      } else {
        final placeholder = find.descendant(
          of: find.byType(ModulePlaceholderPage),
          matching: find.text(label),
        );
        expect(placeholder, findsOneWidget, reason: '$label placeholder shown');
        expect(
          find.text('This module is coming in the next implementation phase.'),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('active destination indication changes with navigation', (
    tester,
  ) async {
    await pumpAuthenticated(tester);

    await tester.tap(railLabel('Billing'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.billing);
    expect(sidebarIndex(tester), 2);
  });

  testWidgets('navigation between destinations keeps the shell alive', (
    tester,
  ) async {
    await pumpAuthenticated(tester);

    await tester.tap(railLabel('Inventory'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.inventory);
    expect(find.byType(InventoryPage), findsOneWidget);
    expect(find.byType(DashboardPage), findsNothing);
    expect(find.byType(AppShell), findsOneWidget);

    await tester.tap(railLabel('Dashboard'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.dashboard);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
  });

  testWidgets('due reminders card opens the customers page', (tester) async {
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
    await pumpAuthenticated(tester, ledger: ledger);

    await tester.tap(find.text('Due Reminders'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.customers);
    expect(find.byType(CustomersPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logout triggers the existing auth flow and returns to /auth', (
    tester,
  ) async {
    final fake = await pumpAuthenticated(tester);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(fake.signOutCalls, 1);
    expect(currentPath(tester), AppRoutes.auth);
    expect(find.byType(AuthShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('unauthenticated users are still redirected to /auth', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(null);
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.auth);
    expect(find.byType(AuthShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets('dashboard renders no fake business data', (tester) async {
    await pumpAuthenticated(tester);

    final amounts = RegExp(r'\d[\d,]*\.\d{2}');
    final currencies = RegExp(r'[₹$€£]');
    final texts = tester.widgetList<Text>(
      find.descendant(
        of: find.byType(DashboardPage),
        matching: find.byType(Text),
      ),
    );
    for (final text in texts) {
      expect(
        text.data,
        isNot(matches(amounts)),
        reason: 'no fake amounts: ${text.data}',
      );
      expect(
        text.data,
        isNot(matches(currencies)),
        reason: 'no fake currency: ${text.data}',
      );
    }
    expect(find.textContaining('₹'), findsNothing);
  });

  testWidgets('shell renders without any network access', (tester) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(_owner);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('direct navigation to a named destination works', (tester) async {
    await pumpAuthenticated(tester);

    final router = routerOf(tester);
    router.goNamed('settings');
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.settings);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.text('Business Name'), findsOneWidget);
    expect(sidebarIndex(tester), 9);
  });

  testWidgets('responsive shell adapts without overflow on mobile, tablet and '
      'desktop', (tester) async {
    await pumpAuthenticated(tester);

    // Mobile: compact AppBar + bottom navigation, no sidebar.
    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(AppSidebar), findsNothing);
    expect(find.byType(AppBottomNavigation), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);

    // Settings is a secondary destination behind "More" on the phone bar.
    await tester.tap(
      find.descendant(
        of: find.byType(AppBottomNavigation),
        matching: find.byIcon(Icons.more_horiz_outlined),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.settings);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Tablet: persistent compact sidebar rail.
    tester.view.physicalSize = const Size(700, 1024);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(AppBottomNavigation), findsNothing);

    // Desktop: extended sidebar with branding.
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('BrewFlow'),
      ),
      findsOneWidget,
    );
    expect(currentPath(tester), AppRoutes.settings);
  });
}
