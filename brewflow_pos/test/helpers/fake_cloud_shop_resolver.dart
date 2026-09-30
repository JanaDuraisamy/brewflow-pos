import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';

/// Test double for [CloudShopResolver].
///
/// Returns a configurable cloud profile and shop-existence result, and records
/// every [pushIdentity] call so durability / retry / idempotency can be
/// asserted. [fetchProfile] can be forced to throw to simulate a cloud outage.
final class FakeCloudShopResolver extends CloudShopResolver {
  FakeCloudShopResolver({
    this.profile,
    this.shopExistsResult = true,
    this.pushIdentityResult = true,
    this.pushIdentityFailures = 0,
    this.fetchThrows = false,
    this.roster = const [],
    this.rosterThrows = false,
    this.managedShops = const [],
    this.managedShopsThrows = false,
    this.deleteStaffResult = true,
    Map<String, String>? staffProfileRoles,
  }) : staffProfileRoles = staffProfileRoles ?? {};

  /// The profile [fetchProfile] returns (null = no cloud profile).
  final CloudUserProfile? profile;

  /// Result of [shopExists] for any shop id.
  final bool shopExistsResult;

  /// Whether [pushIdentity] succeeds once the leading failures are exhausted.
  final bool pushIdentityResult;

  /// Number of leading [pushIdentity] calls that should fail before succeeding.
  int pushIdentityFailures;

  /// When true, [fetchProfile] throws (cloud outage), exercising safe fallback.
  final bool fetchThrows;

  /// The shop staff roster [loadShopStaff] returns. Mutable so a test can swap
  /// the roster between authorization rebuilds. Used as the fallback for any
  /// shop that has no entry in [rostersByShop].
  List<CloudStaffMember> roster;

  /// Per-shop rosters keyed by shop id, consulted by [loadShopStaff] before
  /// [roster]. Lets a test model an owner who manages two businesses with
  /// different staff on each.
  Map<String, List<CloudStaffMember>> rostersByShop = {};

  /// Shop ids whose roster fetch should fail, so a test can prove one
  /// unreachable business does not block the others.
  Set<String> rosterThrowsFor = {};

  /// When true, [loadShopStaff] throws (roster outage), exercising the
  /// "a roster hiccup never blocks authorization" fallback.
  bool rosterThrows;

  /// The memberships [listManagedShops] returns — the clear-data recovery
  /// source. Empty means "no second business exists in the cloud".
  List<CloudManagedShop> managedShops;

  /// When true, [listManagedShops] throws (cloud outage), exercising the
  /// "recovery fails, fall back to create" path.
  bool managedShopsThrows;

  /// Number of times [listManagedShops] has been called.
  int managedShopQueries = 0;

  /// Result of [deleteStaffProfile]. False simulates the cloud refusing the
  /// delete, which must leave the local mirror untouched.
  final bool deleteStaffResult;

  /// Simulated cloud `user_profiles.role` by auth user id. When empty, every
  /// delete uses [deleteStaffResult] for backward compatibility. When
  /// populated, only an explicit `'STAFF'` entry can succeed, mirroring the
  /// server RPC's OWNER refusal and unknown-target failure.
  final Map<String, String> staffProfileRoles;

  /// Every auth user id handed to [deleteStaffProfile] (in call order).
  final List<String> deletedAuthUserIds = [];

  /// Every shop id handed to [loadShopStaff] (in call order).
  final List<String> rosterQueries = [];

  /// Every shop id handed to [pushIdentity] (in call order).
  final List<String> pushedShopIds = [];

  /// Every auth user id handed to [pushIdentity] (in call order).
  final List<String> pushedAuthUserIds = [];

  @override
  Future<CloudUserProfile?> fetchProfile(String authUserId) async {
    if (fetchThrows) throw Exception('cloud unavailable');
    return profile;
  }

  @override
  Future<bool> shopExists(String shopId) async => shopExistsResult;

  @override
  Future<List<CloudStaffMember>> loadShopStaff(String shopId) async {
    rosterQueries.add(shopId);
    if (rosterThrows || rosterThrowsFor.contains(shopId)) {
      throw Exception('roster unavailable');
    }
    return rostersByShop[shopId] ?? roster;
  }

  @override
  Future<List<CloudManagedShop>> listManagedShops() async {
    managedShopQueries++;
    if (managedShopsThrows) throw Exception('cloud unavailable');
    return managedShops;
  }

  @override
  Future<bool> deleteStaffProfile({required String authUserId}) async {
    deletedAuthUserIds.add(authUserId);
    if (staffProfileRoles.isNotEmpty &&
        staffProfileRoles[authUserId] != 'STAFF') {
      return false;
    }
    return deleteStaffResult;
  }

  @override
  Future<bool> pushIdentity({
    required String shopId,
    required String shopName,
    required String authUserId,
    required String email,
  }) async {
    pushedShopIds.add(shopId);
    pushedAuthUserIds.add(authUserId);
    if (pushIdentityFailures > 0) {
      pushIdentityFailures--;
      return false;
    }
    return pushIdentityResult;
  }
}
