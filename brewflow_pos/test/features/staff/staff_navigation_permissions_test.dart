import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/shells/access_denied_shell.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// Staff permission-based navigation contract.
///
/// Navigation must be built strictly from the signed-in profile's actual
/// grants: owner keeps every destination; staff sees ONLY granted modules,
/// the dashboard is not owner-only by default, direct routes stay guarded and
/// owner-only screens stay closed to staff. The final group covers the root
/// cause: a staff member joining via cloud resolution must inherit the grant
/// set the owner pushed (BUG: they used to get an empty set → total
/// 'No access to this area').
/// ---------------------------------------------------------------------------

const AuthUser kOwnerUser = AuthUser(id: 'a-1', email: 'o@x.co');
const AuthUser kStaffUser = AuthUser(id: 'a-2', email: 's@x.co');

String debugLocation(GoRouter router) =>
    router.routeInformationProvider.value.uri.toString();

/// Pushes frames until no transient callbacks are scheduled, or up to [limit]
/// iterations — the billing branch carries idle animations, so a strict
/// [pumpAndSettle] would time out on it.
Future<void> _boundedSettle(WidgetTester tester, {int limit = 60}) async {
  for (var i = 0; i < limit; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (tester.binding.transientCallbackCount == 0) return;
  }
}

/// Pumps the full router for [user]; [staffRepo] is seeded before pumping so
/// the profile resolves with the desired grants.
Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester, {
  required AuthUser user,
  required FakeStaffRepository staffRepo,
}) async {
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: user)),
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
  return (container, router);
}

void _widenView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 900);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

