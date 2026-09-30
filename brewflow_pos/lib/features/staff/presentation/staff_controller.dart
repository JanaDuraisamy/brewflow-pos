import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
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

/// The staff roster for the owner-facing Staff Attendance selector. Loads
/// through the same repository as the staff page, so a hire shows up here
/// too. STAFF rows only; the owner is never part of the attendance roster.
final staffRosterProvider = FutureProvider<List<UserProfile>>((ref) {
  return ref.watch(staffRepositoryProvider).staffMembers();
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
    // Profile resolution decides the operator's role, shop and grants, and
    // every permission check in the app is downstream of it. `source` records
    // which branch produced the profile, which is what makes "the menu is
    // wrong" explainable: local, mirrored-from-cloud, claimed-from-cloud, or
    // first-device-ownership.
    AppTrace.event('authz.resolve', {
      'userRef': AppTrace.userRef(authUser.id),
      'status': 'begin',
    });
    try {
      final resolver = ref.read(cloudShopResolverProvider);

      // Step 1: Try local profile (fast path — already bootstrapped).
      final existing = await repository.profileForAuthUser(authUser.id);
      if (existing != null) {
        if (!existing.isActive) {
          AppTrace.warn('authz.resolve', {
            'userRef': AppTrace.userRef(authUser.id),
            'source': 'local',
            'outcome': 'inactive_profile',
          });
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
              // A device bound to a shop the cloud does not agree with ends up
              // holding membership for the wrong business; this is the branch
              // that repairs it, so it is worth a line of its own.
              AppTrace.warn('authz.shop_migrated', {
                'userRef': AppTrace.userRef(authUser.id),
                'fromShopRef': AppTrace.userRef(existing.shopId),
                'toShopRef': AppTrace.userRef(cloudProfile.shopId),
              });
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

            // Cloud-authoritative grants: when the owner pushed a confirmed
            // grant set (non-empty) from another device, the local copy is
            // stale — mirror it so navigation reflects the owner's actual
            // grants. An empty cloud set means "never pushed yet", so the
            // local set is kept (pre-0020 installs keep working).
            if (existing.role == UserRole.staff &&
                cloudProfile.permissions.isNotEmpty &&
                !_sameGrants(existing.permissions, cloudProfile.permissions)) {
              // Grant changes are permission-sensitive: they silently change
              // what this staff member can do, so the resulting grant set is
              // recorded (the count and the permission names, never the user).
              AppTrace.event('authz.grants_mirrored', {
                'userRef': AppTrace.userRef(existing.id),
                'role': existing.role.name,
                'grants': cloudProfile.permissions.length,
                'permissions': _grantNames(cloudProfile.permissions),
              });
              AppLog.info(
                'Cloud permission grants changed: userId=${existing.id} — '
                'mirroring ${cloudProfile.permissions.length} grants',
                tag: tag,
              );
              await repository.setPermissions(
                existing.id,
                cloudProfile.permissions,
              );
              return await repository.profileForAuthUser(authUser.id);
            }
          }
        } catch (_) {
          // Cloud unavailable — proceed with local profile. Migration
          // will happen on the next successful connectivity check.
        }

        // Step 1b: the OWNER mirrors the cloud roster so staff created from
        // another device appear on this one. Best-effort — a roster hiccup
        // must never block authorization.
        await _backfillStaffRoster(resolver, repository, existing);

        AppTrace.event('authz.resolve', {
          'userRef': AppTrace.userRef(authUser.id),
          'source': 'local',
          'role': existing.role.name,
          'shopRef': AppTrace.userRef(existing.shopId),
          'grants': existing.permissions.length,
        });
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
        // Create local user profile linked to the cloud shop. The cloud role
        // is authoritative — a STAFF account must NEVER be locally promoted
        // to OWNER. Pass the cloud role AND the cloud-confirmed grant set so
        // the local profile mirrors what the owner actually granted.
        final cloudRole =
            UserRole.fromDbValue(cloudProfile.role) ?? UserRole.staff;
        final claimed = await repository.claimOwnershipForCloud(
          authUser,
          shopId: shop.id,
          role: cloudRole,
          permissions: cloudProfile.permissions,
        );
        await _backfillStaffRoster(resolver, repository, claimed);
        // Second device joining an existing shop: the role came from the cloud
        // and is authoritative, so it is recorded here — a device that came up
        // as STAFF here can never be the reason a later OWNER-only action is
        // denied.
        AppTrace.event('authz.resolve', {
          'userRef': AppTrace.userRef(authUser.id),
          'source': 'cloud_claim',
          'role': claimed.role.name,
          'shopRef': AppTrace.userRef(claimed.shopId),
          'grants': claimed.permissions.length,
        });
        return claimed;
      }

      // Step 3: First device ever — claim ownership locally.
      final profile = await repository.claimOwnership(authUser);
      // The cloud identity push is performed durably by the sync session
      // controller (retried on connectivity restore and app restart). It is
      // no longer a fire-and-forget here, so a failed bootstrap cannot
      // permanently orphan the shop.
      AppTrace.event('authz.resolve', {
        'userRef': AppTrace.userRef(authUser.id),
        'source': 'first_device_ownership',
        'role': profile.role.name,
        'shopRef': AppTrace.userRef(profile.shopId),
        'grants': profile.permissions.length,
      });
      return profile;
    } on StaffFailure catch (failure) {
      AppTrace.warn('authz.resolve_fail', {
        'failure': failure.runtimeType.toString(),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppTrace.fail('authz.resolve_fail', error, stackTrace);
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

  /// Mirrors the cloud `user_profiles` rosters for every shop this OWNER
  /// manages into the local database, starting with the primary shop. The
  /// owner's staff page reads the local roster, so staff added from another
  /// device — under EITHER business — must appear on this one.
  ///
  /// The primary shop is always included even when the managed-shop lookup
  /// fails, so a cloud hiccup degrades to the previous single-shop behaviour
  /// instead of leaving the roster empty.
  ///
  /// Rows are matched by auth user id and never re-type an existing OWNER.
  /// Because the local schema binds a profile to exactly ONE shop, a member who
  /// is staff in several businesses is mirrored under the first shop processed
  /// (the primary) and left alone afterwards — re-pointing their `shop_id` on
  /// every login would silently move their authorization between businesses.
  ///
  /// All failures are swallowed, per shop, so one unreachable business cannot
  /// block the others; the roster can always be re-pulled on the next login.
  Future<void> _backfillStaffRoster(
    CloudShopResolver resolver,
    StaffRepository repository,
    UserProfile profile,
  ) async {
    if (!profile.isOwner || profile.shopId == null) return;
    final primaryShopId = profile.shopId!;

    // Primary first: it is the business this device boots into, and processing
    // it first makes the local `shop_id` binding for shared members stable.
    final targets = <({String shopId, String name})>[
      (shopId: primaryShopId, name: 'Cafe'),
    ];
    try {
      for (final shop in await resolver.listManagedShops()) {
        if (shop.shopId == primaryShopId) continue;
        if (targets.any((target) => target.shopId == shop.shopId)) continue;
        targets.add((shopId: shop.shopId, name: shop.shopName));
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'Managed-shop lookup failed; mirroring the primary shop only',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }

    for (final target in targets) {
      try {
        // A secondary business may have no local row yet (recovered id, or a
        // second device), and the roster upsert needs one to attach to.
        await repository.ensureShopWithId(target.shopId, name: target.name);
        final roster = await resolver.loadShopStaff(target.shopId);
        for (final member in roster) {
          // The owner's own row (and any OTHER cloud OWNER row) is never
          // re-typed locally as STAFF by a roster pull.
          if (member.authUserId == profile.authUserId ||
              member.role == 'OWNER') {
            continue;
          }
          final existing = await repository.profileForAuthUser(
            member.authUserId,
          );
          if (existing != null && existing.shopId != target.shopId) {
            AppLog.info(
              'Shared staff already bound to another business; keeping it '
              '(user=${member.authUserId} '
              'local=${existing.shopId} cloud=${target.shopId})',
              tag: tag,
            );
            continue;
          }
          await repository.upsertStaffProfile(
            authUserId: member.authUserId,
            email: member.email,
            shopId: target.shopId,
            isActive: member.isActive,
            permissions: member.permissions,
            displayName: member.displayName,
          );
        }
      } catch (error, stackTrace) {
        AppLog.warning(
          'Cloud roster sync skipped for shop=${target.shopId}',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }
}

/// True when two grant sets contain exactly the same permissions.
bool _sameGrants(Set<Permission> a, Set<Permission> b) =>
    a.length == b.length && a.containsAll(b);

/// Permission names in a stable order, for the `authz.grants_mirrored` trace.
///
/// A grant set is a capability list, not personal data, so printing the names
/// is what makes "the owner revoked billing from this tablet" answerable
/// without guessing from a count.
String _grantNames(Set<Permission> permissions) {
  final names = permissions.map((p) => p.name).toList()..sort();
  return names.join('+');
}

/// Owner-only removal of a staff member, cloud-first.
///
/// Lives in a controller rather than the page so the owner boundary is enforced
/// against a real [Ref] (a `WidgetRef` cannot be used by [requireOwner]) — the
/// Staff page only hides the action, which is never the only guard.
final staffDeletionProvider = NotifierProvider<StaffDeletionController, void>(
  StaffDeletionController.new,
);

final class StaffDeletionController extends Notifier<void> {
  static const String tag = 'StaffDelete';

  @override
  void build() {}

  /// Deletes [member]'s cloud master plus its cross-device tombstone, then
  /// archives the local mirror. Throws [PermissionDeniedFailure] for a
  /// non-owner session and [StaffDeleteCloudFailure] when the cloud refuses, in
  /// which case the local copy is deliberately left untouched so both mirrors
  /// keep agreeing.
  ///
  /// OWNER targets are refused locally before any cloud call; the server RPC
  /// refuses them again. The cloud call derives the target shop server-side,
  /// so a mismatched local shop id can never scope the deletion elsewhere.
  ///
  /// No attendance, salary or advance row is touched on either side.
  Future<void> delete(UserProfile member) async {
    requireOwner(ref);
    if (member.role != UserRole.staff) {
      AppTrace.warn('staff.delete', {
        'userRef': AppTrace.userRef(member.id),
        'role': member.role.name,
        'outcome': 'refused_non_staff',
      });
      AppLog.warning(
        'Refused local staff delete for a non-STAFF profile',
        tag: tag,
      );
      throw const StaffDeleteCloudFailure(
        'Owners cannot be removed as staff members.',
      );
    }
    final authUserId = member.authUserId;
    final shopId = member.shopId;
    if (authUserId == null || shopId == null) {
      AppTrace.warn('staff.delete', {
        'userRef': AppTrace.userRef(member.id),
        'outcome': 'no_cloud_identity',
      });
      throw const StaffDeleteCloudFailure(
        'This staff member has no cloud identity yet, so they cannot be '
        'removed yet.',
      );
    }
    final deleted = await ref
        .read(cloudShopResolverProvider)
        .deleteStaffProfile(authUserId: authUserId);
    if (!deleted) {
      AppTrace.warn('staff.delete', {
        'userRef': AppTrace.userRef(authUserId),
        'shopRef': AppTrace.userRef(shopId),
        'outcome': 'cloud_refused',
      });
      AppLog.warning(
        'Cloud staff delete failed; local mirror left untouched '
        '(user=$authUserId)',
        tag: tag,
      );
      throw const StaffDeleteCloudFailure();
    }
    await ref.read(staffRepositoryProvider).archiveStaffProfile(member.id);
    ref.invalidate(staffRosterProvider);
    AppTrace.event('staff.deleted', {
      'userRef': AppTrace.userRef(authUserId),
      'shopRef': AppTrace.userRef(shopId),
      'attendancePreserved': true,
    });
    AppLog.info(
      'Staff member removed: user=$authUserId shop=$shopId '
      '(history preserved)',
      tag: tag,
    );
  }
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
///
/// A denial is the one failure that is always worth a line: it means an
/// operator's granted set is not what the feature assumes, and that is
/// invisible from the UI (the button is simply absent). The refused
/// permission plus the session's role and grant count is the whole diagnosis,
/// and the surrounding trace line names the attempted operation.
void requirePermission(Ref ref, Permission permission) {
  final authorization = ref.read(authorizationProvider);
  if (authorization is RoleBasedAuthorization &&
      !authorization.canForSession(permission)) {
    final profile = ref.read(userProfileProvider).value;
    AppTrace.warn('authz.denied', {
      'permission': permission.name,
      'reason': 'missing_permission',
      'role': profile?.role.name,
      'shopRef': AppTrace.userRef(profile?.shopId),
      'grants': profile?.permissions.length,
    });
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
    AppTrace.warn('authz.denied', {
      'permission': 'ownerOnly',
      'reason': 'not_owner',
      'role': profile.role.name,
      'shopRef': AppTrace.userRef(profile.shopId),
    });
    throw PermissionDeniedFailure();
  }
}
