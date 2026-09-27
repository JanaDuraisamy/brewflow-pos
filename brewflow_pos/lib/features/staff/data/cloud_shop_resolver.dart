import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Cloud Shop Identity Resolver
///
/// Resolves the authoritative shop identity from the cloud BEFORE local
/// bootstrap, preventing the per-device shop UUID defect where each
/// installation mints its own shop.
///
/// Flow:
///   1. Query cloud `user_profiles` by auth user id
///   2. If found → the cloud shop_id is authoritative
///   3. If not found → this is the first device → create shop + profile in cloud
///
/// The cloud `shops` and `user_profiles` tables intentionally have NO RLS
/// policies (identity tables, not business data) so any authenticated user
/// can bootstrap.
/// ---------------------------------------------------------------------------

/// Lightweight cloud-side profile used only during bootstrap resolution.
final class CloudUserProfile {
  const CloudUserProfile({
    required this.shopId,
    required this.shopName,
    required this.email,
    required this.role,
    required this.isActive,
    this.permissions = const {},
  });

  final String shopId;
  final String shopName;
  final String email;
  final String role;
  final bool isActive;

  /// Owner-confirmed fine-grained grants, cloud-authoritative for STAFF.
  /// Meaningful only for [UserRole.staff]; owners are implied-all.
  final Set<Permission> permissions;
}

/// One cloud `user_profiles` row for a given shop, used by the owner roster
/// backfill so staff created on another device appear locally.
final class CloudStaffMember {
  const CloudStaffMember({
    required this.authUserId,
    required this.email,
    required this.role,
    required this.isActive,
    this.displayName,
    this.permissions = const {},
  });

  final String authUserId;
  final String email;

  /// Raw cloud db value ('OWNER' | 'STAFF').
  final String role;
  final bool isActive;
  final String? displayName;

  /// Cloud-authoritative grants; empty means "owner never pushed yet".
  final Set<Permission> permissions;
}

class CloudShopResolver {
  CloudShopResolver([this._client]);

  /// Creates a no-op resolver for test/dev environments where Supabase is
  /// not initialized. All queries return null (offline-first degradation).
  CloudShopResolver.nullable() : _client = null;

  static const String tag = 'CloudShop';
  final SupabaseClient? _client;

  /// Queries the cloud `user_profiles` table for the given [authUserId].
  /// Returns the authoritative cloud profile when it exists, null otherwise.
  Future<CloudUserProfile?> fetchProfile(String authUserId) async {
    final client = _client;
    if (client == null) return null;
    try {
      final data = await client
          .from('user_profiles')
          .select('shop_id, email, role, is_active, permissions')
          .eq('auth_user_id', authUserId)
          .maybeSingle();
      if (data == null) return null;

      final shopId = data['shop_id'] as String?;
      if (shopId == null || shopId.isEmpty) return null;

      // Resolve the shop name from the shops table.
      String shopName;
      try {
        final shopRow = await client
            .from('shops')
            .select('name')
            .eq('id', shopId)
            .maybeSingle();
        shopName = (shopRow?['name'] as String?) ?? 'My Shop';
      } catch (_) {
        shopName = 'My Shop';
      }

      return CloudUserProfile(
        shopId: shopId,
        shopName: shopName,
        email: data['email'] as String,
        role: data['role'] as String,
        isActive: data['is_active'] as bool,
        permissions: _parsePermissions(data['permissions']),
      );
    } catch (error) {
      AppLog.warning('Cloud profile fetch failed', tag: tag, error: error);
      return null;
    }
  }

  /// Parses the cloud `permissions text[]` column into the typed grant set,
  /// dropping unknown tokens (defensive against schema drift).
  static Set<Permission> _parsePermissions(Object? raw) {
    if (raw is! List) return const {};
    final parsed = <Permission>{};
    for (final entry in raw) {
      if (entry is! String) continue;
      final permission = Permission.fromDbValue(entry);
      if (permission != null) parsed.add(permission);
    }
    return parsed;
  }

  /// Loads every cloud `user_profiles` row belonging to [shopId].
  ///
  /// Used by the signed-in OWNER to mirror the authoritative roster on this
  /// device (staff added from another device otherwise stay invisible until
  /// re-created locally). Best-effort: returns an empty roster when Supabase
  /// is not initialized or the query fails.
  Future<List<CloudStaffMember>> loadShopStaff(String shopId) async {
    final client = _client;
    if (client == null) return const [];
    try {
      final data = await client
          .from('user_profiles')
          .select(
            'auth_user_id, email, role, is_active, display_name, permissions',
          )
          .eq('shop_id', shopId);
      return [
        for (final row in data)
          CloudStaffMember(
            authUserId: row['auth_user_id'] as String,
            email: (row['email'] as String?) ?? '',
            role: (row['role'] as String?) ?? 'STAFF',
            isActive: row['is_active'] as bool? ?? true,
            displayName: row['display_name'] as String?,
            permissions: _parsePermissions(row['permissions']),
          ),
      ];
    } catch (error) {
      AppLog.warning(
        'Cloud staff roster fetch failed (local roster unchanged)',
        tag: tag,
        error: error,
      );
      return const [];
    }
  }