void main() {
  group('Owner navigation', () {
    testWidgets('owner keeps the full original navigation', (tester) async {
      _widenView(tester);
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);

      await _pump(tester, user: kOwnerUser, staffRepo: staffRepo);

      for (final label in const [
        'Dashboard',
        'Inventory',
        'Billing',
        'Orders',
        'Customers',
        'Suppliers',
        'Purchases',
        'Expenses',
        'Reports',
        'Offers',
        'Settings',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
    });
  });

  group('Staff permission-based navigation', () {
    testWidgets('staff sees only the pages the owner granted', (tester) async {
      _widenView(tester);
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);
      await staffRepo.createStaffProfile(
        identity: kStaffUser,
        shopId: 'shop-1',
        permissions: defaultStaffPermissions,
      );

      await _pump(tester, user: kStaffUser, staffRepo: staffRepo);

      // The cold-start redirect to the first granted branch collapses the
      // rail at desktop width; reopen it so the granted labels are visible.
      if (find.byTooltip('Open navigation').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('Open navigation'));
        await _boundedSettle(tester);
      }

      // Granted: BILLING / VIEW_INVENTORY / CUSTOMERS / ORDERS. Each granted
      // module is reachable from the navigation (the landing page's own title
      // may repeat the label, so "present" is the contract, not a count).
      expect(find.text('Billing'), findsWidgets);
      expect(find.text('Inventory'), findsWidgets);
      expect(find.text('Customers'), findsWidgets);
      expect(find.text('Orders'), findsWidgets);
      // Not granted: hidden entirely.
      expect(find.text('Dashboard'), findsNothing);
      expect(find.text('Suppliers'), findsNothing);
      expect(find.text('Purchases'), findsNothing);
      expect(find.text('Expenses'), findsNothing);
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Offers'), findsNothing);
      expect(find.text('Settings'), findsNothing);
    });

    testWidgets('staff without VIEW_DASHBOARD cannot reach the dashboard', (
      tester,
    ) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);
      await staffRepo.createStaffProfile(
        identity: kStaffUser,
        shopId: 'shop-1',
        permissions: {Permission.billing},
      );

      final (container, router) = await _pump(
        tester,
        user: kStaffUser,
        staffRepo: staffRepo,
      );

      final profile = container.read(userProfileProvider).value;
      expect(profile?.role, UserRole.staff);
      expect(profile?.permissions, {Permission.billing});

      expect(
        debugLocation(router),
        isNot(AppRoutes.dashboard),
        reason: 'must not route to /dashboard for staff without access',
      );
      expect(find.byType(DashboardPage), findsNothing);
      expect(find.byType(AccessDeniedShell), findsNothing);
      expect(find.byType(PosPage), findsOneWidget);
    });

    testWidgets('staff with VIEW_DASHBOARD lands on the dashboard', (
      tester,
    ) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);
      await staffRepo.createStaffProfile(
        identity: kStaffUser,
        shopId: 'shop-1',
        permissions: {Permission.viewDashboard, Permission.billing},
      );

      final (_, _) = await _pump(
        tester,
        user: kStaffUser,
        staffRepo: staffRepo,
      );

      expect(find.byType(DashboardPage), findsOneWidget);
      expect(find.text('No access to this area'), findsNothing);
    });

    testWidgets('direct navigation to an ungranted route stays blocked', (
      tester,
    ) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);
      await staffRepo.createStaffProfile(
        identity: kStaffUser,
        shopId: 'shop-1',
        permissions: {Permission.billing},
      );

      final (_, router) = await _pump(
        tester,
        user: kStaffUser,
        staffRepo: staffRepo,
      );

      router.go('/reports');
      await _boundedSettle(tester);
      expect(find.byType(AccessDeniedShell), findsOneWidget);
      expect(find.text('No access to this area'), findsOneWidget);
    });

    testWidgets('owner-only storage screens stay closed to staff', (
      tester,
    ) async {
      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(kOwnerUser);
      await staffRepo.createStaffProfile(
        identity: kStaffUser,
        shopId: 'shop-1',
        permissions: {Permission.manageStaff, Permission.billing},
      );

      final (_, router) = await _pump(
        tester,
        user: kStaffUser,
        staffRepo: staffRepo,
      );

      router.go('/storage');
      await _boundedSettle(tester);
      expect(find.text('No access to this area'), findsOneWidget);
    });
  });

  group('Cloud grant propagation (root cause)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    ProviderContainer containerWith({
      required FakeAuthRepository auth,
      required FakeCloudShopResolver resolver,
    }) => ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(auth),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(resolver),
      ],
    );

    test(
      'staff joining via cloud resolution inherits the pushed grant set',
      () async {
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: 'shop-1',
            shopName: 'My Shop',
            email: kStaffUser.email,
            role: 'STAFF',
            isActive: true,
            permissions: {
              Permission.viewDashboard,
              Permission.billing,
              Permission.orders,
            },
          ),
        );
        final container = containerWith(
          auth: FakeAuthRepository(user: kStaffUser),
          resolver: resolver,
        );
        addTearDown(container.dispose);

        final profile = await container.read(userProfileProvider.future);

        expect(profile?.role, UserRole.staff);
        expect(profile?.permissions, {
          Permission.viewDashboard,
          Permission.billing,
          Permission.orders,
        });
      },
    );

    test('existing staff profile mirrors cloud grants when the owner pushes a '
        'new set', () async {
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('shop-1'), name: 'My Shop'));
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              email: kStaffUser.email,
              authUserId: Value(kStaffUser.id),
              shopId: Value('shop-1'),
              role: const Value('STAFF'),
            ),
          );
      const stale = {Permission.billing};

      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: 'shop-1',
          shopName: 'My Shop',
          email: kStaffUser.email,
          role: 'STAFF',
          isActive: true,
          // Owner granted more on another device.
          permissions: {
            Permission.billing,
            Permission.viewDashboard,
            Permission.reports,
          },
        ),
      );
      final container = containerWith(
        auth: FakeAuthRepository(user: kStaffUser),
        resolver: resolver,
      );
      addTearDown(container.dispose);

      final profile = await container.read(userProfileProvider.future);

      expect(profile?.role, UserRole.staff);
      expect(profile?.permissions, isNot(equals(stale)));
      expect(profile?.permissions, {
        Permission.billing,
        Permission.viewDashboard,
        Permission.reports,
      });
      // The controller must never derive OWNER from the cloud profile.
      expect(profile?.isOwner, isFalse);
    });
  });
}
