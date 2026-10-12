import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/widgets/brand_mark.dart';
import 'package:brewflow_pos/app/widgets/sync_status_indicator.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
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
/// Mobile AppBar determinism contract
///
/// The phone header used to take its height from whatever the title happened to
/// measure: two single-line texts plus a [DropdownButton], whose height follows
/// the resolved font metrics. [AppBar] sizes itself from that toolbar child, so
/// the header — and the room the Scaffold reserved for it — shifted with the
/// device's font and layout, which is exactly the variance that shows up when
/// the same build runs on Android 14, 15 and 16.
///
/// These tests pin the fixed numbers instead: the app bar is always
/// `statusBarInset + preferredSize`, the title stack is always the same height,
/// and the switcher is always the same control height — in both themes, for both
/// roles, at every phone width. Everything is asserted from measured rects, so a
/// regression shows up as a geometry failure rather than a vague overflow.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');
const _staffUser = AuthUser(id: 'u2', email: 'staff@brewflow.example');

/// Real phone widths: small Android, iPhone SE/mini, the two most common sizes,
/// a Pro Max and a large folded cover. All below the 600dp rail breakpoint.
const _widths = <double>[360, 375, 390, 411, 430, 480];

const _viewportHeight = 800.0;
const _statusBarInset = 44.0;
const _gestureInset = 34.0;

/// Owner header: app name + shop name + switcher. 112dp is fixed by design.
const _ownerPreferredHeight = 112.0;
const _ownerTitleHeight = 84.0;

/// Staff header: app name + shop name only.
const _compactPreferredHeight = 64.0;
const _compactTitleHeight = 40.0;

/// The switcher control's own height, border included.
const _switcherHeight = 40.0;

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

