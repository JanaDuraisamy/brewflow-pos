import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/app_navigation.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_connectivity_service.dart';
import '../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// Sidebar active-item mapping.
///
/// `AppSidebar.selectedIndex` indexes the RENDERED destination list. For staff
/// that list is a permission-filtered subset, so the shell must translate the
/// router branch index into the list position. Regression guard: staff used to
/// pass the raw branch index straight through, drifting the highlight one
/// module across (Inventory → Billing, Billing → Orders, …).
/// ---------------------------------------------------------------------------

const AuthUser kOwnerUser = AuthUser(id: 'a-1', email: 'o@x.co');
const AuthUser kStaffUser = AuthUser(id: 'a-2', email: 's@x.co');

/// Grants covering the five guarded modules below; excludes Dashboard so the
/// filtered list starts at Inventory (the case that exposed the drift).
const Set<Permission> _granted = {
  Permission.viewInventory,
  Permission.billing,
  Permission.orders,
  Permission.customers,
  Permission.expenses,
};

Future<void> _boundedSettle(WidgetTester tester, {int limit = 60}) async {
  for (var i = 0; i < limit; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.binding.transientCallbackCount == 0) return;
  }
}

void _widenView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<GoRouter> _pumpStaff(WidgetTester tester) async {
  final staffRepo = FakeStaffRepository();
  await staffRepo.claimOwnership(kOwnerUser);
  await staffRepo.createStaffProfile(
    identity: kStaffUser,
    shopId: 'shop-1',
    permissions: _granted,
  );
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(user: kStaffUser),
      ),
      staffRepositoryProvider.overrideWithValue(staffRepo),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(appRouterProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await _boundedSettle(tester);
  return router;
}

String _activeSidebarLabel(WidgetTester tester) {
  final sidebar = tester.widget<AppSidebar>(find.byType(AppSidebar));
  return sidebar.items[sidebar.selectedIndex].label;
}

/// Desktop (>= 600) collapses the rail after any navigation — including the
/// staff cold-start redirect to the first granted branch — so tests reopen it
/// before reading the rendered rail.
Future<void> _reopenRail(WidgetTester tester) async {
  if (find.byType(AppSidebar).evaluate().isEmpty) {
    await tester.tap(find.byTooltip('Open navigation'));
    await _boundedSettle(tester);
  }
}

void main() {
  group('sidebar highlights the current module for filtered staff', () {
    testWidgets('Inventory route maps to the Inventory sidebar item', (
      tester,
    ) async {
      _widenView(tester);
      final router = await _pumpStaff(tester);

      router.go(AppRoutes.inventory);
      await _boundedSettle(tester);
      await _reopenRail(tester);

      expect(_activeSidebarLabel(tester), 'Inventory');
    });

    testWidgets('Billing route maps to the Billing sidebar item', (
      tester,
    ) async {
      _widenView(tester);
      final router = await _pumpStaff(tester);

      router.go(AppRoutes.billing);
      await _boundedSettle(tester);
      await _reopenRail(tester);

      expect(_activeSidebarLabel(tester), 'Billing');
    });

    testWidgets('Orders route maps to the Orders sidebar item', (tester) async {
      _widenView(tester);
      final router = await _pumpStaff(tester);

      router.go(AppRoutes.orders);
      await _boundedSettle(tester);
      await _reopenRail(tester);

      expect(_activeSidebarLabel(tester), 'Orders');
    });

    testWidgets('Customers route maps to the Customers sidebar item', (
      tester,
    ) async {
      _widenView(tester);
      final router = await _pumpStaff(tester);

      router.go(AppRoutes.customers);
      await _boundedSettle(tester);
      await _reopenRail(tester);

      expect(_activeSidebarLabel(tester), 'Customers');
    });

    testWidgets('Expenses route maps to the Expenses sidebar item', (
      tester,
    ) async {
      _widenView(tester);
      final router = await _pumpStaff(tester);

      router.go(AppRoutes.expenses);
      await _boundedSettle(tester);
      await _reopenRail(tester);

      expect(_activeSidebarLabel(tester), 'Expenses');
    });
  });
}
