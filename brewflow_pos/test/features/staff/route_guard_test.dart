import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/app/shells/access_denied_shell.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_staff_repository.dart';

void main() {
  testWidgets('staff without REPORTS hitting /reports lands on no-access', (
    tester,
  ) async {
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(const AuthUser(id: 'a-1', email: 'o@x.co'));
    await staffRepo.createStaffProfile(
      identity: const AuthUser(id: 'a-2', email: 's@x.co'),
      shopId: 'shop-1',
      permissions: {Permission.billing},
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            user: const AuthUser(id: 'a-2', email: 's@x.co'),
          ),
        ),
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
    // Let profile resolution finish; authenticated users land on dashboard.
    await tester.pumpAndSettle();
    router.go('/reports');
    await tester.pumpAndSettle();

    expect(find.byType(AccessDeniedShell), findsOneWidget);
    expect(find.text('No access to this area'), findsOneWidget);
  });

  testWidgets('staff with BILLING can open /billing directly', (tester) async {
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(const AuthUser(id: 'a-1', email: 'o@x.co'));
    await staffRepo.createStaffProfile(
      identity: const AuthUser(id: 'a-2', email: 's@x.co'),
      shopId: 'shop-1',
      permissions: {Permission.billing},
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            user: const AuthUser(id: 'a-2', email: 's@x.co'),
          ),
        ),
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
    await tester.pumpAndSettle();
    router.go('/billing');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(PosPage), findsOneWidget);
    expect(find.byType(AccessDeniedShell), findsNothing);
  });
}
