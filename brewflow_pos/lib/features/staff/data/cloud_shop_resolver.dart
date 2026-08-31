import 'package:brewflow_pos/core/services/app_log.dart';
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
  });

  final String shopId;
  final String shopName;
  final String email;
  final String role;
  final bool isActive;
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
          .select('shop_id, email, role, is_active')
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
      );
    } catch (error) {
      AppLog.warning('Cloud profile fetch failed', tag: tag, error: error);
      return null;
    }
  }

  /// Pushes a new shop and owner profile to the cloud. Idempotent: re-pushes
  /// if the rows already exist (safe for concurrent first-boot races).
  ///
  /// Returns true when the cloud confirms the identity, false on network failure
  /// (caller should fall back to local-only mode and retry later).
  Future<bool> pushIdentity({
    required String shopId,
    required String shopName,
    required String authUserId,
    required String email,
  }) async {
    final client = _client;
    if (client == null) return false;
    try {
      // Upsert shop (idempotent by primary key).
      await client.from('shops').upsert({
        'id': shopId,
        'name': shopName,
      }, onConflict: 'id');

      // Upsert user profile (idempotent by primary key).
      await client.from('user_profiles').upsert({
        'auth_user_id': authUserId,
        'email': email,
        'role': 'OWNER',
        'shop_id': shopId,
        'is_active': true,
      }, onConflict: 'auth_user_id');

      AppLog.info(
        'Cloud identity pushed: shop=$shopId user=$authUserId',
        tag: tag,
      );
      return true;
    } catch (error) {
      AppLog.warning(
        'Cloud identity push failed (will retry on connectivity)',
        tag: tag,
        error: error,
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
}
