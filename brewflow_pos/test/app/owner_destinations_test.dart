import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/shells/access_denied_shell.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/closing/presentation/daily_closing_page.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_payroll_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_connectivity_service.dart';
import '../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// Owner destinations: Staff Attendance (/staff/payroll) and Daily Closing
/// (/closing) are separate pushed pages on the existing router (not shell
/// branches), owner-reachable with working back navigation, and hidden from
/// staff by the existing permission guard. Entries arrive via go() (push()
/// does not resolve across navigators in this router setup), so each page
/// owns its back navigation: an explicit BackButton plus PopScope for the
/// Android system back/gesture. Phone navigation is untouched: the same
/// Scaffold back stack works on every width.
/// ---------------------------------------------------------------------------

void main() {
  const owner = AuthUser(id: 'a-1', email: 'o@x.co');
  const staffAuth = AuthUser(id: 'a-2', email: 's@x.co');

  const profile = UserProfile(
    id: 'staff-1',
    email: 's@x.co',
    role: UserRole.staff,
    isActive: true,
    permissions: {Permission.billing},
    shopId: 'shop-1',
  );

  Future<(ProviderContainer, GoRouter)> pumpWith(
    WidgetTester tester, {
    required FakeAuthRepository auth,
    required FakeStaffRepository staffRepo,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        staffRepositoryProvider.overrideWithValue(staffRepo),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
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
    return (container, router);
  }

  Future<FakeStaffRepository> ownerRepo() async {
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(owner);
    return staffRepo;
  }

  Future<FakeStaffRepository> billingOnlyStaffRepo() async {
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(owner);
    await staffRepo.createStaffProfile(
      identity: staffAuth,
      shopId: 'shop-1',
      permissions: {Permission.billing},
    );
    return staffRepo;
  }

  testWidgets('owner opens Daily Closing with a Back button', (tester) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.closing);
    await _boundedSettle(tester);
    expect(find.byType(DailyClosingPage), findsOneWidget);
    // Dedicated page with an always-visible Back button (entries arrive
    // via go(), so no automatic back affordance exists).
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('owner opens Staff Attendance with a Back button', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.staffPayroll, extra: profile);
    await _boundedSettle(tester);
    expect(find.byType(StaffPayrollPage), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('Back button returns from Daily Closing to the dashboard', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.closing);
    await _boundedSettle(tester);
    expect(find.byType(DailyClosingPage), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _boundedSettle(tester);
    expect(find.byType(DailyClosingPage), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      anyOf([AppRoutes.dashboard, startsWith(AppRoutes.dashboard)]),
    );
  });

  testWidgets('Back button returns from Staff Attendance to the staff list', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.staffPayroll, extra: profile);
    await _boundedSettle(tester);
    expect(find.byType(StaffPayrollPage), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await _boundedSettle(tester);
    expect(find.byType(StaffPayrollPage), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.staff,
    );
  });

  testWidgets('system back returns from Daily Closing to the dashboard', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.closing);
    await _boundedSettle(tester);
    expect(find.byType(DailyClosingPage), findsOneWidget);

    await tester.pageBack();
    await _boundedSettle(tester);
    expect(find.byType(DailyClosingPage), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      anyOf([AppRoutes.dashboard, startsWith(AppRoutes.dashboard)]),
    );
  });

  testWidgets('system back returns from Staff Attendance to the staff list', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: owner),
      staffRepo: await ownerRepo(),
    );
    router.go(AppRoutes.staffPayroll, extra: profile);
    await _boundedSettle(tester);
    expect(find.byType(StaffPayrollPage), findsOneWidget);

    await tester.pageBack();
    await _boundedSettle(tester);
    expect(find.byType(StaffPayrollPage), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      AppRoutes.staff,
    );
  });

  testWidgets('staff without grants cannot open owner destinations', (
    tester,
  ) async {
    final (_, router) = await pumpWith(
      tester,
      auth: FakeAuthRepository(user: staffAuth),
      staffRepo: await billingOnlyStaffRepo(),
    );
    router.go(AppRoutes.staffPayroll);
    await _boundedSettle(tester);
    expect(find.byType(AccessDeniedShell), findsOneWidget);

    router.go(AppRoutes.closing);
    await _boundedSettle(tester);
    expect(find.byType(AccessDeniedShell), findsOneWidget);
  });
}

Future<void> _boundedSettle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
