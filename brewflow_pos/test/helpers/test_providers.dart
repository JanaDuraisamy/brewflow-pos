import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_connectivity_service.dart';
import 'fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Test Provider Overrides
///
/// Centralises the provider overrides that every widget test needs to avoid
/// hitting real platform plugins.
/// ---------------------------------------------------------------------------

/// Returns a list with the standard connectivity fake override.
///
/// Use when building a [ProviderContainer] for tests that render [AppShell]
/// or any widget reading `syncStatusProvider`.
///
/// ```dart
/// ProviderContainer(overrides: [...connectivityOverrides()]);
/// ```
List<dynamic> connectivityOverrides() => [
  connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
];

/// Overrides that let business-scoped controllers resolve a shop id without
/// touching the real database or SharedPreferences.
///
/// Shop-scoped reads resolve their scope from the authenticated profile
/// ([userProfileProvider]) and fail closed when that profile has not resolved,
/// so a test that renders the shelf, the inventory list or the POS counter must
/// declare which shop it is signed in to. [businessScopeOverrides] pins an
/// owner of the Cafe — the same `shop-1` identity [FakeStaffRepository] hands
/// out — so feature fakes and shop scoping agree.
///
/// The staff repository is still overridden because write paths
/// (`requireWritableShopId`) materialise the row through it.
///
/// Add this to every container that exercises a shop-scoped controller:
///
/// ```dart
/// ProviderContainer(overrides: [
///   inventoryRepositoryProvider.overrideWithValue(fake),
///   ...businessScopeOverrides(),
/// ]);
/// ```
///
/// Pass a profile to model a different session:
///
/// ```dart
/// ...businessScopeOverrides(profile: testStaffProfile(shopId: kTestFoodTruckShopId))
/// ```
List<dynamic> businessScopeOverrides({
  FakeStaffRepository? staff,
  UserProfile? profile,
}) => [
  staffRepositoryProvider.overrideWithValue(staff ?? FakeStaffRepository()),
  userProfileProvider.overrideWithBuild(
    (ref, notifier) => profile ?? testOwnerProfile(),
  ),
];

/// Shop id the POS/Inventory fixtures seed products and categories under.
const String kTestCafeShopId = 'shop-1';

/// The second business, for Food Truck and shared-catalogue scenarios.
const String kTestFoodTruckShopId = 'shop-2';

/// A signed-in OWNER of the Cafe: full multi-business switcher.
UserProfile testOwnerProfile({String shopId = kTestCafeShopId}) => UserProfile(
  id: 'test-owner',
  email: 'owner@brewflow.test',
  role: UserRole.owner,
  isActive: true,
  permissions: const {},
  shopId: shopId,
);

/// A signed-in STAFF member pinned to [shopId].
///
/// Staff are single-shop by contract: no business switcher, and every read is
/// scoped to this id regardless of the persisted selection.
UserProfile testStaffProfile({String shopId = kTestCafeShopId}) => UserProfile(
  id: 'test-staff',
  email: 'staff@brewflow.test',
  role: UserRole.staff,
  isActive: true,
  permissions: const {
    Permission.viewDashboard,
    Permission.billing,
    Permission.viewInventory,
  },
  shopId: shopId,
);
