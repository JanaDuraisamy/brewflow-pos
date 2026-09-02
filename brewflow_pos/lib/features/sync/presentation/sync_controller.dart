import 'dart:async';

import 'package:brewflow_pos/core/identity/device_identity.dart'
    show deviceIdProvider;
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart'
    show ConnectivitySnapshot, ConnectivityStatus;
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart' as auth;
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/data/device_registration_coordinator.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_invalidation.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/supabase_master_data_gateway.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_gateway.dart';
import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';
import 'sync_status_provider.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Session (Riverpod)
///
/// Relationship enforced here (never merged):
///
///   DEVICE (installation uuid)   ← DeviceIdentity / devices table
///   USER   (supabase auth uid)   ← auth session
///   SHOP   (shops.id)            ← resolved from the user's profile
///   ROLE/PERMISSIONS             ← user-based (Step-2), never device-based
///
/// [SyncSessionController] owns the per-session lifecycle:
///   authenticated profile resolves → register THIS device (local first,
///   cloud best-effort, retried whenever connectivity returns) → later Phase
///   6 stages hang the sync engine off the same lifecycle.
///
/// The same OWNER account may register any number of devices; nothing here
/// ever derives permissions from the device.
/// ---------------------------------------------------------------------------

/// Cloud boundary for device rows + master data; override in tests with an
/// in-memory fake.
final syncGatewayProvider = Provider<RemoteMasterDataGateway>((ref) {
  return SupabaseMasterDataGateway(Supabase.instance.client);
});

/// Device-registration view of the same cloud boundary (Phase 6 foundation).
final remoteDeviceGatewayProvider = Provider<RemoteDeviceGateway>((ref) {
  return ref.watch(syncGatewayProvider);
});

/// Owns the local outbox/cursors/devices store for the app scope.
final syncRepositoryProvider = Provider<DriftSyncRepository>((ref) {
  return DriftSyncRepository(ref.watch(appDatabaseProvider));
});

/// Applies pulled cloud master data into local Drift (idempotent upserts).
final localMasterDataApplierProvider = Provider<LocalMasterDataApplier>((ref) {
  return LocalMasterDataApplier(ref.watch(appDatabaseProvider));
});

/// The push/pull engine for the app scope; reentrant cycles collapse inside.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    ref.watch(syncRepositoryProvider),
    ref.watch(syncGatewayProvider),
    ref.watch(localMasterDataApplierProvider),
  );
});

/// Registration coordinator bound to the app-scope repositories.
final deviceRegistrationCoordinatorProvider =
    Provider<DeviceRegistrationCoordinator>((ref) {
      return DeviceRegistrationCoordinator(
        syncRepository: ref.watch(syncRepositoryProvider),
        remoteGateway: ref.watch(remoteDeviceGatewayProvider),
      );
    });

/// Atomic business-write + outbox bridge handed to master-data repositories.
/// Context resolution degrades to null (plain local writes) whenever no
/// authenticated shop session exists — offline-first by construction.
///
/// Every successful enqueue schedules a FAST sync kickoff (debounced), so a
/// meaningful mutation pushes within seconds when online instead of waiting
/// for the periodic cycle. Offline, the outbox simply stays pending.
final syncOutboxCoordinatorProvider = Provider<SyncOutboxCoordinator>((ref) {
  final kick = ref.read(syncKickProvider);
  return SyncOutboxCoordinator(
    ref.watch(syncRepositoryProvider),
    () async {
      final profile = await ref.read(userProfileProvider.future);
      if (profile == null || !profile.isActive || profile.shopId == null) {
        return null;
      }
      final authUser = ref.read(authRepositoryProvider).currentUser;
      if (authUser == null) return null;
      final deviceId = await ref.read(deviceIdProvider.future);
      return SyncSessionContext(
        deviceId: deviceId,
        shopId: profile.shopId!,
        userId: authUser.id,
      );
    },
    onEnqueue: () {
      // Trigger fast-sync (debounced).
      kick();
      // Refresh the sync status indicator (debounced).
      try {
        ref.read(syncStatusProvider.notifier).notifyEnqueue();
      } catch (_) {
        // Provider may not be initialized in test scopes — ignore.
      }
    },
  );
});