  /// Pushes a shop, owner profile and — critically — the caller's OWNER
  /// `user_shop_memberships` row to the cloud in ONE server-side call
  /// (migration 0013 `bootstrap_owner_membership`). The membership row is what
  /// every `is_shop_member(shop_id)`-gated RPC (checkout, void, purchases,
  /// receipts) and the create-staff boundary authorize against; without it the
  /// cloud rejects every OWNER write with FORBIDDEN. Idempotent: re-pushes are
  /// safe (replays mint no duplicates), which keeps first-boot races safe.
  ///
  /// Returns true when the cloud confirms the identity, false on network
  /// failure or rejection (caller should retry on connectivity).
  Future<bool> pushIdentity({
    required String shopId,
    required String shopName,
    required String authUserId,
    required String email,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      final success = await client.rpc<bool>(
        'bootstrap_owner_membership',
        params: {
          'p_shop_id': shopId,
          'p_shop_name': shopName,
          'p_email': email,
        },
      );
      if (success) {
        AppLog.info(
          'Cloud identity pushed: shop=$shopId user=$authUserId',
          tag: tag,
        );
      }
      return success;
    } catch (error) {
      AppLog.warning(
        'Cloud identity push failed (will retry on connectivity)',
        tag: tag,
        error: error,
      );
      return false;
    }
  }

  /// Persists [permissions] as the cloud-authoritative grant set for the STAFF
  /// account [authUserId] via the owner-verified `set_staff_permissions` RPC
  /// (migration 0020). The RPC itself authorizes the caller as an active OWNER
  /// of the target's shop, so a staff caller is rejected server-side.
  ///
  /// Best-effort like [pushIdentity]: returns false on offline/rejection and
  /// the caller logs; the local device keeps working offline-first.
  Future<bool> pushStaffPermissions({
    required String authUserId,
    required Set<Permission> permissions,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      await client.rpc<void>(
        'set_staff_permissions',
        params: {
          'p_auth_user_id': authUserId,
          'p_permissions': [
            for (final permission in permissions) permission.dbValue,
          ],
        },
      );
      AppLog.info(
        'Cloud staff permissions pushed: user=$authUserId '
        'count=${permissions.length}',
        tag: tag,
      );
      return true;
    } catch (error) {
      AppLog.warning(
        'Cloud staff permission push failed (owner device will retry)',
        tag: tag,
        error: error,
      );
      return false;
    }
  }

  /// Owner-only removal of one staff member's cloud master record.
  ///
  /// Deletes the `user_profiles` row, then writes a `STAFF_PROFILE` tombstone
  /// so every other device for the shop drops the member from its roster too.
  /// The tombstone is required: a deleted row can never appear in a row-scan
  /// delta query, so without it peers would keep the member forever.
  ///
  /// The tombstone id is the Supabase auth user id, which is what peers match
  /// their local `users.auth_user_id` on.
  ///
  /// Historical payroll is untouched: staff_attendance, staff_advances,
  /// staff_monthly_salaries and staff_daily_salaries all key staff by a plain
  /// `staff_user_id text` column with no foreign key to `user_profiles`, so
  /// removing the profile cannot cascade into (or invalidate) that history.
  ///
  /// The Supabase auth account is intentionally left in place — the person can
  /// still authenticate but resolves to no profile, so they cannot use the app,
  /// and their address stays reserved against a stale re-invite.
  ///
  /// Returns false when there is no cloud client or the delete was rejected;
  /// the caller must NOT drop the local row in that case, or the local mirror
  /// and the cloud would silently disagree.
  Future<bool> deleteStaffProfile({
    required String authUserId,
    required String shopId,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      // Owner protection: never let this path remove an OWNER profile.
      final target = await client
          .from('user_profiles')
          .select('role')
          .eq('auth_user_id', authUserId)
          .maybeSingle();
      if (target == null) return false;
      if (target['role'] == 'OWNER') {
        AppLog.warning(
          'Refused cloud staff delete for an OWNER profile',
          tag: tag,
        );
        return false;
      }
      await client
          .from('user_profiles')
          .delete()
          .eq('auth_user_id', authUserId);
      await client.from('master_deletions').upsert({
        'entity': MasterEntity.staffProfile.wire,
        'id': authUserId,
        'shop_id': shopId,
      }, onConflict: 'entity,id');
      AppLog.info(
        'Cloud staff profile deleted: user=$authUserId shop=$shopId',
        tag: tag,
      );
      return true;
    } catch (error, stackTrace) {
      AppLog.error(
        'Cloud staff profile delete failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Returns true when the cloud `shops` row with [shopId] exists.
  ///
  /// Used by the bootstrap flow to avoid migrating a local identity onto a
  /// shop that is itself orphaned/missing in the cloud.
  Future<bool> shopExists(String shopId) async {
    final client = _client;
    if (client == null) return false;
    try {
      final data = await client
          .from('shops')
          .select('id')
          .eq('id', shopId)
          .maybeSingle();
      return data != null;
    } catch (error) {
      AppLog.warning(
        'Cloud shop existence check failed',
        tag: tag,
        error: error,
      );
      return false;
    }
  }

  /// Live authorization probe (temporary diagnostics only).
  ///
  /// Calls the SAME SECURITY DEFINER gate that every cloud write enforces
  /// (`is_shop_member()`), so the returned value is exactly what
  /// create_sale_atomic / create-staff will see for [shopId]. Read-only.
  /// Returns null when the probe could not reach the cloud.
  Future<bool?> isShopMember(String shopId) async {
    final client = _client;
    if (client == null) return null;
    try {
      return await client.rpc<bool>(
        'is_shop_member',
        params: {'target_shop_id': shopId},
      );
    } catch (error) {
      AppLog.warning('is_shop_member probe failed', tag: tag, error: error);
      return null;
    }
  }
}
