import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/pages/module_placeholder_page.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:drift/native.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/app/widgets/filter_chip.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/closing/presentation/daily_closing_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_page.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_page.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_page.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_page.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchases_page.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_page.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_page.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_page.dart';
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
import '../helpers/fake_offers_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_purchases_repository.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_staff_repository.dart';
import '../helpers/fake_suppliers_repository.dart';
import '../helpers/test_providers.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  Widget app(
    FakeAuthRepository fake, {
    FakeCustomerLedgerRepository? ledger,
    FakeSettingsRepository? settings,
    FakeInventoryRepository? inventory,
    FakeStaffRepository? staff,
    DriftDailyClosingRepository? closing,
  }) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
      inventoryRepositoryProvider.overrideWithValue(
        inventory ?? FakeInventoryRepository(),
      ),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(inventory ?? FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        ledger ?? FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        settings ?? FakeSettingsRepository(),
      ),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
      purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
      // Inventory/category reads are shop-scoped, so the fixture has to declare
      // the signed-in owner session (this also supplies the staff repository).
      ...businessScopeOverrides(staff: staff),
      if (closing != null)
        dailyClosingRepositoryProvider.overrideWithValue(closing),
    ],
    child: const BrewFlowApp(),
  );

  /// Wide + tall viewport so the extended sidebar shows labels and every
  /// dashboard section is built by the lazy list.
  Future<FakeAuthRepository> pumpAuthenticated(
    WidgetTester tester, {
    FakeCustomerLedgerRepository? ledger,
    FakeInventoryRepository? inventory,
    FakeStaffRepository? staff,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final fake = FakeAuthRepository();
    await tester.pumpWidget(
      app(fake, ledger: ledger, inventory: inventory, staff: staff),
    );
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

  testWidgets('all navigation destinations resolve', (tester) async {
    await pumpAuthenticated(tester);

    const destinations = [
      ('Dashboard', AppRoutes.dashboard),
      ('Staff Management', AppRoutes.staff),
      ('Inventory', AppRoutes.inventory),
      ('Billing', AppRoutes.billing),
      ('Orders', AppRoutes.orders),
      ('Customers', AppRoutes.customers),
      ('Suppliers', AppRoutes.suppliers),
      ('Purchases', AppRoutes.purchases),
      ('Expenses', AppRoutes.expenses),
      ('Reports', AppRoutes.reports),
      ('Offers', AppRoutes.offers),
      ('Settings', AppRoutes.settings),
    ];

    for (final (label, route) in destinations) {
      // Branch position is derived from the route, never hardcoded: inserting
      // a destination must not silently re-point this test's page assertions.
      final index = AppRoutes.branchIndexOf(route);

      // The rail auto-collapses after EVERY navigation on widths >= 600
      // (desktop included — one contract, no width bands). Reopen it when
      // needed both before tapping the next destination and after checking
      // the landing widget, since reading the active item needs the rail.
      if (find.byType(AppSidebar).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
      }
      await tester.tap(railLabel(label));
      await tester.pumpAndSettle();

      expect(currentPath(tester), route, reason: '$label lands on $route');

      switch (route) {
        case AppRoutes.dashboard:
          expect(find.byType(DashboardPage), findsOneWidget);
        case AppRoutes.staff:
          expect(
            find.byType(StaffPage),
            findsOneWidget,
            reason:
                'Staff Management lands on the real staff page, '
                'not on Stock/Inventory',
          );
        case AppRoutes.inventory:
          expect(find.byType(InventoryPage), findsOneWidget);
        case AppRoutes.billing:
          expect(
            find.byType(PosPage),
            findsOneWidget,
            reason: 'Billing lands on the POS page',
          );
        case AppRoutes.orders:
          expect(
            find.byType(OrdersPage),
            findsOneWidget,
            reason: 'Orders lands on the orders history page',
          );
        case AppRoutes.customers:
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
        case AppRoutes.suppliers:
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
        case AppRoutes.purchases:
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
        case AppRoutes.expenses:
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
        case AppRoutes.reports:
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
        case AppRoutes.offers:
          expect(
            find.byType(OffersPage),
            findsOneWidget,
            reason: 'Offers lands on the real offers page',
          );
          expect(
            find.text('No offers yet'),
            findsOneWidget,
            reason: 'Offers page renders its empty state',
          );
        case AppRoutes.settings:
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
        default:
          final placeholder = find.descendant(
            of: find.byType(ModulePlaceholderPage),
            matching: find.text(label),
          );
          expect(
            placeholder,
            findsOneWidget,
            reason: '$label placeholder shown',
          );
          expect(
            find.text(
              'This module is coming in the next implementation phase.',
            ),
            findsOneWidget,
          );
      }

      // The navigation just collapsed the rail again; reopen it so the active
      // item can be read (and the next destination tapped) from an open rail.
      if (find.byType(AppSidebar).evaluate().isEmpty) {
        await tester.tap(find.byTooltip('Open navigation'));
        await tester.pumpAndSettle();
      }
      expect(
        sidebarIndex(tester),
        index,
        reason: '$label is the active branch',
      );
    }
  });

  testWidgets('active destination indication changes with navigation', (
    tester,
  ) async {
    await pumpAuthenticated(tester);

    await tester.tap(railLabel('Billing'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.billing);
    // Desktop collapses after navigation too; reopen to read the active item.
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'desktop rail collapses after navigation',
    );
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(
      sidebarIndex(tester),
      AppRoutes.branchIndexOf(AppRoutes.billing),
      reason: 'Billing is highlighted at its own branch position',
    );
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

    // The rail auto-collapsed; reopen it for the return tap.
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
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
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'desktop rail collapses after router navigation',
    );
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(
      sidebarIndex(tester),
      AppRoutes.branchIndexOf(AppRoutes.settings),
      reason: 'Settings is highlighted at its own branch position',
    );
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
        matching: find.text('JiggarTea Bill'),
      ),
      findsWidgets,
      reason: 'brand wordmark (and the default shop name) render in the rail',
    );
    expect(currentPath(tester), AppRoutes.settings);
  });

  testWidgets('phone bar shows Dashboard, Staff Management and Customers; '
      'Billing lives behind More', (tester) async {
    await pumpAuthenticated(tester);

    tester.view.physicalSize = const Size(320, 568);
    await tester.pumpAndSettle();

    final bar = find.byType(AppBottomNavigation);
    expect(bar, findsOneWidget);

    // Canonical feature names: the phone bar never renames a feature.
    expect(
      find.descendant(of: bar, matching: find.text('Dashboard')),
      findsOneWidget,
      reason: 'Dashboard is the first phone primary',
    );
    expect(
      find.descendant(of: bar, matching: find.text('Staff Management')),
      findsOneWidget,
      reason: 'Staff Management is a phone primary',
    );
    expect(
      find.descendant(of: bar, matching: find.text('Customers')),
      findsOneWidget,
      reason: 'Customers is a phone primary',
    );
    expect(find.text('More'), findsOneWidget, reason: 'More opens the sheet');

    // Billing/POS must NOT be a primary destination on the phone bar — it is
    // a secondary, reachable only through the More sheet.
    expect(
      find.descendant(of: bar, matching: find.text('Sales')),
      findsNothing,
      reason: 'Billing is not a direct phone nav destination',
    );
    expect(
      find.descendant(of: bar, matching: find.text('Billing')),
      findsNothing,
    );

    await tester.tap(
      find.descendant(
        of: bar,
        matching: find.byIcon(Icons.more_horiz_outlined),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Billing'), findsOneWidget, reason: 'Billing in More');
    expect(find.text('Settings'), findsOneWidget, reason: 'Settings in More');

    // Grouping, not hiding: Staff Management stays on the main bar, and the
    // three primaries plus the nine More tiles still cover all twelve
    // destinations.
    expect(find.text('Staff Management'), findsOneWidget);
    expect(
      find.byType(ListTile).evaluate().length,
      9,
      reason: 'nine secondary destinations sit behind More (3 + 9 = 12)',
    );
  });

  testWidgets('tablet rail auto-collapses after navigation and reopens via the '
      'floating toggle', (tester) async {
    await pumpAuthenticated(tester);

    // Tablet width: compact rail starts visible, no floating toggle yet.
    tester.view.physicalSize = const Size(700, 1024);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsNothing);

    // The FIRST navigation on a tablet collapses the rail so the opened page
    // (Billing/POS especially) expands to the full content width; sign-out
    // stays reachable beside the floating menu toggle.
    await tester.tap(find.byTooltip('Orders'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.orders);
    expect(find.byType(OrdersPage), findsOneWidget);
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'rail auto-collapses after a tablet navigation',
    );
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    expect(find.byTooltip('Sign out'), findsOneWidget);

    // The floating toggle reopens the rail for another navigation.
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget);

    // Navigating again collapses the rail again — Billing/POS keeps the width.
    await tester.tap(find.byTooltip('Billing'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.billing);
    expect(find.byType(PosPage), findsOneWidget);
    expect(find.byType(AppSidebar), findsNothing);
    expect(tester.takeException(), isNull);

    // The collapse contract is width-agnostic: resizing to wide desktop keeps
    // the rail hidden (shared state), and the floating toggle still restores
    // the extended rail.
    tester.view.physicalSize = const Size(1200, 2000);
    await tester.pumpAndSettle();
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'desktop keeps the collapsed rail across width changes',
    );
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tablet rail auto-collapses for content-internal navigation '
      '(dashboard header action)', (tester) async {
    await pumpAuthenticated(tester);
    tester.view.physicalSize = const Size(700, 1024);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byTooltip('Open navigation'), findsNothing);

    // The dashboard header notification bell navigates with context.go(),
    // not the rail's onDestinationSelected handler. The rail must still
    // auto-hide so the opened page reclaims the full tablet width.
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.inventory);
    expect(find.byType(InventoryPage), findsOneWidget);
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'rail auto-collapses for router/context navigation too',
    );
    expect(find.byTooltip('Open navigation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('collapsed tablet never overlaps page content with the floating '
      'toggle or sign-out controls', (tester) async {
    await pumpAuthenticated(tester);
    tester.view.physicalSize = const Size(700, 1024);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Orders'));
    await tester.pumpAndSettle();

    // The floating controls and the opened page header coexist on the same
    // row: the collapsed gutter (AppSpacing.ultra) must keep the header clear
    // of the rail-replacement column at the far left.
    final toggle = tester.getRect(find.byTooltip('Open navigation'));
    final signOutBox = tester.getRect(find.byTooltip('Sign out'));
    final subtitle = find.text('Review completed sales and receipts.');
    expect(subtitle, findsOneWidget);
    final headerBox = tester.getRect(subtitle);
    for (final box in [toggle, signOutBox]) {
      expect(
        box.right,
        lessThan(headerBox.left),
        reason: 'floating controls must stay clear of page headers',
      );
    }
  });

  testWidgets('collapsed-tablet POS keeps the vertical category rail and cart '
      'in view, with Frequently Sold selected by default', (tester) async {
    final now = DateTime.now().toUtc();
    final inventory = FakeInventoryRepository()
      ..storedCategories.addAll([
        Category(
          id: 'c-beverages',
          name: 'Beverages',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
        Category(
          id: 'c-snacks',
          name: 'Snacks',
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ])
      ..storedProducts.addAll([
        Product(
          id: 'p-chai',
          categoryId: 'c-beverages',
          name: 'Masala Chai',
          sku: null,
          sellingPricePaise: 12000,
          costPricePaise: null,
          stockQuantity: 50,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
        Product(
          id: 'p-cookie',
          categoryId: 'c-snacks',
          name: 'Butter Cookie',
          sku: null,
          sellingPricePaise: 5000,
          costPricePaise: null,
          stockQuantity: 40,
          isActive: true,
          createdAt: now,
          updatedAt: now,
        ),
      ]);
    await pumpAuthenticated(tester, inventory: inventory);
    tester.view.physicalSize = const Size(800, 1024);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Orders'));
    await tester.pumpAndSettle();
    // The first navigation collapsed the rail; reopen it to reach Billing.
    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Billing'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.billing);
    expect(find.byType(PosPage), findsOneWidget);
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'rail collapsed so the counter keeps the wide layout',
    );
    // Vertical rail with the default Frequently Sold pill selected first.
    final railPill = find.text('Frequently Sold');
    expect(railPill, findsOneWidget);
    expect(
      tester
          .widget<AppFilterChip>(
            find.ancestor(of: railPill, matching: find.byType(AppFilterChip)),
          )
          .selected,
      isTrue,
      reason: 'Frequently Sold is the default POS category on tablet',
    );
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Beverages'), findsOneWidget);
    expect(find.text('Snacks'), findsOneWidget);
    // The cart panel is pinned in view, not hidden behind the shelf.
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(find.text('Hold Bill'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar uses the Settings app display name, not a hardcoded '
      'brand', (tester) async {
    await pumpAuthenticated(tester);

    // Default settings render the default brand wordmark in the sidebar.
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('JiggarTea Bill'),
      ),
      findsWidgets,
      reason: 'brand wordmark (and the default shop name) render in the rail',
    );

    // A renamed display name from Settings replaces the wordmark — including
    // the table/desktop rail — with no hardcoded fallback text anywhere.
    final fake = FakeAuthRepository();
    final settings = FakeSettingsRepository()
      ..stored = const ShopSettings(
        shopName: 'Cafe Anna',
        appDisplayName: 'Anna POS',
      );
    await tester.pumpWidget(app(fake, settings: settings));
    fake.emit(_owner);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Anna POS'),
      ),
      findsOneWidget,
      reason: 'sidebar wordmark follows the Settings display name',
    );
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('Cafe Anna'),
      ),
      findsOneWidget,
      reason: 'active shop name renders under the wordmark',
    );
    expect(
      find.descendant(
        of: find.byType(AppSidebar),
        matching: find.text('JiggarTea Bill'),
      ),
      findsNothing,
      reason: 'sidebar must not fall back to a hardcoded brand',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('owner opens Daily Closing from the dashboard quick action '
      'with working back navigation', (tester) async {
    // Claimed ownership resolves the OWNER profile, which is what gates
    // the permission-protected quick-action card into view. The fake must
    // carry the user synchronously (emit() alone leaves currentUser null
    // and the profile never resolves).
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(_owner);
    // In-memory closing repository: the real file database never resolves
    // inside widget tests, which would leave the page's loaders spinning
    // forever (established fakes convention used by every other page test).
    final closingDb = db.AppDatabase(NativeDatabase.memory());
    addTearDown(closingDb.close);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 2000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      app(
        FakeAuthRepository(user: _owner),
        staff: staffRepo,
        closing: DriftDailyClosingRepository(closingDb),
      ),
    );
    await tester.pumpAndSettle();

    // The real owner path: tap the quick-action card (a widget tap, not a
    // router call).
    expect(find.text('Quick actions'), findsOneWidget);
    expect(find.text('New Sale'), findsOneWidget);
    expect(find.text('Daily Closing'), findsOneWidget);
    await tester.tap(find.text('Daily Closing'));
    await tester.pumpAndSettle();

    expect(currentPath(tester), AppRoutes.closing);
    expect(find.byType(DailyClosingPage), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The page-owned Back button returns to the dashboard.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(currentPath(tester), AppRoutes.dashboard);
    expect(find.byType(DashboardPage), findsOneWidget);
    // The pushed /closing trip collapsed the rail at desktop width; the shared
    // state must survive the shell remount so return lands collapsed too.
    expect(
      find.byType(AppSidebar),
      findsNothing,
      reason: 'rail stays collapsed across a pushed-page round trip',
    );
    expect(tester.takeException(), isNull);
  });
}
