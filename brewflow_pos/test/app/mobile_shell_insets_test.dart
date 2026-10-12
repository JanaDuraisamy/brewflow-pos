import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/app/widgets/connectivity_banner.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// ---------------------------------------------------------------------------
/// Mobile shell system-inset contract
///
/// The phone layout is the one place where three layers used to fight over the
/// bottom inset — the Scaffold body [SafeArea], a hand-rolled [SafeArea] around
/// the bar, and [NavigationBar]'s own built-in one. Under Android 15/16
/// edge-to-edge that produced a dead strip of Scaffold background below the
/// navigation bar whose size depended on the device.
///
/// These tests pin the corrected ownership: the Scaffold reserves the inset
/// once, the bar's own surface covers it down to the window edge, and the page
/// body ends exactly where the bar begins.
///
/// Geometry is asserted directly rather than through [WidgetTester
/// .takeException] alone: an overflow or a wrong inset is a *layout* fact, and
/// a passing test that never measures a rect cannot tell the two layouts apart.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// Real phone widths, narrowest to widest: a small Android, the two most common
/// sizes, a Pro Max and a large folded cover. All sit under the 600dp rail
/// breakpoint, so every one of them must render the bottom bar.
const _phoneWidths = <double>[360, 390, 411, 430, 480];

/// Tall enough that the dashboard is always scrollable at every phone width.
const _phoneHeight = 800.0;

/// A notch plus a gesture bar: the non-zero top AND bottom inset combination
/// that Android 15/16 edge-to-edge always reports.
const _topInset = 44.0;
const _bottomInset = 34.0;

Widget _app(FakeAuthRepository fake) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(fake),
    inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
    billingRepositoryProvider.overrideWithValue(
      FakeBillingRepository(FakeInventoryRepository()),
    ),
    ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
    customerLedgerRepositoryProvider.overrideWithValue(
      FakeCustomerLedgerRepository(),
    ),
    settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
    customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
    suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
    purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
    expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
    staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
    offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
  ],
  child: const BrewFlowApp(),
);

