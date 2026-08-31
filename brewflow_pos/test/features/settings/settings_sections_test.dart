import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

Set<Permission> _permissionsFromDbValues(Set<String> dbValues) {
  final byKey = {for (final p in Permission.values) p.dbValue: p};
  return {
    for (final value in dbValues)
      if (byKey[value] != null) byKey[value]!,
  };
}

Future<(ProviderContainer, GoRouter)> _pumpSettings(
  WidgetTester tester, {
  required AuthUser user,
  Set<String> staffPermissions = const {},
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1200, 1400);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final staffRepo = FakeStaffRepository();
  await staffRepo.claimOwnership(const AuthUser(id: 'a-1', email: 'o@x.co'));
  if (user.email != 'o@x.co') {
    final member = await staffRepo.createStaffProfile(
      identity: user,
      shopId: 'shop-1',
      permissions: _permissionsFromDbValues(staffPermissions),
    );
    // createStaffProfile already stores permissions; keep activation state.
    await staffRepo.updateStaff(StaffUpdateInput(id: member.id));
  }

  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(user: user)),
      staffRepositoryProvider.overrideWithValue(staffRepo),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
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
  router.go('/settings');
  await tester.pumpAndSettle();
  return (container, router);
}

void main() {
  testWidgets(
    'owner sees the Staff & Permissions entry and it navigates to Staff Management',
    (tester) async {
      final (_, router) = await _pumpSettings(
        tester,
        user: const AuthUser(id: 'a-1', email: 'o@x.co'),
      );

      expect(find.text('Business identity'), findsOneWidget);
      expect(
        find.text('Receipt printing status and diagnostics.'),
        findsOneWidget,
      );
      expect(find.text('Staff & Permissions'), findsOneWidget);
      expect(find.text('Staff Management'), findsOneWidget);

      await tester.ensureVisible(find.text('Staff Management'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Staff Management'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        '/staff',
      );
      expect(find.text('No staff yet'), findsOneWidget);
    },
  );

  testWidgets(
    'staff without manage-staff permission sees no owner-only staff controls',
    (tester) async {
      await _pumpSettings(
        tester,
        user: const AuthUser(id: 'a-2', email: 's@x.co'),
        // SETTINGS lets staff reach this page; MANAGE_STAFF stays off.
        staffPermissions: {'SETTINGS'},
      );

      expect(find.text('Business identity'), findsOneWidget);
      expect(find.text('Staff & Permissions'), findsNothing);
      expect(find.text('Staff Management'), findsNothing);
    },
  );

  testWidgets('printer section stays honest about unverified hardware', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      user: const AuthUser(id: 'a-1', email: 'o@x.co'),
    );

    expect(find.textContaining('not yet verified'), findsOneWidget);

    await tester.ensureVisible(find.text('Test Print'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test Print'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not set up yet'), findsOneWidget);
  });
}
