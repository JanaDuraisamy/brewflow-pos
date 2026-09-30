import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_preferences_storage.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// Food Truck roster scope.
///
/// Staff Management must follow the selected business. Food Truck shows only
/// Food Truck staff, while the owner's Combined view keeps the cross-business
/// roster.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'a-owner', email: 'owner@brewflow.example');
const _cafeStaff = AuthUser(id: 'a-cafe-staff', email: 'cafe@brewflow.example');
const _truckStaff = AuthUser(
  id: 'a-truck-staff',
  email: 'truck@brewflow.example',
);

final class _FakeSecure implements SecureStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      defaultValue;

  @override
  Future<void> writeBool(String key, bool value) async {}

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async => defaultValue;

  @override
  Future<void> writeInt(String key, int value) async {}

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async => _values.clear();
}

void main() {
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (tester.binding.transientCallbackCount == 0) return;
    }
  }

  Future<ProviderContainer> pumpRoster(
    WidgetTester tester, {
    required BusinessContext business,
  }) async {
    final prefs = FakePreferencesStorage();
    await AppStorage.init(secure: _FakeSecure(), preferences: prefs);
    addTearDown(prefs.clearAppData);
    await prefs.writeString(
      BusinessSwitcherController.foodTruckShopIdKey,
      'shop-truck',
    );

    final repository = FakeStaffRepository();
    final ownerProfile = await repository.claimOwnership(_owner);
    await repository.createStaffProfile(
      identity: _cafeStaff,
      shopId: ownerProfile.shopId!,
    );
    await repository.createStaffProfile(
      identity: _truckStaff,
      shopId: 'shop-truck',
    );

    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: _owner),
        ),
        staffRepositoryProvider.overrideWithValue(repository),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(FakeCloudShopResolver()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(businessSwitcherProvider.notifier).select(business);

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
    return container;
  }

  testWidgets('Food Truck shows only Food Truck staff', (tester) async {
    await pumpRoster(tester, business: BusinessContext.foodTruck);

    expect(find.byType(StaffPage), findsOneWidget);
    expect(find.text('truck@brewflow.example'), findsOneWidget);
    expect(find.text('cafe@brewflow.example'), findsNothing);
  });

  testWidgets('Combined keeps the cross-business roster', (tester) async {
    await pumpRoster(tester, business: BusinessContext.all);

    expect(find.byType(StaffPage), findsOneWidget);
    expect(find.text('truck@brewflow.example'), findsOneWidget);
    expect(find.text('cafe@brewflow.example'), findsOneWidget);
  });
}
