import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_repository.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';

/// ---------------------------------------------------------------------------
/// Food Truck staff login and shop scope.
///
/// A Food Truck staff member must resolve to the Food Truck shop after login,
/// see only that business's roster entries, and use that shop as the default
/// write scope on a staff device. Cafe staff and the Cafe roster must stay
/// untouched.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'a-owner', email: 'owner@brewflow.example');
const _truckStaff = AuthUser(
  id: 'a-truck-staff',
  email: 'truck@brewflow.example',
);
const _cafeStaff = AuthUser(id: 'a-cafe-staff', email: 'cafe@brewflow.example');
const _cafeShop = 'shop-cafe';
const _truckShop = 'shop-truck';

void main() {
  late AppDatabase database;
  late DriftStaffRepository staff;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    staff = DriftStaffRepository(database);
    await staff.ensureShopWithId(_cafeShop, name: 'Cafe');
    await staff.ensureShopWithId(_truckShop, name: 'Food Truck');
  });

  tearDown(() async => database.close());

  ProviderContainer containerWith({
    required AuthUser session,
    required CloudUserProfile cloudProfile,
  }) {
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: session),
        ),
        staffRepositoryProvider.overrideWithValue(staff),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(
          FakeCloudShopResolver(profile: cloudProfile),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  CloudUserProfile truckStaffCloudProfile() => const CloudUserProfile(
    shopId: _truckShop,
    shopName: 'Food Truck',
    email: 'truck@brewflow.example',
    role: 'STAFF',
    isActive: true,
  );

  test('Food Truck staff login resolves to the Food Truck shop', () async {
    final container = containerWith(
      session: _truckStaff,
      cloudProfile: truckStaffCloudProfile(),
    );

    final profile = await container.read(userProfileProvider.future);

    expect(profile, isNotNull);
    expect(profile!.role, UserRole.staff);
    expect(profile.isActive, isTrue);
    expect(profile.shopId, _truckShop);

    // Staff tablets use the Cafe context; it must follow the staff profile's
    // own shop rather than minting or borrowing another business.
    final cafeContextShop = await container
        .read(businessSwitcherProvider.notifier)
        .shopIdFor(BusinessContext.cafe);
    expect(cafeContextShop, _truckShop);
  });

  test('Food Truck and Cafe rosters stay separated', () async {
    await staff.claimOwnership(_owner);
    await staff.createStaffProfile(identity: _cafeStaff, shopId: _cafeShop);
    await staff.createStaffProfile(identity: _truckStaff, shopId: _truckShop);

    expect(
      (await staff.staffMembers(
        shopId: _truckShop,
      )).map((member) => member.email),
      ['truck@brewflow.example'],
    );
    expect(
      (await staff.staffMembers(
        shopId: _cafeShop,
      )).map((member) => member.email),
      ['cafe@brewflow.example'],
    );
  });

  test('a staff-only device defaults writes to the staff shop', () async {
    final fresh = AppDatabase(NativeDatabase.memory());
    addTearDown(fresh.close);
    final freshStaff = DriftStaffRepository(fresh);
    await freshStaff.ensureShopWithId(_truckShop, name: 'Food Truck');
    await freshStaff.createStaffProfile(
      identity: _truckStaff,
      shopId: _truckShop,
    );

    expect(await resolveWritableShopId(fresh), _truckShop);
  });
}
