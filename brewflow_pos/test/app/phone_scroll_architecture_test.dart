import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
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
import '../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// Scroll architecture contract for phone pages.
///
/// Overflow tests cannot see a scroll-architecture fault. A page that hands two
/// boxes the same vertical axis still lays out cleanly, and so does a list whose
/// owner cannot actually reach its last row — the user just quietly cannot get
/// to the data. So these assert the two things a phone user depends on:
///
///  1. exactly one draggable vertical axis owns the page, and
///  2. that axis really travels: a drag moves it, the middle rows come into
///     view, and the end of the list lands on `maxScrollExtent` with the last
///     row rendered.
///
/// Deliberately not asserted, because the app gets these right on purpose:
/// horizontal axes (filter chip rows, the POS category rail, a table's
/// horizontal pass) and `shrinkWrap` lists whose physics are disabled so a
/// parent scroll view owns the axis. Both are load-bearing, not faults.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

/// Every logical phone width under the 600dp layout rail.
const _phoneWidths = <double>[360, 390, 411, 480];

const _phoneHeight = 800.0;
const _topInset = 44.0;
const _bottomInset = 34.0;

/// More rows than any tested viewport can show, so the list must scroll.
const _rowCount = 20;

/// The customer list is sorted by name, so row labels must be zero-padded or
/// "Customer 10" sorts ahead of "Customer 2" and the last row stops being
/// `Customer 20` — which would make a reachability test assert the wrong thing.
String label(int i) => 'Customer ${i.toString().padLeft(2, '0')}';

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeCustomersRepository fakeCustomers;
  late FakeStaffRepository fakeStaff;

  final now = DateTime.now();

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeCustomers = FakeCustomersRepository();
    fakeStaff = FakeStaffRepository();
  });

  Customer customer(int i) => Customer(
    id: 'c$i',
    name: label(i),
    phone: '900000${i.toString().padLeft(4, '0')}',
    email: 'c$i@brewflow.example',
    address: '12 Market Street',
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      customersRepositoryProvider.overrideWithValue(fakeCustomers),
      staffRepositoryProvider.overrideWithValue(fakeStaff),
      inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
      billingRepositoryProvider.overrideWithValue(
        FakeBillingRepository(FakeInventoryRepository()),
      ),
      ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      suppliersRepositoryProvider.overrideWithValue(FakeSuppliersRepository()),
      purchasesRepositoryProvider.overrideWithValue(FakePurchasesRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
      // The customer list is shop-scoped and fails closed without a session, so
      // state the signed-in owner. `staffRepositoryProvider` is overridden above
      // and Riverpod forbids overriding a provider twice.
      userProfileProvider.overrideWithBuild(
        (ref, notifier) => testOwnerProfile(),
      ),
    ],
    child: const BrewFlowApp(),
  );

  /// The scrollable that owns the page's vertical axis, or null.
  ///
  /// A `shrinkWrap` list with `NeverScrollableScrollPhysics` is not an owner by
  /// design — its parent is — so those are skipped, as are horizontal axes such
  /// as a `TextField`'s or a chip rail's.
  ScrollableState? verticalOwner(WidgetTester tester) {
    for (final element in tester.elementList(find.byType(Scrollable))) {
      final widget = element.widget as Scrollable;
      if (widget.physics is NeverScrollableScrollPhysics) continue;
      if (widget.axisDirection != AxisDirection.down) continue;
      if (widget.controller?.positions.isEmpty ?? true) continue;
      return tester.state<ScrollableState>(
        find.byElementPredicate((candidate) => candidate == element),
      );
    }
    return null;
  }

  int verticalOwners(WidgetTester tester) {
    var count = 0;
    for (final element in tester.elementList(find.byType(Scrollable))) {
      final widget = element.widget as Scrollable;
      if (widget.physics is NeverScrollableScrollPhysics) continue;
      if (widget.axisDirection != AxisDirection.down) continue;
      if (widget.controller?.positions.isEmpty ?? true) continue;
      count++;
    }
    return count;
  }

  Future<void> pumpCustomers(WidgetTester tester, double width) async {
    fakeCustomers.storedCustomers.addAll([
      for (var i = 1; i <= _rowCount; i++) customer(i),
    ]);
    await fakeStaff.claimOwnership(_owner);

    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = Size(width, _phoneHeight);
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

    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();

    final element = tester.element(find.byType(Scaffold).first);
    ProviderScope.containerOf(
      element,
    ).read(appRouterProvider).go(AppRoutes.customers);
    await tester.pumpAndSettle();
  }

  for (final width in _phoneWidths) {
    testWidgets('customers page has exactly one vertical scroll owner at '
        '${width}dp', (tester) async {
      await pumpCustomers(tester, width);

      expect(
        tester.takeException(),
        isNull,
        reason: 'no layout exception at ${width}dp',
      );
      expect(
        verticalOwners(tester),
        1,
        reason:
            'one draggable vertical axis must own the page at ${width}dp, '
            'found ${verticalOwners(tester)} — two owners on the same axis '
            'makes the outer one swallow drags',
      );
    });

    testWidgets('customers page reaches its last of $_rowCount rows at '
        '${width}dp', (tester) async {
      await pumpCustomers(tester, width);

      // Arrival: the first row is on screen with no scrolling.
      expect(
        find.text(label(1), findRichText: true),
        findsOneWidget,
        reason: 'first row must be visible on arrival at ${width}dp',
      );

      final owner = verticalOwner(tester);
      expect(owner, isNotNull, reason: 'a vertical owner must exist');
      final position = owner!.position;
      final ownerScrollable = find.byElementPredicate(
        (e) => e.widget == owner.widget,
      );
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason: '$_rowCount rows must overflow the viewport at ${width}dp',
      );
      expect(
        position.pixels,
        0,
        reason: 'the page must start at the top at ${width}dp',
      );

      // A real drag, not a programmatic jump: the offset must move.
      await tester.drag(ownerScrollable, const Offset(0, -180));
      await tester.pumpAndSettle();
      expect(
        position.pixels,
        greaterThan(0),
        reason: 'dragging must move the page at ${width}dp',
      );

      // The middle of the list is reachable.
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      final middle = [
        for (var i = 2; i < _rowCount; i++)
          if (find.text(label(i), findRichText: true).evaluate().isNotEmpty) i,
      ];
      expect(
        middle,
        isNotEmpty,
        reason:
            'a row from the middle of the list must be on screen at '
            '${width}dp',
      );
      expect(
        middle.any((i) => i > _rowCount ~/ 2),
        isTrue,
        reason:
            'scrolling to mid-extent must reach past row ${_rowCount ~/ 2} '
            'at ${width}dp, saw rows $middle',
      );

      // And the very end. `maxScrollExtent` is an estimate while the rows are
      // still being measured, so it is not a value to assert against; the
      // invariant that matters is that the list bottoms out and the last row
      // is on screen once it has.
      await tester.scrollUntilVisible(
        find.text(label(_rowCount), findRichText: true),
        150,
        scrollable: ownerScrollable,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(label(_rowCount), findRichText: true),
        findsOneWidget,
        reason: 'the last row must be reachable at ${width}dp',
      );

      // Flick to the end, then prove there is nothing past it.
      await tester.fling(ownerScrollable, const Offset(0, -4000), 4000);
      await tester.pumpAndSettle();
      expect(
        find.text(label(_rowCount), findRichText: true),
        findsOneWidget,
        reason: 'the last row must still be on screen at the end at ${width}dp',
      );
      final endPixels = position.pixels;
      await tester.drag(ownerScrollable, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        position.pixels,
        moreOrLessEquals(endPixels, epsilon: 1.0),
        reason:
            'the list must bottom out at ${width}dp '
            '(moved from $endPixels to ${position.pixels})',
      );
    });
  }

  testWidgets('the last customer row is not hidden behind the bottom bar', (
    tester,
  ) async {
    await pumpCustomers(tester, 390);

    final owner = verticalOwner(tester);
    expect(owner, isNotNull);
    await tester.scrollUntilVisible(
      find.text(label(_rowCount), findRichText: true),
      150,
      scrollable: find.byElementPredicate((e) => e.widget == owner!.widget),
    );
    await tester.pumpAndSettle();

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget, reason: 'the phone shell shows a bottom bar');
    final barTop = tester.getRect(bar).top;
    final lastRow = tester.getRect(
      find.text(label(_rowCount), findRichText: true),
    );
    expect(
      lastRow.bottom,
      lessThanOrEqualTo(barTop),
      reason:
          'the last row must end above the bottom bar (row bottom '
          '${lastRow.bottom}, bar top $barTop)',
    );
  });
}