/// Debounced fast-sync trigger. Mutations inside the window collapse into
/// ONE engine cycle; the engine additionally collapses overlapping cycles
/// itself (_running guard), so bursts never recurse, double-push or spin.
/// A cycle with an empty outbox is a cheap no-op push-wise. Timer-based —
/// prompt when online, not realtime.
final syncKickProvider = Provider<void Function()>((ref) {
  Timer? pending;
  ref.onDispose(() {
    pending?.cancel();
    pending = null;
  });
  return () {
    if (ref.read(syncSessionProvider).phase != SyncSessionPhase.active) {
      return;
    }
    pending?.cancel();
    pending = Timer(SyncSessionController.fastSyncDebounce, () async {
      try {
        if (ref.read(syncSessionProvider).phase != SyncSessionPhase.active) {
          return;
        }
        final profile = ref.read(userProfileProvider).value;
        if (profile == null || profile.shopId == null) return;
        final pendingCount = await ref
            .read(syncRepositoryProvider)
            .pendingOutboxCount();
        if (pendingCount == 0) return;
        final deviceId = await ref.read(deviceIdProvider.future);
        await ref
            .read(syncEngineProvider)
            .runCycle(deviceId: deviceId, shopId: profile.shopId!);
        invalidateDomainProviders(ref);
      } catch (error, stackTrace) {
        AppLog.warning(
          'Fast sync skipped',
          tag: 'Sync',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  };
});

/// Lifecycle phase of the sync session for the signed-in identity.
enum SyncSessionPhase {
  /// No active authenticated shop session (signed out / unprovisioned).
  idle,

  /// A session exists and device registration is being ensured.
  preparing,

  /// The session is registered at least locally; the cloud copy may still be
  /// pending while offline ([SyncSessionState.cloudConfirmed]).
  active,
}

@immutable
final class SyncSessionState {
  const SyncSessionState({
    required this.phase,
    this.cloudConfirmed = false,
    this.deviceId,
  });

  static const SyncSessionState idle = SyncSessionState(
    phase: SyncSessionPhase.idle,
  );

  final SyncSessionPhase phase;

  /// Whether the cloud devices row is confirmed stored (false = offline or
  /// rejected; retried automatically — never surfaced as a POS error).
  final bool cloudConfirmed;

  /// Installation id of the active session (diagnostics).
  final String? deviceId;

  @override
  bool operator ==(Object other) =>
      other is SyncSessionState &&
      other.phase == phase &&
      other.cloudConfirmed == cloudConfirmed &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(phase, cloudConfirmed, deviceId);
}

/// Application sync session; initialized once via the app root widget and
/// alive for the whole ProviderScope lifetime.
final syncSessionProvider =
    NotifierProvider<SyncSessionController, SyncSessionState>(
      SyncSessionController.new,
    );

/// Watches auth/profile/connectivity and keeps the device registered for the
/// whole signed-in lifetime, running sync cycles while active. Every failure
/// degrades into state — sync must never block or crash POS usage
/// (offline-first).
final class SyncSessionController extends Notifier<SyncSessionState> {
  static const String tag = 'Sync';

  /// Period between background sync cycles while a session is active.
  static const Duration cycleInterval = Duration(seconds: 30);

  /// Debounce window for mutation-triggered fast syncs (bursts of edits
  /// collapse into one cycle).
  static const Duration fastSyncDebounce = Duration(seconds: 2);

  StreamSubscription<ConnectivitySnapshot>? _connectivitySub;
  Timer? _cycleTimer;
  Timer? _fastCycleTimer;

  @override
  SyncSessionState build() {
    // Profile resolution drives everything: sign-in, provision, sign-out.
    ref.listen<AsyncValue<UserProfile?>>(
      userProfileProvider,
      (_, _) => _scheduleEnsure(),
    );
    ref.onDispose(() {
      _cancelConnectivityWatch();
      _cycleTimer?.cancel();
      _fastCycleTimer?.cancel();
    });

    // React to an already-resolved profile on first build as well.
    scheduleMicrotask(_ensure);

    return SyncSessionState.idle;
  }

  /// Connectivity is only monitored while something is actually pending —
  /// idle sessions (and signed-out test scopes) never construct or start
  /// the plugin-backed service.
  void _watchConnectivityWhilePending() {
    if (_connectivitySub != null) return;
    final service = ref.read(connectivityServiceProvider);
    unawaited(service.init());
    _connectivitySub = service.snapshots.listen((snapshot) {
      if (snapshot.status == ConnectivityStatus.online &&
          state.phase == SyncSessionPhase.active) {
        // Back online: retry a pending cloud registration AND immediately
        // drain whatever the outbox accumulated while offline.
        _scheduleEnsure();
        _scheduleFastCycle();
      }
    });
  }

  /// Connectivity-restore fast cycle (separate debounce from the
  /// mutation-triggered one; both collapse inside the engine).
  void _scheduleFastCycle() {
    _fastCycleTimer = Timer(SyncSessionController.fastSyncDebounce, () {
      if (state.phase != SyncSessionPhase.active) return;
      unawaited(
        _safeCycle(() async {
          final shopId = ref.read(userProfileProvider).value?.shopId;
          if (shopId == null) return;
          final deviceId = await ref.read(deviceIdProvider.future);
          await ref
              .read(syncEngineProvider)
              .runCycle(deviceId: deviceId, shopId: shopId);
          _refreshAfterSync();
        }),
      );
    });
  }

  void _cancelConnectivityWatch() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  void _startCycles(String shopId) {
    _stopCycles();
    Future<void> runOnce() async {
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref
          .read(syncEngineProvider)
          .runCycle(deviceId: deviceId, shopId: shopId);
      // Pulled rows land directly in Drift; every domain screen caches via
      // AsyncNotifier until invalidated, so a successful pull must refresh all
      // domain views in the running app (no restart).
      _refreshAfterSync();
    }

    // First cycle right away (drains anything queued since sign-in), then
    // periodic drains + connectivity-triggered catch-ups.
    unawaited(_safeCycle(runOnce));
    _cycleTimer = Timer.periodic(cycleInterval, (_) => _safeCycle(runOnce));
  }

  void _stopCycles() {
    _cycleTimer?.cancel();
    _cycleTimer = null;
    _fastCycleTimer?.cancel();
    _fastCycleTimer = null;
  }

  Future<void> _safeCycle(Future<void> Function() cycle) async {
    try {
      if (state.phase != SyncSessionPhase.active) return;
      await cycle();
      if (state.cloudConfirmed && state.phase != SyncSessionPhase.idle) {
        _cancelConnectivityWatch();
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'Sync cycle failed (will retry)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _scheduleEnsure() => scheduleMicrotask(_ensure);

  Future<void> _ensure() async {
    try {
      await _ensureGuarded();
    } catch (error, stackTrace) {
      AppLog.error(
        'Sync session update failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _ensureGuarded() async {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null || !profile.isActive || profile.shopId == null) {
      _stopCycles();
      _cancelConnectivityWatch();
      _setIfChanged(SyncSessionState.idle);
      return;
    }
    final authUser = ref.read(authRepositoryProvider).currentUser;
    if (authUser == null) {
      _stopCycles();
      _cancelConnectivityWatch();
      _setIfChanged(SyncSessionState.idle);
      return;
    }

    // F1/F2: resolve the authoritative cloud shop identity. Never trust the
    // local shop_id when a valid cloud identity exists — an orphaned local
    // shop (minted before the cloud bootstrap completed) must not be
    // propagated downstream into device registration, outbox revival or the
    // sync cycle.
    final resolver = ref.read(cloudShopResolverProvider);
    final staffRepository = ref.read(staffRepositoryProvider);
    String authoritativeShopId = profile.shopId!;
    try {
      final cloudProfile = await resolver.fetchProfile(authUser.id);
      if (cloudProfile != null && cloudProfile.isActive) {
        if (cloudProfile.shopId != authoritativeShopId) {
          final cloudShopPresent = await resolver.shopExists(
            cloudProfile.shopId,
          );
          if (cloudShopPresent) {
            // Migrate the local identity to the cloud-authoritative shop. This
            // only touches identity-scoped rows (users / devices / sync_outbox
            // / sync_state) — never transactional data.
            await staffRepository.migrateLocalShopId(
              authoritativeShopId,
              cloudProfile.shopId,
              cloudProfile.shopName,
            );
            authoritativeShopId = cloudProfile.shopId;
            AppLog.info(
              'Synced local shop identity to cloud authoritative '
              '$authoritativeShopId',
              tag: tag,
            );
            // Keep downstream outbox enqueues consistent for this session.
            ref.read(userProfileProvider.notifier).reload();
          }
        } else {
          // Cloud already matches local — it is authoritative.
          authoritativeShopId = cloudProfile.shopId;
        }
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'Cloud identity resolution skipped (retry on connectivity)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }

    final shopId = authoritativeShopId;
    final userId = authUser.id;
    if (state.phase == SyncSessionPhase.preparing) return;
    state = SyncSessionState(
      phase: SyncSessionPhase.preparing,
      deviceId: state.deviceId,
    );

    String deviceId;
    bool confirmed;
    bool identityOk = false;
    try {
      deviceId = await ref.read(deviceIdProvider.future);
      confirmed = await ref
          .read(deviceRegistrationCoordinatorProvider)
          .ensureRegistered(
            DeviceRegistration(
              deviceId: deviceId,
              shopId: shopId,
              userId: userId,
              platform: defaultTargetPlatform.name.toLowerCase(),
              isActive: true,
              lastSeenAt: DateTime.now().toUtc(),
            ),
          );

      // F3: durably ensure the cloud user_profiles/shops row for this shop is
      // present. pushIdentity is an idempotent upsert, so retrying on app
      // restart or connectivity restore can never create a duplicate identity.
      // A failed push is observed (logged) and retried via the connectivity
      // watcher below and on the next app start.
      identityOk = await _pushCloudIdentity(
        resolver,
        shopId: shopId,
        authUser: authUser,
      );
      if (!identityOk) {
        AppLog.warning('Cloud identity push pending retry', tag: tag);
      }
    } catch (error, stackTrace) {
      AppLog.error(
        'Local device registration failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      state = SyncSessionState(
        phase: SyncSessionPhase.active,
        deviceId: state.deviceId,
      );
      return;
    }

    // A sign-out/profile switch during registration must not win the race:
    // only commit when the same identity triple is still in charge.
    final currentProfile = ref.read(userProfileProvider).value;
    final currentUser = ref.read(authRepositoryProvider).currentUser;
    if (currentProfile == null ||
        currentProfile.shopId != shopId ||
        currentUser?.id != userId) {
      return;
    }

    state = SyncSessionState(
      phase: SyncSessionPhase.active,
      cloudConfirmed: confirmed,
      deviceId: deviceId,
    );

    // F2: revive FAILED outbox entries using the authoritative cloud shop_id
    // (never the stale orphan local id). reviveFailedEntries re-stamps the
    // outbox row AND the JSON payload shopId, then resets FAILED → PENDING.
    try {
      final revived = await ref
          .read(syncRepositoryProvider)
          .reviveFailedEntries(shopId);
      if (revived > 0) {
        AppLog.info(
          'Revived $revived FAILED outbox entries with shop $shopId',
          tag: tag,
        );
      }
    } catch (error) {
      AppLog.warning('Failed entry revival skipped', tag: tag, error: error);
    }

    // Keep watching connectivity while anything is still pending: a failed
    // cloud identity push (even with a confirmed device registration) must be
    // retried when connectivity returns. Only stop watching once BOTH the
    // device registration and the identity push are confirmed.
    if (confirmed && identityOk) {
      _cancelConnectivityWatch();
      _startCycles(shopId);
    } else {
      _watchConnectivityWhilePending();
      // Still run cycles: pushes/pulls can work whenever the network is up
      // even if the devices row has not landed yet.
      _startCycles(shopId);
    }
  }

  /// F3: durable, idempotent cloud identity bootstrap.
  ///
  /// [CloudShopResolver.pushIdentity] upserts by `auth_user_id`, so re-calling
  /// it on app restart or connectivity restore cannot create a duplicate
  /// profile/shop. A failed push is observed and retried by:
  ///   - the connectivity watcher (offline → online), and
  ///   - the next app start (this method runs from [build]/profile changes).
  /// No second timer or sync engine is introduced.
  Future<bool> _pushCloudIdentity(
    CloudShopResolver resolver, {
    required String shopId,
    required auth.AuthUser authUser,
  }) async {
    try {
      final ok = await resolver.pushIdentity(
        shopId: shopId,
        shopName: 'My Shop',
        authUserId: authUser.id,
        email: authUser.email,
      );
      if (!ok) _watchConnectivityWhilePending();
      return ok;
    } catch (_) {
      _watchConnectivityWhilePending();
      return false;
    }
  }

  void _setIfChanged(SyncSessionState next) {
    if (state == next) return;
    state = next;
  }

  /// Refreshes every domain view after a successful sync cycle so that
  /// pulled rows become visible while the app is running (foreground sync).
  /// Best-effort: never breaks the cycle when a provider scope is not
  /// initialized (e.g. bare test scopes).
  void _refreshAfterSync() {
    invalidateDomainProviders(ref);
  }
}
