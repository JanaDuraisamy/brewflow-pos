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

  /// Creates a local profile linked to an existing cloud [shopId].
  /// Idempotent: if a profile for this auth user already exists, returns it.
  /// The [role] parameter reflects the cloud-side role; the caller must NOT
  /// supply [UserRole.owner] for a staff account.
  Future<UserProfile> claimOwnershipForCloud(
    AuthUser user, {
    required String shopId,
    required UserRole role,
    Set<Permission> permissions = const {},
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

  /// Best-effort cloud roster mirror: creates or refreshes a local STAFF
  /// profile for a cloud identity, matching by [authUserId].
  ///
  /// OWNER rows are never touched (returns null for them) — the cloud pull
  /// must never re-type an owner. When [permissions] is empty the existing
  /// local grant set is preserved, because an empty cloud set means the owner
  /// has not pushed grants yet. Returns the resulting local profile.
  Future<UserProfile?> upsertStaffProfile({
    required String authUserId,
    required String email,
    required String shopId,
    required bool isActive,
    Set<Permission> permissions = const {},
    String? displayName,
  });

  /// Archives a STAFF profile after the owner deleted them, by local row id.
  ///
  /// The row itself is deliberately RETAINED: staff_attendance,
  /// staff_daily_salaries, staff_monthly_salaries and staff_advances all
  /// reference `users.id` with `ON DELETE CASCADE` and `PRAGMA foreign_keys`
  /// is ON, so deleting the row would silently destroy the member's payroll
  /// history. Instead the row is re-typed with [kArchivedStaffRole], its
  /// permissions are dropped and `auth_user_id` is cleared, which removes the
  /// member from the roster, the Staff page and sign-in while every history row
  /// keeps pointing at it and stays attributed.
  ///
  /// Idempotent. OWNER profiles are refused — [ProfileNotProvisionedFailure] —
  /// exactly like the other staff write paths. Unknown ids are likewise
  /// refused. This touches NO attendance, salary or advance row.
  Future<void> archiveStaffProfile(String localUserId);

  /// [archiveStaffProfile] addressed by the Supabase auth user id, which is
  /// what a cross-device STAFF_PROFILE tombstone carries.
  Future<void> archiveStaffProfileByAuthUserId(String authUserId);
}
