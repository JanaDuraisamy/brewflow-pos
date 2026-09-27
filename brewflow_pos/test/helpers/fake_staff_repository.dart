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

  /// Local row ids of members the owner deleted. The Drift implementation
  /// re-types these rows out of `'STAFF'` and keeps them only as foreign-key
  /// anchors, so the fake models the same thing as a set and filters the
  /// roster the same way [staffMembers] does.
  final Set<String> archivedProfileIds = {};

  Shop? shop;
  Object? claimError;

  /// Thrown by the archive paths when set, to exercise delete failures.
  Object? archiveError;

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
  Future<List<UserProfile>> staffMembers({String? shopId}) async {
    var staff = storedProfiles.where(
      (p) => p.role == UserRole.staff && !archivedProfileIds.contains(p.id),
    );
    if (shopId != null) {
      staff = staff.where((p) => p.shopId == shopId);
    }
    return [...staff];
  }

  @override
  Future<UserProfile> createStaffProfile({
    required AuthUser identity,
    required String shopId,
    Set<Permission> permissions = defaultStaffPermissions,
    String? displayName,
  }) async {
    if (storedProfiles.any(
      (p) =>
          p.email.toLowerCase() == identity.email.toLowerCase() &&
          p.shopId == shopId,
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
    required UserRole role,
    Set<Permission> permissions = const {},
  }) async {
    final existing = profilesByAuthId[user.id];
    if (existing != null) return existing;
    return _insert(
      email: user.email,
      authUserId: user.id,
      role: role,
      permissions: permissions,
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

  @override
  Future<UserProfile?> upsertStaffProfile({
    required String authUserId,
    required String email,
    required String shopId,
    required bool isActive,
    Set<Permission> permissions = const {},
    String? displayName,
  }) async {
    final existing = profilesByAuthId[authUserId];
    // OWNER rows are never re-typed by a cloud roster pull.
    if (existing != null && existing.role == UserRole.owner) return null;
    if (existing != null) {
      final updated = UserProfile(
        id: existing.id,
        email: existing.email,
        authUserId: existing.authUserId,
        shopId: shopId,
        displayName: displayName ?? existing.displayName,
        role: existing.role,
        isActive: isActive,
        permissions: permissions.isEmpty ? existing.permissions : permissions,
      );
      final index = storedProfiles.indexWhere((p) => p.id == existing.id);
      storedProfiles[index] = updated;
      profilesByAuthId[authUserId] = updated;
      return updated;
    }
    final created = _insert(
      email: email,
      authUserId: authUserId,
      role: UserRole.staff,
      permissions: permissions,
      displayName: displayName,
      shopId: shopId,
    );
    final index = storedProfiles.indexWhere((p) => p.id == created.id);
    storedProfiles[index] = UserProfile(
      id: created.id,
      email: created.email,
      authUserId: created.authUserId,
      shopId: created.shopId,
      displayName: created.displayName,
      role: created.role,
      isActive: isActive,
      permissions: created.permissions,
    );
    profilesByAuthId[authUserId] = storedProfiles[index];
    return storedProfiles[index];
  }

  @override
  Future<void> archiveStaffProfile(String localUserId) async {
    final error = archiveError;
    if (error != null) throw error;
    final index = storedProfiles.indexWhere((p) => p.id == localUserId);
    if (index == -1 || storedProfiles[index].role != UserRole.staff) {
      throw const ProfileNotProvisionedFailure();
    }
    final member = storedProfiles[index];
    archivedProfileIds.add(member.id);
    // Sign-in can no longer resolve the row: the auth link is released.
    if (member.authUserId != null) {
      profilesByAuthId.remove(member.authUserId);
    }
    storedProfiles[index] = UserProfile(
      id: member.id,
      email: archivedStaffEmail(member.id),
      authUserId: null,
      shopId: member.shopId,
      displayName: null,
      role: member.role,
      isActive: false,
      permissions: const {},
    );
  }

  @override
  Future<void> archiveStaffProfileByAuthUserId(String authUserId) async {
    final member = profilesByAuthId[authUserId];
    if (member == null) return;
    if (member.role != UserRole.staff) return;
    await archiveStaffProfile(member.id);
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
