import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Authorization State (Riverpod)
///
/// Resolution chain after Supabase Auth succeeds:
///   auth user id → local profile (users table) → role + permissions.
///
/// Owner bootstrap: the FIRST authenticated user on a fresh database claims
/// OWNER exactly once (transactional, blocked once any owner exists). Every
/// later authenticated user without a provisioned profile resolves to
/// "no access" until the owner adds them as staff — nobody silently becomes
/// owner. Inactive staff resolve to an explicit access-denied state.
///
/// Sign-out rebuilds this provider automatically (it watches the auth state),
/// so role/permissions are cleared together with the session.
/// ---------------------------------------------------------------------------

/// Owns the single staff/authorization repository for the app scope.
final staffRepositoryProvider = Provider<StaffRepository>((ref) {
  return DriftStaffRepository(ref.watch(appDatabaseProvider));
});

/// Resolves shop identity from the cloud before local bootstrap.
/// Returns a no-op resolver when Supabase is not initialized (tests).
final cloudShopResolverProvider = Provider<CloudShopResolver>((ref) {
  try {
    return CloudShopResolver(Supabase.instance.client);
  } catch (_) {
    return CloudShopResolver.nullable();
  }
});

/// Resolved profile for the signed-in identity; null while signed out or
/// unprovisioned. Errors carry [ProfileNotProvisionedFailure] /
/// [OwnerAlreadyClaimedFailure].
final userProfileProvider =
    AsyncNotifierProvider<UserProfileController, UserProfile?>(
      UserProfileController.new,
    );

final class UserProfileController extends AsyncNotifier<UserProfile?> {
  static const String tag = 'Authz';

  @override
  Future<UserProfile?> build() async {
    final auth = ref.watch(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) {
      return null;
    }
    final repository = ref.watch(staffRepositoryProvider);
    final authUser = ref.read(authRepositoryProvider).currentUser;
    if (authUser == null) {
      return null;
    }
    try {
      final resolver = ref.read(cloudShopResolverProvider);

      // Step 1: Try local profile (fast path — already bootstrapped).
      final existing = await repository.profileForAuthUser(authUser.id);
      if (existing != null) {
        if (!existing.isActive) {
          throw const ProfileNotProvisionedFailure.inactive();
        }

        // Best-effort cloud identity verification: if the cloud has a
        // different authoritative shop, migrate locally. This handles the
        // second-device case where the device already bootstrapped locally
        // with its own shop UUID before the cloud was populated.
        try {
          final cloudProfile = await resolver.fetchProfile(authUser.id);
          if (cloudProfile != null && cloudProfile.isActive) {
            // Do NOT trust the cloud profile blindly — confirm the
            // authoritative shop actually exists in the cloud before
            // migrating the local identity onto it. A cloud profile whose
            // shop is itself missing would otherwise orphan the device.
            final cloudShopPresent = await resolver.shopExists(
              cloudProfile.shopId,
            );
            if (existing.shopId != null &&
                existing.shopId != cloudProfile.shopId &&
                cloudShopPresent) {
              AppLog.info(
                'Cloud shop mismatch: local=${existing.shopId} '
                'cloud=${cloudProfile.shopId} — migrating',
                tag: tag,
              );
              await repository.migrateLocalShopId(
                existing.shopId!,
                cloudProfile.shopId,
                cloudProfile.shopName,
              );
              // Re-read profile with the updated shop_id.
              return await repository.profileForAuthUser(authUser.id);
            }
          }
        } catch (_) {
          // Cloud unavailable — proceed with local profile. Migration
          // will happen on the next successful connectivity check.
        }

        return existing;
      }

      // Step 2: Try cloud resolution (second device joining an existing shop).
      final cloudProfile = await resolver.fetchProfile(authUser.id);
      if (cloudProfile != null && cloudProfile.isActive) {
        // Ensure local shop matches the cloud's authoritative shop.
        final shop = await repository.ensureShopWithId(
          cloudProfile.shopId,
          name: cloudProfile.shopName,
        );
        // Create local user profile linked to the cloud shop.
        return await repository.claimOwnershipForCloud(
          authUser,
          shopId: shop.id,
        );
      }

      // Step 3: First device ever — claim ownership locally.
      final profile = await repository.claimOwnership(authUser);
      // The cloud identity push is performed durably by the sync session
      // controller (retried on connectivity restore and app restart). It is
      // no longer a fire-and-forget here, so a failed bootstrap cannot
      // permanently orphan the shop.
      return profile;
    } on StaffFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Authorization store unavailable',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedAuthFailure();
    }
  }

  /// Refreshes after owner-side staff/profile mutations.
  void reload() => ref.invalidateSelf();
}

/// Centralized authorization for the whole app: widgets, controllers and
/// repositories all ask this one service.
final authorizationProvider = Provider<AuthorizationService>((ref) {
  final profile = ref.watch(userProfileProvider).value;
  return RoleBasedAuthorization(
    role: profile?.role,
    grantedPermissions: profile?.permissions ?? const {},
  );
});

/// Convenience question used across features:
/// `ref.read(canProvider(Permission.billing))`.
final canProvider = Provider.family<bool, Permission>((ref, permission) {
  return ref.watch(authorizationProvider).can(permission);
});

/// Business-operation boundary guard. Throws [PermissionDeniedFailure] when
/// a resolved session lacks [permission]. Controllers call this at the top
/// of sensitive mutations so hiding UI is never the only protection.
void requirePermission(Ref ref, Permission permission) {
  final authorization = ref.read(authorizationProvider);
  if (authorization is RoleBasedAuthorization &&
      !authorization.canForSession(permission)) {
    throw PermissionDeniedFailure();
  }
}

/// Owner-only boundary guard for destructive deletions. Throws
/// [PermissionDeniedFailure] unless the signed-in profile is the Owner. A
/// missing profile (pure unit/service contexts) is allowed — those contexts
/// never come from a signed-in device session.
void requireOwner(Ref ref) {
  final profile = ref.read(userProfileProvider).value;
  if (profile != null && !profile.isOwner) {
    throw PermissionDeniedFailure();
  }
}