/// Boots the authenticated shell on a phone viewport with real system insets.
/// Owner sessions get the switcher; a staff session resolves a staff profile so
/// the header renders without it.
Future<void> _pumpHeader(
  WidgetTester tester, {
  required double width,
  required bool owner,
  required bool dark,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, _viewportHeight);
  tester.view.padding = const FakeViewPadding(
    top: _statusBarInset,
    bottom: _gestureInset,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: _statusBarInset,
    bottom: _gestureInset,
  );
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  final staff = FakeStaffRepository();
  await staff.claimOwnership(_owner);
  if (!owner) {
    await staff.createStaffProfile(
      identity: _staffUser,
      shopId: 'shop-1',
      permissions: defaultStaffPermissions,
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
  expect(find.byType(AppShell), findsOneWidget);
}

/// The app bar's brand mark. Scoped to the [AppBar] because the dashboard body
/// renders one too.
Finder _brandMark() =>
    find.descendant(of: find.byType(AppBar), matching: find.byType(BrandMark));

/// The title stack: the [Column] holding the app name, the shop name and the
/// switcher.
///
/// Anchored structurally on the brand mark's row, not on a rendered string: the
/// app name and the shop name are deliberately the same text
/// (`AppConstants.appName` is the app display name), so a string finder matches
/// both lines and cannot tell them apart.
Finder _titleStack() {
  final brand = _brandMark();
  expect(brand, findsOneWidget, reason: 'the header shows the brand mark');
  final row = find.ancestor(of: brand, matching: find.byType(Row));
  return find.descendant(of: row.first, matching: find.byType(Column)).first;
}

/// Every text line drawn inside the title stack, in tree order. Used for
/// geometry only — see [_headerLines] to identify the two header lines.
Finder _titleTexts() =>
    find.descendant(of: _titleStack(), matching: find.byType(Text));

/// Rects for every element a finder matches, in tree order.
///
/// [WidgetTester.getRect] only accepts a single hit, and the header's text
/// finder is expected to match several; this walks the hits one by one so each
/// is measured against the same contract instead of only the first.
List<Rect> _rectsOf(WidgetTester tester, Finder finder) => [
  for (final element in tester.elementList(finder))
    (element.renderObject! as RenderBox).localToGlobal(Offset.zero) &
        (element.renderObject! as RenderBox).size,
];

/// The app name and the shop name: the title stack's own direct [Text] children.
/// Counting them structurally is what proves both lines are still rendered, and
/// a missing line shows up as a count, not as an ambiguous text lookup.
List<Text> _headerLines(WidgetTester tester) =>
    tester.widget<Column>(_titleStack()).children.whereType<Text>().toList();

/// The app bar minus the status-bar inset it consumes: the band the title and
/// the actions must live inside.
Rect _toolbarBand(Rect appBar) => Rect.fromLTRB(
  appBar.left,
  appBar.top + _statusBarInset,
  appBar.right,
  appBar.bottom,
);

String _inside(Rect band, Rect child) =>
    'child ${child.top}..${child.bottom} must sit inside toolbar '
    '${band.top}..${band.bottom}';

void main() {
  for (final width in _widths) {
    for (final dark in [false, true]) {
      for (final owner in [true, false]) {
        final role = owner ? 'owner' : 'staff';
        final theme = dark ? 'dark' : 'light';
        final expectedPreferred = owner
            ? _ownerPreferredHeight
            : _compactPreferredHeight;
        final expectedTitle = owner ? _ownerTitleHeight : _compactTitleHeight;

        testWidgets(
          '$role header at ${width.toInt()}dp in $theme is deterministic and '
          'does not clip',
          (tester) async {
            await _pumpHeader(tester, width: width, owner: owner, dark: dark);
            final context = '$role/${width.toInt()}/$theme';

            // No overflow: a RenderFlex overflow surfaces as a FlutterError,
            // which fails the test outright; asserted explicitly so a failure
            // names the cause.
            expect(
              tester.takeException(),
              isNull,
              reason: 'no layout exception at $context',
            );

            // --- App bar height is a fixed constant, not a content result ---
            final appBar = tester.getRect(find.byType(AppBar));
            expect(
              appBar.height,
              moreOrLessEquals(_statusBarInset + expectedPreferred),
              reason:
                  'app bar must be statusBarInset + preferredSize at $context',
            );
            expect(
              appBar.top,
              0,
              reason: 'the app bar owns the status-bar inset at $context',
            );
            final band = _toolbarBand(appBar);

            // --- Title stack has a deterministic height ---
            final title = tester.getRect(_titleStack());
            expect(
              title.height,
              moreOrLessEquals(expectedTitle),
              reason: 'title stack height is fixed at $context',
            );
            expect(
              title.top,
              greaterThanOrEqualTo(band.top),
              reason: _inside(band, title),
            );
            expect(
              title.bottom,
              lessThanOrEqualTo(band.bottom),
              reason: _inside(band, title),
            );

            // --- Brand mark, app name and shop name stay inside the band ---
            final brand = tester.getRect(_brandMark());
            expect(brand.top, greaterThanOrEqualTo(band.top), reason: context);
            expect(
              brand.bottom,
              lessThanOrEqualTo(band.bottom),
              reason: context,
            );

            // Both header lines are still rendered, each single-line with an
            // ellipsis so a long shop name truncates instead of wrapping or
            // being cut mid-glyph.
            final lines = _headerLines(tester);
            expect(
              lines,
              hasLength(2),
              reason: 'app name + shop name are both present at $context',
            );
            for (final line in lines) {
              expect(line.maxLines, 1, reason: context);
              expect(line.overflow, TextOverflow.ellipsis, reason: context);
            }

            // Every line drawn in the header — the two names plus the switcher's
            // current selection — stays inside the toolbar band and the window.
            for (final rect in _rectsOf(tester, _titleTexts())) {
              expect(
                rect.top,
                greaterThanOrEqualTo(band.top),
                reason:
                    'header text ${rect.top}..${rect.bottom} inside toolbar at '
                    '$context',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(band.bottom),
                reason:
                    'header text ${rect.top}..${rect.bottom} inside toolbar at '
                    '$context',
              );
              expect(rect.left, greaterThanOrEqualTo(0), reason: context);
              expect(
                rect.right,
                lessThanOrEqualTo(width + 0.01),
                reason: 'header text stays inside the window at $context',
              );
            }

            // --- Switcher: owner only, fixed control height, fully visible ---
            final switcher = find.byType(BusinessSwitcher);
            if (owner) {
              expect(switcher, findsOneWidget, reason: context);
              final rect = tester.getRect(switcher);
              expect(
                rect.height,
                moreOrLessEquals(_switcherHeight),
                reason: 'the switcher control is a fixed 40dp at $context',
              );
              expect(
                rect.top,
                greaterThanOrEqualTo(band.top),
                reason: 'switcher fully visible at $context',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(band.bottom),
                reason: _inside(band, rect),
              );
              // Width comes from the title column, never a hardcoded number.
              expect(
                rect.width,
                greaterThan(0),
                reason: 'the switcher is not collapsed at $context',
              );
              expect(
                rect.right,
                lessThanOrEqualTo(title.right + 0.01),
                reason:
                    'the switcher stays inside the title column at $context',
              );
              // The current selection is rendered inside the control, so the
              // header is never a bare arrow with no label. All three contexts
              // are covered by the menu test below.
              expect(
                _rectsOf(tester, _titleTexts()).length,
                greaterThanOrEqualTo(3),
                reason: 'the switcher renders its selected label at $context',
              );
            } else {
              expect(
                switcher,
                findsNothing,
                reason: 'staff headers never show the business switcher',
              );
            }

            // --- Actions stay visible and never collide with the title ---
            final signOut = find.byTooltip('Sign out');
            expect(signOut, findsOneWidget, reason: context);
            final signOutRect = tester.getRect(signOut);
            final syncRect = tester.getRect(find.byType(SyncStatusDot));
            for (final (label, rect) in [
              ('sign out', signOutRect),
              ('sync dot', syncRect),
            ]) {
              expect(
                rect.top,
                greaterThanOrEqualTo(band.top),
                reason: '$label visible at $context',
              );
              expect(
                rect.bottom,
                lessThanOrEqualTo(band.bottom),
                reason: '$label visible at $context',
              );
              // No horizontal overflow: nothing escapes the window.
              expect(rect.left, greaterThanOrEqualTo(0), reason: context);
              expect(
                rect.right,
                lessThanOrEqualTo(width + 0.01),
                reason: '$label stays inside the window at $context',
              );
            }
            expect(
              title.right,
              lessThanOrEqualTo(signOutRect.left),
              reason: 'the title never runs under the actions at $context',
            );

            // --- The brand mark sits inside the window too ---
            expect(brand.left, greaterThanOrEqualTo(0), reason: context);
            expect(
              brand.right,
              lessThanOrEqualTo(width + 0.01),
              reason: context,
            );
            expect(
              title.left,
              greaterThanOrEqualTo(brand.right),
              reason: context,
            );
            expect(title.right, greaterThan(title.left), reason: context);
          },
        );
      }
    }
  }

  // The closed control is only half the story: the menu is the part that
  // expands, and a fixed-height button must still be able to offer every
  // business context in full.
  const contexts = <String>['Cafe', 'Food Truck', 'Combined'];
  for (final dark in [false, true]) {
    for (final width in <double>[360, 390, 480]) {
      testWidgets('the switcher menu shows every business context unclipped at '
          '${width.toInt()}dp in ${dark ? 'dark' : 'light'}', (tester) async {
        await _pumpHeader(tester, width: width, owner: true, dark: dark);
        final context = '${width.toInt()}/${dark ? 'dark' : 'light'}';

        // Closed, the control shows exactly one context: the current one.
        final closed = {
          for (final label in contexts)
            label: _rectsOf(tester, find.text(label)).length,
        };
        expect(
          closed.values.where((count) => count > 0),
          hasLength(1),
          reason: 'the closed control shows one context at $context: $closed',
        );

        await tester.tap(find.byType(BusinessSwitcher));
        await tester.pumpAndSettle();

        expect(
          tester.takeException(),
          isNull,
          reason: 'the menu opens without a layout exception at $context',
        );

        // Opening the menu adds every context, including the selected one, and
        // every added label lands fully on screen — the gold control is
        // width-expanded, so the menu must not run past the window edge.
        for (final label in contexts) {
          final open = _rectsOf(tester, find.text(label));
          expect(
            open.length,
            greaterThan(closed[label]!),
            reason: 'the menu offers "$label" at $context',
          );
          for (final rect in open) {
            expect(rect.left, greaterThanOrEqualTo(0), reason: context);
            expect(
              rect.right,
              lessThanOrEqualTo(width + 0.01),
              reason: '"$label" stays inside the window at $context',
            );
            expect(rect.top, greaterThanOrEqualTo(0), reason: context);
            expect(
              rect.bottom,
              lessThanOrEqualTo(_viewportHeight + 0.01),
              reason: '"$label" stays on screen at $context',
            );
          }
        }
      });
    }
  }
}
