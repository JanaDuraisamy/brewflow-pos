import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Management Owner-Delete Regression
///
/// Locks the boundary and the effect of the new Owner → Remove Staff action:
///
///  - the destructive action is offered to the OWNER only, never to staff who
///    merely hold manageStaff;
///  - a refused cloud delete removes nobody locally, so both mirrors keep
///    agreeing;
///  - a confirmed delete archives the member and clears the roster.
/// ---------------------------------------------------------------------------

const owner = AuthUser(id: 'a-owner', email: 'owner@x.co');
const member = AuthUser(id: 'a-staff', email: 'staff@x.co');

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.binding.transientCallbackCount == 0) return;
    }
  }

  Future<FakeStaffRepository> seedRoster({
    Set<Permission> memberPermissions = defaultStaffPermissions,
  }) async {
    final repo = FakeStaffRepository();
    await repo.claimOwnership(owner);
    await repo.createStaffProfile(
      identity: member,
      shopId: 'shop-1',
      permissions: memberPermissions,
    );
    return repo;
  }

  Future<void> pumpStaffPage(
    WidgetTester tester, {
    required AuthUser session,
    required FakeStaffRepository repo,
    required bool cloudDeleteSucceeds,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: session),
        ),
        staffRepositoryProvider.overrideWithValue(repo),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(
          FakeCloudShopResolver(deleteStaffResult: cloudDeleteSucceeds),
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
    await settle(tester);
    router.go(AppRoutes.staff);
    await settle(tester);
  }

  testWidgets('owner is offered Remove and can complete it', (tester) async {
    final repo = await seedRoster();
    await pumpStaffPage(
      tester,
      session: owner,
      repo: repo,
      cloudDeleteSucceeds: true,
    );

    expect(find.byType(StaffPage), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The dialog must state that payroll history survives.
    expect(
      find.textContaining('history is kept'),
      findsOneWidget,
      reason: 'the owner must be told payroll history survives',
    );

    await tester.tap(find.text('Remove').last);
    await settle(tester);

    expect(repo.archivedProfileIds, isNotEmpty);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('staff holding manageStaff never sees Remove', (tester) async {
    final repo = await seedRoster(
      memberPermissions: {Permission.manageStaff, Permission.billing},
    );
    await pumpStaffPage(
      tester,
      session: member,
      repo: repo,
      cloudDeleteSucceeds: true,
    );

    // The page is reachable because this staff holds manageStaff...
    expect(find.byType(StaffPage), findsOneWidget);
    // ...but removal is the owner's call alone.
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('a refused cloud delete removes nobody locally', (tester) async {
    final repo = await seedRoster();
    await pumpStaffPage(
      tester,
      session: owner,
      repo: repo,
      cloudDeleteSucceeds: false,
    );

    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Remove').last);
    await settle(tester);

    expect(
      repo.archivedProfileIds,
      isEmpty,
      reason:
          'the local mirror must not be dropped while the cloud still has it',
    );
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });
}
