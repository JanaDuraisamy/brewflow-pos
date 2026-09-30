import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/app/widgets/brand_mark.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
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
import 'package:brewflow_pos/features/staff/presentation/business_switcher_widget.dart';
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
/// Phone system-inset + responsive shell contract (Android 14 vs Android 16)
///
/// The two OS versions disagree about what the system bars report, and the
/// disagreement used to leak into layout. Android 14 hands the window a 24dp
/// status bar and no gesture strip; Android 15/16 force edge-to-edge and
/// report a larger bottom inset. The app then had three layers arguing over
/// that bottom inset — the Scaffold, a hand-rolled [SafeArea] and
/// [NavigationBar]'s own — which produced a dead strip under the bar on some
/// devices and a different header height on others, and no amount of overflow
/// testing would have caught either, because neither is an overflow.
///
/// So this suite varies the *insets themselves* as first-class inputs and
/// asserts the resolved geometry, measured from real rects:
///
///  - the bar's surface reaches the window edge and grows by exactly one inset,
///  - the body ends precisely where the bar begins (no gap, no overlap),
///  - the AppBar absorbs the top inset and the title/dropdown stay inside it,
///  - the page can actually reach its own end with the bar pinned above it.
///
/// Covering both inset pairs, both themes, both roles and every phone width is
/// what makes this a device-difference regression suite rather than a single
/// happy-path layout test.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');
const _staffUser = AuthUser(id: 'u2', email: 'staff@brewflow.example');

/// Every logical phone width below the 600dp rail breakpoint: small Android,
/// iPhone SE/mini, the two most common sizes, a Pro Max, a folded cover.
const _widths = <double>[360, 375, 390, 411, 430, 480];

const _phoneHeight = 800.0;

/// The two inset pairs the reported Android 14 vs Android 16 difference
/// produces. Both have a 24dp status bar; only the bottom strip differs, which
/// is exactly the dimension the phone layout has to get right.
const _insetCases = <(double, double)>[(24, 24), (24, 34)];

String _insets(double top, double bottom) =>
    'top ${top.toInt()}/bottom '
    '${bottom.toInt()}';

/// A staff grant wide enough to open the dashboard, so staff mode exercises the
/// same page as owner mode with the switcher removed.
const _staffGrants = {...defaultStaffPermissions, Permission.viewDashboard};

Widget _app(
  AuthUser user,
  FakeStaffRepository staff,
  ThemeMode mode,
) => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: user)),
    staffRepositoryProvider.overrideWithValue(staff),
    appThemeModeProvider.overrideWithValue(mode),
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
    offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
  ],
  child: const BrewFlowApp(),
);

