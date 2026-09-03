/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff/Authorization Repository Contract
///
/// The authoritative local store for profiles, roles, permissions and shop
/// scope (Drift). Identity stays with Supabase Auth; this boundary only ever
/// sees the resolved auth user id.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';

import 'staff_models.dart';

abstract interface class StaffRepository {
  /// The profile linked to [authUserId], or null when not provisioned yet.
  Future<UserProfile?> profileForAuthUser(String authUserId);

  /// One-time owner bootstrap: atomically creates the single shop row (when
  /// absent) and claims the OWNER role for [user]. Succeeds only when no
  /// owner exists; otherwise throws [OwnerAlreadyClaimedFailure].
  Future<UserProfile> claimOwnership(AuthUser user);

  /// Creates a local OWNER profile linked to an existing cloud [shopId].
  /// Idempotent: if a profile for this auth user already exists, returns it.
  Future<UserProfile> claimOwnershipForCloud(
    AuthUser user, {
    required String shopId,
  });

  /// All STAFF profiles for management UI, oldest first.
  ///
  /// When [shopId] is provided, only staff members of that shop are returned.
  /// When null, returns staff across all shops (for owner Combined view).
  Future<List<UserProfile>> staffMembers({String? shopId});

  /// Creates a local STAFF profile for an already-provisioned auth identity.
  /// Throws [DuplicateStaffEmailFailure] when the email is taken.
  Future<UserProfile> createStaffProfile({
    required AuthUser identity,
    required String shopId,
    Set<Permission> permissions = defaultStaffPermissions,
    String? displayName,
  });

  /// Applies a display-name / activation / permission update. Refuses to
  /// touch OWNER profiles (owner protection).
  Future<void> updateStaff(StaffUpdateInput input);

  /// Replaces the permission rows of one staff member atomically.
  Future<void> setPermissions(String userId, Set<Permission> permissions);

  /// The single local shop, creating it on first call during bootstrap.
  Future<Shop> ensureShop({String name = 'My Shop'});

  /// Ensures a local shop exists with the exact [id] (from the cloud).
  /// Creates it if absent; returns it unchanged if already present.
  Future<Shop> ensureShopWithId(String id, {String name = 'My Shop'});

  /// Migrates all local shop_id references from [oldShopId] to [newShopId].
  /// Called when a second device resolves to the cloud's authoritative shop.
  /// [newShopName] seeds the local shop row name when it must be created.
  Future<void> migrateLocalShopId(
    String oldShopId,
    String newShopId, [
    String? newShopName,
  ]);
}
