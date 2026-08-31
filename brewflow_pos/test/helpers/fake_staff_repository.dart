import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_repository.dart';

/// In-memory [StaffRepository] for controller/UI authorization tests.
///
/// Mirrors the Drift semantics that matter to state: one shop, one-time owner
/// claim, per-auth-id profile lookup, duplicate-email rejection and
/// owner-protected updates.
final class FakeStaffRepository implements StaffRepository {
  final Map<String, UserProfile> profilesByAuthId = {};
  final List<UserProfile> storedProfiles = [];

  Shop? shop;
  Object? claimError;

  int _sequence = 0;

  @override
  Future<UserProfile?> profileForAuthUser(String authUserId) async =>
      profilesByAuthId[authUserId];

  @override
  Future<UserProfile> claimOwnership(AuthUser user) async {
    final error = claimError;
    if (error != null) throw error;
    if (storedProfiles.any((p) => p.role == UserRole.owner)) {
      throw const OwnerAlreadyClaimedFailure();
    }
    final shopId = (await ensureShop()).id;
    return _insert(
      email: user.email,
      authUserId: user.id,
      role: UserRole.owner,
      shopId: shopId,
    );
  }

  @override
  Future<List<UserProfile>> staffMembers() async => [
    ...storedProfiles.where((p) => p.role == UserRole.staff),
  ];

  @override
  Future<UserProfile> createStaffProfile({
    required AuthUser identity,
    required String shopId,
    Set<Permission> permissions = defaultStaffPermissions,
    String? displayName,
  }) async {
    if (storedProfiles.any(
      (p) => p.email.toLowerCase() == identity.email.toLowerCase(),
    )) {
      throw const DuplicateStaffEmailFailure();
    }
    return _insert(
      email: identity.email,
      authUserId: identity.id,
      role: UserRole.staff,
      permissions: permissions,
      displayName: displayName,
      shopId: shopId,
    );
  }

  @override
  Future<void> updateStaff(StaffUpdateInput input) async {
    final index = storedProfiles.indexWhere((p) => p.id == input.id);
    if (index == -1 || storedProfiles[index].role != UserRole.staff) {
      throw const ProfileNotProvisionedFailure();
    }
    final member = storedProfiles[index];
    storedProfiles[index] = UserProfile(
      id: member.id,
      email: member.email,
      authUserId: member.authUserId,
      shopId: member.shopId,
      displayName: input.displayName ?? member.displayName,
      role: member.role,
      isActive: input.isActive ?? member.isActive,
      permissions: input.permissions ?? member.permissions,
    );
  }

  @override
  Future<void> setPermissions(String userId, Set<Permission> permissions) =>
      updateStaff(StaffUpdateInput(id: userId, permissions: permissions));

  @override
  Future<Shop> ensureShop({String name = 'My Shop'}) async {
    shop ??= Shop(id: 'shop-1', name: name);
    return shop!;
  }

  @override
  Future<Shop> ensureShopWithId(String id, {String name = 'My Shop'}) async {
    shop = Shop(id: id, name: name);
    return shop!;
  }

  @override
  Future<UserProfile> claimOwnershipForCloud(
    AuthUser user, {
    required String shopId,
  }) async {
    final existing = profilesByAuthId[user.id];
    if (existing != null) return existing;
    return _insert(
      email: user.email,
      authUserId: user.id,
      role: UserRole.owner,
      shopId: shopId,
    );
  }

  @override
  Future<void> migrateLocalShopId(
    String oldShopId,
    String newShopId, [
    String? newShopName,
  ]) async {
    shop = Shop(id: newShopId, name: newShopName ?? shop?.name ?? 'My Shop');
  }

  UserProfile _insert({
    required String email,
    required String? authUserId,
    required UserRole role,
    required String? shopId,
    Set<Permission> permissions = const {},
    String? displayName,
  }) {
    final profile = UserProfile(
      id: 'profile-${++_sequence}',
      email: email,
      authUserId: authUserId,
      shopId: shopId,
      displayName: displayName,
      role: role,
      isActive: true,
      permissions: role == UserRole.owner ? const {} : permissions,
    );
    storedProfiles.add(profile);
    if (authUserId != null) {
      profilesByAuthId[authUserId] = profile;
    }
    return profile;
  }
}