/// Boots the authenticated phone shell at an explicit width, inset pair, theme
/// and role.
Future<void> _pumpShell(
  WidgetTester tester, {
  required double width,
  required double top,
  required double bottom,
  required bool owner,
  required bool dark,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, _phoneHeight);
  // padding drives SafeArea; viewPadding stays equal to it so the window reads
  // as the edge-to-edge case Android 15/16 always reports.
  tester.view.padding = FakeViewPadding(top: top, bottom: bottom);
  tester.view.viewPadding = FakeViewPadding(top: top, bottom: bottom);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final staff = FakeStaffRepository();
  await staff.claimOwnership(_owner);
  if (!owner) {
    await staff.createStaffProfile(
      identity: _staffUser,
      shopId: 'shop-1',
      permissions: _staffGrants,
    );
  }
  await tester.pumpWidget(
    _app(
      owner ? _owner : _staffUser,
      staff,
      dark ? ThemeMode.dark : ThemeMode.light,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _bar() => find.byType(NavigationBar);

/// The dashboard's own page scroll view — a single [ListView] of sections.
Finder _pageList() => find.descendant(
  of: find.byType(DashboardPage),
  matching: find.byType(ListView),
);

Finder _pageScroll() => find
    .descendant(
      of: find.byType(DashboardPage),
      matching: find.byType(Scrollable),
    )
    .first;

/// Rects for every element a finder matches, in tree order.
List<Rect> _rectsOf(WidgetTester tester, Finder finder) => [
  for (final element in tester.elementList(finder))
    (element.renderObject! as RenderBox).localToGlobal(Offset.zero) &
        (element.renderObject! as RenderBox).size,
];

/// Drags the page to its end the way a finger would and stops when the offset
/// stops advancing.
///
/// [ScrollPosition.maxScrollExtent] is only an estimate while a lazily measured
/// list is still being built, so a single `jumpTo` lands short and asserting
/// `pixels == maxScrollExtent` against the first value read is unsound. Dragging
/// until the offset converges is both stable and the behaviour that matters.
Future<double> _settleToEnd(WidgetTester tester, Finder scroll) async {
  final position = tester.state<ScrollableState>(scroll).position;
  var previous = -1.0;
  for (var i = 0; i < 40; i++) {
    await tester.drag(scroll, const Offset(0, -240));
    await tester.pumpAndSettle();
    if (position.pixels <= previous + 0.5) break;
    previous = position.pixels;
  }
  await tester.pumpAndSettle();
  return position.maxScrollExtent;
}

/// Depth-first collection of every laid-out [RenderBox] in a subtree, in global
/// coordinates. Used to measure what the page actually paints rather than
/// trusting a widget's name.
void _collectRects(RenderObject node, List<Rect> out) {
  if (node is RenderBox && node.hasSize && !node.size.isEmpty) {
    out.add(node.localToGlobal(Offset.zero) & node.size);
  }
  node.visitChildren((child) => _collectRects(child, out));
}

void main() {
  // -------------------------------------------------------------------------
  // 1. Core shell geometry across the full width x inset x theme x role matrix.
  // -------------------------------------------------------------------------
  for (final width in _widths) {
    for (final (top, bottom) in _insetCases) {
      for (final dark in [false, true]) {
        for (final owner in [true, false]) {
          final w = width.toInt();
          final theme = dark ? 'dark' : 'light';
          final role = owner ? 'owner' : 'staff';
          final ctx = '$role/${w}dp/${_insets(top, bottom)}/$theme';

          testWidgets('$ctx shell is well-formed', (tester) async {
            await _pumpShell(
              tester,
              width: width,
              top: top,
              bottom: bottom,
              owner: owner,
              dark: dark,
            );

            // A RenderFlex overflow surfaces as a FlutterError; asserting it
            // explicitly makes a failure name the real cause.
            expect(
              tester.takeException(),
              isNull,
              reason: 'no layout exception at $ctx',
            );

            expect(find.byType(AppShell), findsOneWidget, reason: ctx);
            expect(find.byType(DashboardPage), findsOneWidget, reason: ctx);
            expect(
              find.byType(AppSidebar),
              findsNothing,
              reason: '$w dp is under the 600dp rail breakpoint at $ctx',
            );

            final window = tester.getRect(find.byType(AppShell));
            final bar = tester.getRect(_bar());

            // --- NavigationBar is visible and owns the bottom inset once ---
            expect(
              bar.height,
              moreOrLessEquals(AppSpacing.ultra + bottom),
              reason:
                  'bar is 64dp plus exactly ONE ${bottom.toInt()}dp inset at '
                  '$ctx; a doubled SafeArea would be '
                  '${2 * bottom}dp',
            );
            expect(
              bar.bottom,
              moreOrLessEquals(window.bottom),
              reason:
                  'the bar surface covers the inset to the window edge at '
                  '$ctx',
            );
            expect(bar.width, moreOrLessEquals(width), reason: ctx);

            // --- The page body ends exactly where the bar begins ---
            // No dead strip of Scaffold background, and no overlap either.
            final body = tester.getRect(_pageList());
            expect(
              body.bottom,
              moreOrLessEquals(bar.top),
              reason:
                  'the body must fill up to the bar at $ctx '
                  '(body ${body.bottom}, bar ${bar.top})',
            );
            expect(
              body.width,
              moreOrLessEquals(width),
              reason: 'the page spans the window width at $ctx',
            );

            // --- AppBar absorbs the top inset; the body never sees it ---
            final appBar = tester.getRect(find.byType(AppBar));
            final appBarWidget = tester.widget<AppBar>(find.byType(AppBar));
            expect(
              appBar.top,
              0,
              reason: 'the AppBar owns the status-bar inset at $ctx',
            );
            expect(
              appBar.height,
              moreOrLessEquals(appBarWidget.preferredSize.height + top),
              reason:
                  'the top inset is added to the app bar, not above the '
                  'body, at $ctx',
            );

            // --- No horizontal overflow anywhere in the chrome ---
            // Header content and bar actions both have to stay in the window.
            for (final rect in [
              ..._rectsOf(
                tester,
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(BrandMark),
                ),
              ),
              ..._rectsOf(
                tester,
                find.descendant(
                  of: find.byType(AppBar),
                  matching: find.byType(Text),
                ),
              ),
            ]) {
              expect(rect.left, greaterThanOrEqualTo(-0.01), reason: ctx);
              expect(
                rect.right,
                lessThanOrEqualTo(width + 0.01),
                reason:
                    'header text ${rect.left}..${rect.right} escapes the '
                    '${width}dp window at $ctx',
              );
            }

            // --- Title and switcher are never clipped ---
            // The band is the app bar minus the inset it consumes; the title
            // stack and the switcher must live entirely inside it.
            final band = Rect.fromLTRB(
              appBar.left,
              appBar.top + top,
              appBar.right,
              appBar.bottom,
            );

            final brand = find.descendant(
              of: find.byType(AppBar),
              matching: find.byType(BrandMark),
            );
            expect(brand, findsOneWidget, reason: ctx);
            final titleStack = find
                .descendant(
                  of: find
                      .ancestor(of: brand, matching: find.byType(Row))
                      .first,
                  matching: find.byType(Column),
                )
                .first;
            final titleRect = tester.getRect(titleStack);
            expect(
              titleRect.top,
              greaterThanOrEqualTo(band.top - 0.01),
              reason: 'title clipped above the toolbar at $ctx',
            );
            expect(
              titleRect.bottom,
              lessThanOrEqualTo(band.bottom + 0.01),
              reason: 'title clipped below the toolbar at $ctx',
            );

            final switcher = find.byType(BusinessSwitcher);
            if (owner) {
              expect(
                switcher,
                findsOneWidget,
                reason: 'the owner header shows the business switcher at $ctx',
              );
              final rect = tester.getRect(switcher);
              expect(
                rect.height,
                moreOrLessEquals(40),
                reason: 'the switcher is a fixed 40dp control at $ctx',
              );
              expect(
                rect.top,
                greaterThanOrEqualTo(band.top - 0.01),
                reason: 'the switcher is clipped at the top of $ctx',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(band.bottom + 0.01),
                reason:
                    'the switcher is clipped at the bottom of $ctx '
                    '(switcher ${rect.bottom}, toolbar ${band.bottom})',
              );
              // Width comes from the title column, so it must fit inside it
              // and inside the window — never a hardcoded number.
              expect(
                rect.right,
                lessThanOrEqualTo(titleRect.right + 0.01),
                reason: 'the switcher overflows the title column at $ctx',
              );
              expect(
                rect.right,
                lessThanOrEqualTo(width + 0.01),
                reason: 'the switcher overflows the window at $ctx',
              );
            } else {
              expect(
                switcher,
                findsNothing,
                reason:
                    'staff headers never show the business switcher at '
                    '$ctx',
              );
            }
          });
        }
      }
    }
  }

  // -------------------------------------------------------------------------
  // 2. The dashboard reaches its own end, with the bar pinned above it.
  // -------------------------------------------------------------------------
  for (final width in _widths) {
    for (final (top, bottom) in _insetCases) {
      final w = width.toInt();
      final ctx = '${w}dp/${_insets(top, bottom)}';
      testWidgets('dashboard at $ctx reaches its last content above the bar', (
        tester,
      ) async {
        await _pumpShell(
          tester,
          width: width,
          top: top,
          bottom: bottom,
          owner: true,
          dark: false,
        );

        // --- The bar is outside the page's scroll subtree ---
        expect(
          find.ancestor(
            of: find.byType(AppBottomNavigation),
            matching: find.byType(DashboardPage),
          ),
          findsNothing,
          reason: 'the bar must never live inside the scrollable page at $ctx',
        );
        expect(
          find.descendant(of: _pageList(), matching: _bar()),
          findsNothing,
          reason: 'the page body does not contain the bar at $ctx',
        );
        final scaffold = tester.widget<Scaffold>(
          find
              .ancestor(
                of: find.byType(AppBottomNavigation),
                matching: find.byType(Scaffold),
              )
              .first,
        );
        expect(
          scaffold.bottomNavigationBar,
          isA<AppBottomNavigation>(),
          reason: 'the bar is a Scaffold slot at $ctx',
        );

        // --- There is genuinely enough content to scroll ---
        final scroll = _pageScroll();
        final position = tester.state<ScrollableState>(scroll).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'the dashboard must overflow the viewport at $ctx',
        );

        final barBefore = tester.getRect(_bar());

        // --- It reaches the end, and the bar never moved ---
        final settledMax = await _settleToEnd(tester, scroll);
        expect(
          tester.takeException(),
          isNull,
          reason: 'scrolling to the end is exception free at $ctx',
        );
        expect(
          position.pixels,
          moreOrLessEquals(settledMax, epsilon: 1.0),
          reason:
              'the dashboard must settle on its own maxScrollExtent at $ctx '
              '(pixels ${position.pixels}, max $settledMax)',
        );
        expect(
          tester.getRect(_bar()),
          barBefore,
          reason: 'the bar is pinned while the page scrolls beneath it at $ctx',
        );

        // --- The last content is visible, not behind the bar ---
        // The final dashboard section is a private widget, so rather than
        // naming it, measure every box actually painted inside the page
        // viewport: nothing may extend below the viewport's own bottom edge,
        // and the viewport's bottom edge is the top of the bar. This catches
        // content sliding under the bar whatever the section happens to be
        // called.
        final barRect = tester.getRect(_bar());
        final pageRect = tester.getRect(_pageList());
        final painted = <Rect>[];
        _collectRects(_pageList().evaluate().single.renderObject!, painted);

        final visible = [
          for (final rect in painted)
            if (rect.height > 0 &&
                rect.bottom > pageRect.top &&
                rect.top < pageRect.bottom)
              rect,
        ];
        expect(
          visible,
          isNotEmpty,
          reason: 'the page must paint content at $ctx',
        );

        final lowest = visible
            .map((rect) => rect.bottom)
            .reduce((a, b) => a > b ? a : b);
        expect(
          lowest,
          lessThanOrEqualTo(pageRect.bottom + 0.5),
          reason:
              'dashboard content is painted below the page viewport at $ctx '
              '(lowest $lowest, viewport bottom ${pageRect.bottom})',
        );
        expect(
          pageRect.bottom,
          moreOrLessEquals(barRect.top),
          reason:
              'the page viewport must end at the bar, so no content can be '
              'hidden behind it at $ctx',
        );
      });
    }
  }

  // -------------------------------------------------------------------------
  // 3. Width must not restructure navigation.
  // -------------------------------------------------------------------------
  testWidgets('the phone bar keeps one structure across every phone width', (
    tester,
  ) async {
    // Pump once, then change only the width. Re-pumping the whole app would
    // re-run bootstrap storage init, and mutating the view is a truer model of
    // "the same app on a wider phone" anyway.
    await _pumpShell(
      tester,
      width: _widths.first,
      top: 24,
      bottom: 34,
      owner: true,
      dark: false,
    );

    String? baseline;
    final heights = <double>{};

    for (final width in _widths) {
      tester.view.physicalSize = Size(width, _phoneHeight);
      await tester.pumpAndSettle();

      final bar = find.byType(AppBottomNavigation);
      expect(bar, findsOneWidget, reason: '${width}dp must render the bar');

      // The rendered destinations, in order, as a single comparable string.
      final labels = [
        for (final destination
            in tester.widget<NavigationBar>(_bar()).destinations)
          (destination as NavigationDestination).label,
      ];
      final structure = labels.join('|');
      baseline ??= structure;

      expect(
        structure,
        baseline,
        reason:
            'the destination list must not change with width '
            '(at ${width.toInt()}dp saw "$structure", expected "$baseline")',
      );
      expect(find.byType(AppSidebar), findsNothing, reason: '${width}dp');

      // The bar is always 64dp tall regardless of width, and always flush to
      // the window edge, so widening the phone adds room rather than height.
      final rect = tester.getRect(bar);
      expect(
        rect.height,
        moreOrLessEquals(AppSpacing.ultra + 34),
        reason: 'bar height must not drift with width at ${width}dp',
      );
      expect(
        rect.bottom,
        moreOrLessEquals(tester.getRect(find.byType(AppShell)).bottom),
        reason: 'the bar stays flush at ${width}dp',
      );
      expect(
        rect.width,
        moreOrLessEquals(width),
        reason: 'the bar spans the whole window at ${width}dp',
      );
      heights.add(rect.height);

      // No width is a special case for overflow.
      expect(
        tester.takeException(),
        isNull,
        reason: 'no layout exception at ${width}dp',
      );
    }

    // Same bar height everywhere: only the width axis is allowed to change.
    expect(
      heights,
      hasLength(1),
      reason: 'the bar height must be identical at every width, saw $heights',
    );
  });

  // -------------------------------------------------------------------------
  // 4. A larger reported bottom inset must add space exactly once.
  // -------------------------------------------------------------------------
  testWidgets('a bigger bottom inset adds one inset of spacing, not two', (
    tester,
  ) async {
    const width = 390.0;
    const top = 24.0;
    const small = 24.0;
    const large = 34.0;

    await _pumpShell(
      tester,
      width: width,
      top: top,
      bottom: small,
      owner: true,
      dark: false,
    );
    expect(
      tester.takeException(),
      isNull,
      reason: 'no layout exception at bottom ${small.toInt()}dp',
    );
    final smallBar = tester.getRect(_bar());
    final smallBody = tester.getRect(_pageList());
    final smallAppBar = tester.getRect(find.byType(AppBar));

    // The same live tree, a device that reports the larger gesture strip.
    tester.view.padding = const FakeViewPadding(top: top, bottom: large);
    tester.view.viewPadding = const FakeViewPadding(top: top, bottom: large);
    await tester.pumpAndSettle();
    expect(
      tester.takeException(),
      isNull,
      reason: 'no layout exception at bottom ${large.toInt()}dp',
    );
    final largeBar = tester.getRect(_bar());
    final largeBody = tester.getRect(_pageList());
    final largeAppBar = tester.getRect(find.byType(AppBar));

    final delta = large - small;
    final ctx = 'insets ${small.toInt()} vs ${large.toInt()}';

    // The bar grows by exactly the inset difference. Two SafeAreas would make
    // it grow by twice that.
    expect(
      largeBar.height - smallBar.height,
      moreOrLessEquals(delta),
      reason:
          'a ${delta.toInt()}dp bigger inset must add ${delta.toInt()}dp to the '
          'bar, not ${2 * delta}dp',
    );
    // Still flush to the window edge, and the app bar is untouched by a bottom
    // inset change.
    expect(
      largeBar.bottom,
      moreOrLessEquals(smallBar.bottom),
      reason: 'the bar stays flush to the window edge at $ctx',
    );
    expect(
      largeAppBar.height,
      moreOrLessEquals(smallAppBar.height),
      reason: 'the bottom inset must not disturb the app bar at $ctx',
    );
    expect(largeAppBar.top, smallAppBar.top, reason: ctx);
    // The body yields exactly the space the bar took, so there is never a
    // dead strip between them.
    expect(
      smallBody.bottom,
      moreOrLessEquals(smallBar.top),
      reason: 'no gap at ${small.toInt()}dp',
    );
    expect(
      largeBody.bottom,
      moreOrLessEquals(largeBar.top),
      reason: 'no gap at ${large.toInt()}dp',
    );
    expect(
      smallBody.height - largeBody.height,
      moreOrLessEquals(delta),
      reason: 'the body must give back exactly what the bar took at $ctx',
    );
    expect(
      largeBody.height,
      greaterThan(0),
      reason: 'the body must keep usable height at ${large.toInt()}dp',
    );
  });
}