/// Boots the authenticated shell on a phone viewport with real system insets.
Future<FakeAuthRepository> _pumpPhoneShell(
  WidgetTester tester, {
  required double width,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, _phoneHeight);
  // padding drives SafeArea; viewPadding keeps MediaQuery realistic for an
  // edge-to-edge window where the system bars overlap the app.
  tester.view.padding = const FakeViewPadding(
    top: _topInset,
    bottom: _bottomInset,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: _topInset,
    bottom: _bottomInset,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final fake = FakeAuthRepository();
  await tester.pumpWidget(_app(fake));
  fake.emit(_owner);
  await tester.pumpAndSettle();
  return fake;
}

/// The Scaffold that actually hosts the bottom bar (not merely any ancestor).
Finder _hostScaffold() => find.ancestor(
  of: find.byType(AppBottomNavigation),
  matching: find.byType(Scaffold),
);

/// The dashboard's own page scroll view. The dashboard is a single [ListView]
/// of sections, so this is unambiguous.
Finder _dashboardList() => find.descendant(
  of: find.byType(DashboardPage),
  matching: find.byType(ListView),
);

/// The outermost scrollable inside the dashboard — pre-order traversal reaches
/// the page ListView before any of the nested grid scroll views.
Finder _dashboardScroll() => find
    .descendant(
      of: find.byType(DashboardPage),
      matching: find.byType(Scrollable),
    )
    .first;

void main() {
  for (final width in _phoneWidths) {
    final label = '${width.toInt()}dp';

    testWidgets('phone shell at $label renders the bottom bar flush to the '
        'window edge with the inset applied exactly once', (tester) async {
      await _pumpPhoneShell(tester, width: width);

      expect(tester.takeException(), isNull, reason: 'no overflow at $label');
      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(
        find.byType(AppSidebar),
        findsNothing,
        reason: '$label is below the rail breakpoint, so no sidebar',
      );
      expect(find.byType(NavigationBar), findsOneWidget);

      final bar = tester.getRect(find.byType(NavigationBar));
      final window = tester.getRect(find.byType(AppShell));

      // The bar's surface owns the bottom inset. This is the assertion the old
      // layout could not pass: it left a strip of bare Scaffold background
      // between the bar and the window edge, sized by whatever the device
      // reported.
      expect(
        bar.bottom,
        moreOrLessEquals(window.bottom),
        reason: 'the bar surface reaches the window edge, covering the inset',
      );
      expect(
        bar.top,
        moreOrLessEquals(window.bottom - AppSpacing.ultra - _bottomInset),
        reason: 'bar is AppSpacing.ultra plus ONE bottom inset, not two',
      );
      expect(
        bar.height,
        moreOrLessEquals(AppSpacing.ultra + _bottomInset),
        reason: 'a doubled SafeArea would make this 2x the inset',
      );
      expect(
        bar.width,
        moreOrLessEquals(width),
        reason: 'the bar spans the full window width',
      );

      // The top inset is owned by the AppBar, so the body never sees it.
      final appBarRect = tester.getRect(find.byType(AppBar));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBarRect.top, 0, reason: 'the AppBar absorbs the top inset');
      expect(
        appBarRect.height,
        moreOrLessEquals(appBar.preferredSize.height + _topInset),
        reason: 'the top inset is added to the app bar, not above the body',
      );
    });

    testWidgets('phone shell at $label keeps the bottom bar out of the '
        'scrollable page body', (tester) async {
      await _pumpPhoneShell(tester, width: width);

      // Structural: the bar is a Scaffold slot, not a descendant of the page.
      final scaffold = tester.widget<Scaffold>(_hostScaffold());
      expect(
        scaffold.bottomNavigationBar,
        isA<AppBottomNavigation>(),
        reason: 'the bar is handed to Scaffold.bottomNavigationBar',
      );
      expect(
        find.ancestor(
          of: find.byType(AppBottomNavigation),
          matching: find.byType(DashboardPage),
        ),
        findsNothing,
        reason: 'the bar must never live inside the scrollable page',
      );
      expect(
        find.descendant(
          of: _dashboardList(),
          matching: find.byType(NavigationBar),
        ),
        findsNothing,
        reason: 'the page body does not contain the bar',
      );

      // Geometric: the page ends exactly where the bar starts — no overlap and
      // no dead gap — so the body is not short by the inset either.
      final list = tester.getRect(_dashboardList());
      final bar = tester.getRect(find.byType(NavigationBar));
      expect(
        list.bottom,
        moreOrLessEquals(bar.top),
        reason: 'the body fills up to the bar with nothing hidden behind it',
      );
      expect(list.bottom, lessThanOrEqualTo(bar.top));

      // Scrolling the page must not move the bar, which is only true if the
      // bar sits outside the scrollable subtree.
      final scroll = _dashboardScroll();
      final state = tester.state<ScrollableState>(scroll);
      expect(
        state.position.maxScrollExtent,
        greaterThan(0),
        reason: 'the dashboard is taller than the phone viewport',
      );
      final barBefore = bar;
      await tester.drag(scroll, const Offset(0, -250));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason:
            'scrolling is exception '
            'free at $label',
      );
      expect(
        state.position.pixels,
        greaterThan(0),
        reason: 'the dashboard still scrolls after the shell restructure',
      );
      expect(
        tester.getRect(find.byType(NavigationBar)),
        barBefore,
        reason: 'the bar is pinned while the page scrolls beneath it',
      );
    });
  }

  testWidgets('phone bar is a compact 64dp NavigationBar with always-visible '
      'labels and no outer SafeArea', (tester) async {
    await _pumpPhoneShell(tester, width: 390);

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(
      navBar.height,
      moreOrLessEquals(AppSpacing.ultra),
      reason: 'the phone bar is AppSpacing.ultra (64dp), not the tight 56dp',
    );
    expect(
      navBar.labelBehavior,
      NavigationDestinationLabelBehavior.alwaysShow,
      reason: 'labels are always rendered, so the bar needs the taller height',
    );

    // NavigationBar supplies its own SafeArea(top: false). A second wrapper
    // between the DecoratedBox and the bar is the regression this locks out.
    expect(
      find.ancestor(
        of: find.byType(NavigationBar),
        matching: find.byType(SafeArea),
      ),
      findsNothing,
      reason: 'the bar must not be wrapped in another SafeArea',
    );

    // The DecoratedBox is what keeps the surface, border and shadow spanning
    // the inset region, so it must sit between the bar and the shell.
    expect(
      find.ancestor(
        of: find.byType(NavigationBar),
        matching: find.byType(DecoratedBox),
      ),
      findsWidgets,
    );
    expect(
      tester.getRect(find.byType(AppBottomNavigation)).bottom,
      moreOrLessEquals(tester.getRect(find.byType(AppShell)).bottom),
      reason: 'the decorated surface covers the inset, not just the bar height',
    );
  });

  testWidgets('phone bar keeps its destinations and selection on the Scaffold '
      'slot', (tester) async {
    await _pumpPhoneShell(tester, width: 411);

    final bar = find.byType(AppBottomNavigation);
    expect(bar, findsOneWidget);

    // The three primaries plus More, unchanged by the restructure.
    for (final label in ['Dashboard', 'Staff Management', 'Customers']) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
        reason: '$label is still a direct phone destination',
      );
    }
    expect(
      find.descendant(of: bar, matching: find.text('More')),
      findsOneWidget,
      reason: 'the More sheet is still reachable from the bar',
    );

    // The connectivity banner is still a body sibling above the page, not
    // swallowed into it and not pushed into the bar slot.
    expect(find.byType(ConnectivityBanner), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(ConnectivityBanner),
        matching: find.byType(DashboardPage),
      ),
      findsNothing,
      reason: 'the banner sits above the page, inside the body column',
    );

    // Tapping a destination still navigates: moving the bar to the Scaffold
    // slot must not break the selection logic.
    await tester.tap(
      find.descendant(of: bar, matching: find.text('Customers')),
    );
    await tester.pumpAndSettle();

    final context = tester.element(find.byType(AppShell));
    final router = ProviderScope.containerOf(context).read(appRouterProvider);
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.customers);
    expect(find.byType(DashboardPage), findsNothing);
    expect(
      tester.getRect(find.byType(NavigationBar)).bottom,
      moreOrLessEquals(tester.getRect(find.byType(AppShell)).bottom),
      reason: 'the bar stays flush after a branch switch too',
    );
  });
}
