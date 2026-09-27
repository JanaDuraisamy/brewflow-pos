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
    this.deleteStaffResult = true,
  }) : super();

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
  /// the roster between authorization rebuilds.
  List<CloudStaffMember> roster;

  /// When true, [loadShopStaff] throws (roster outage), exercising the
  /// "a roster hiccup never blocks authorization" fallback.
  bool rosterThrows;

  /// Result of [deleteStaffProfile]. False simulates the cloud refusing the
  /// delete, which must leave the local mirror untouched.
  final bool deleteStaffResult;

  /// Every auth user id handed to [deleteStaffProfile] (in call order).
  final List<String> deletedAuthUserIds = [];

  /// Every shop id handed to [deleteStaffProfile] (in call order).
  final List<String> deletedShopIds = [];

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
    if (rosterThrows) throw Exception('roster unavailable');
    return roster;
  }

  @override
  Future<bool> deleteStaffProfile({
    required String authUserId,
    required String shopId,
  }) async {
    deletedAuthUserIds.add(authUserId);
    deletedShopIds.add(shopId);
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
