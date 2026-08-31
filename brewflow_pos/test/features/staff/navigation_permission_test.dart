import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_staff_repository.dart';

Future<(ProviderContainer, GoRouter)> _pump(
  WidgetTester tester, {
  required AuthUser user,
}) async {
  final staffRepo = FakeStaffRepository();
  await staffRepo.claimOwnership(const AuthUser(id: 'a-1', email: 'o@x.co'));
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
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets('owner sees all ten navigation destinations', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final (_, _) = await _pump(
      tester,
      user: const AuthUser(id: 'a-1', email: 'o@x.co'),
    );

    for (final label in [
      'Dashboard',
      'Inventory',
      'Billing',
      'Orders',
      'Customers',
      'Suppliers',
      'Purchases',
      'Expenses',
      'Reports',
      'Settings',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('staff with default permissions sees only allowed modules', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(const AuthUser(id: 'a-1', email: 'o@x.co'));
    await staffRepo.createStaffProfile(
      identity: const AuthUser(id: 'a-2', email: 's@x.co'),
      shopId: 'shop-1',
      // Defaults: BILLING / VIEW_INVENTORY / CUSTOMERS / ORDERS.
      permissions: defaultStaffPermissions,
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

    expect(find.text('Dashboard'), findsNothing);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Billing'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Suppliers'), findsNothing);
    expect(find.text('Purchases'), findsNothing);
    expect(find.text('Expenses'), findsNothing);
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    router.go('/reports');
    await tester.pumpAndSettle();
    expect(find.text('No access to this area'), findsOneWidget);
  });
}
