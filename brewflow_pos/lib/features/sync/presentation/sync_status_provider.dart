import 'dart:async';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_invalidation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Status Provider
///
/// Lightweight, UI-facing view of sync health: connectivity + outbox count.
/// Polls outbox count periodically and on every sync kick so the indicator
/// stays current without a Drift stream (the count query is trivially cheap).
/// ---------------------------------------------------------------------------

/// Snapshot of the sync health for the sidebar / dashboard indicator.
enum SyncStatusLevel {
  /// Signed out or no active session.
  idle,

  /// Online, outbox empty → all synced.
  synced,

  /// Online, outbox has pending entries.
  pending,

  /// Offline (data saved locally, will sync when back online).
  offline,

  /// Online but cloud registration not confirmed (will retry).
  unconfirmed,

  /// Actively syncing (push/pull in progress).
  syncing,

  /// Last manual or background sync failed.
  error,
}

/// Immutable, equality-safe snapshot for the UI.
class SyncStatusSnapshot {
  const SyncStatusSnapshot({
    required this.level,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.isSyncing = false,
    this.lastSyncAt,
    this.lastError,
  });

  final SyncStatusLevel level;
  final int pendingCount;
  final int failedCount;
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? lastError;

  @override
  bool operator ==(Object other) =>
      other is SyncStatusSnapshot &&
      other.level == level &&
      other.pendingCount == pendingCount &&
      other.failedCount == failedCount &&
      other.isSyncing == isSyncing &&
      other.lastSyncAt == lastSyncAt &&
      other.lastError == lastError;

  @override
  int get hashCode => Object.hash(
    level,
    pendingCount,
    failedCount,
    isSyncing,
    lastSyncAt,
    lastError,
  );
}

/// App-scope sync status; watches connectivity + outbox count. Rebuilds only
/// when the combined status actually changes.
final syncStatusProvider =
    NotifierProvider<SyncStatusController, SyncStatusSnapshot>(
      SyncStatusController.new,
    );

final class SyncStatusController extends Notifier<SyncStatusSnapshot> {
  StreamSubscription<ConnectivitySnapshot>? _connectivitySub;

  /// Debounce rapid kicks so we don't hammer the DB.
  Timer? _debounce;

  bool _manualSyncRunning = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  @override
  SyncStatusSnapshot build() {
    final session = ref.watch(syncSessionProvider);

    // Watch connectivity for real-time online/offline changes.
    // Initialisation is owned by connectivityServiceProvider — we only observe.
    final service = ref.watch(connectivityServiceProvider);

    // Cancel previous subscription on every rebuild.
    _connectivitySub?.cancel();
    _connectivitySub = null;

    // Clean up on dispose.
    ref.onDispose(() {
      _connectivitySub?.cancel();
      _connectivitySub = null;
      _debounce?.cancel();
      _debounce = null;
    });

    // When idle there is nothing to poll — skip subscription entirely.
    if (session.phase == SyncSessionPhase.idle) {
      return SyncStatusSnapshot(
        level: SyncStatusLevel.idle,
        isSyncing: _manualSyncRunning,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );
    }

    // Session is active (preparing or active) — observe connectivity changes
    // for real-time status updates.  Outbox count is also refreshed on every
    // mutation via [notifyEnqueue] (debounced).
    _connectivitySub = service.snapshots.listen((_) => _refresh());

    if (!session.cloudConfirmed) {
      return SyncStatusSnapshot(
        level: SyncStatusLevel.unconfirmed,
        isSyncing: _manualSyncRunning,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );
    }

    final serviceStatus = service.status;
    if (serviceStatus == ConnectivityStatus.disconnected) {
      return SyncStatusSnapshot(
        level: SyncStatusLevel.offline,
        isSyncing: _manualSyncRunning,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );
    }

    if (_manualSyncRunning) {
      return SyncStatusSnapshot(
        level: SyncStatusLevel.syncing,
        isSyncing: true,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      );
    }

    // Online — kick off an async count refresh.
    scheduleMicrotask(_refresh);
    return SyncStatusSnapshot(
      level: SyncStatusLevel.synced,
      lastSyncAt: _lastSyncAt,
      lastError: _lastError,
    );
  }

  /// Called by the sync outbox coordinator's [onEnqueue] callback (via
  /// [syncKickProvider]) to refresh the count after a mutation is queued.
  void notifyEnqueue() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  /// Manual “Sync now” — reuses the existing [SyncEngine], no second timer.
  /// Serializes concurrent calls, respects offline, and surfaces
  /// `syncing`/`synced`/`error`/`offline` via `SyncStatusSnapshot`.
  Future<void> syncNow() async {
    if (_manualSyncRunning) return;
    final session = ref.read(syncSessionProvider);
    if (session.phase == SyncSessionPhase.idle) return;

    final connectivity = ref.read(connectivityServiceProvider).status;
    if (connectivity == ConnectivityStatus.disconnected) {
      _lastError = null;
      _setIfChanged(
        SyncStatusSnapshot(
          level: SyncStatusLevel.offline,
          pendingCount: state.pendingCount,
          failedCount: state.failedCount,
          lastSyncAt: _lastSyncAt,
        ),
      );
      return;
    }

    _manualSyncRunning = true;
    _lastError = null;
    _setIfChanged(
      SyncStatusSnapshot(
        level: SyncStatusLevel.syncing,
        pendingCount: state.pendingCount,
        failedCount: state.failedCount,
        isSyncing: true,
        lastSyncAt: _lastSyncAt,
      ),
    );

    try {
      final deviceId = await ref.read(deviceIdProvider.future);
      String? shopId = ref.read(userProfileProvider).value?.shopId;
      if (shopId == null) {
        final state = await ref.read(syncRepositoryProvider).stateFor(deviceId);
        shopId = state?.shopId;
      }
      if (shopId == null || shopId.isEmpty) {
        throw StateError('No shop_id for manual sync');
      }
      await ref
          .read(syncEngineProvider)
          .runCycle(deviceId: deviceId, shopId: shopId);
      // Pulled cloud_image_paths + queued uploads/deletes are drained here.
      // Fire-and-forget so sync status is never gated on image I/O.
      unawaited(drainProductImages(ref));
      invalidateDomainProviders(ref);
      _lastSyncAt = DateTime.now().toUtc();
      _lastError = null;
      await _refresh();
      // _refresh will set level to synced/pending; ensure syncing flag cleared
      // and lastSyncAt preserved. Force a synced snapshot if still syncing.
      if (state.isSyncing) {
        _setIfChanged(
          SyncStatusSnapshot(
            level: state.pendingCount > 0
                ? SyncStatusLevel.pending
                : SyncStatusLevel.synced,
            pendingCount: state.pendingCount,
            failedCount: state.failedCount,
            lastSyncAt: _lastSyncAt,
          ),
        );
      }
    } catch (error) {
      _lastError = error.toString();
      _setIfChanged(
        SyncStatusSnapshot(
          level: SyncStatusLevel.error,
          pendingCount: state.pendingCount,
          failedCount: state.failedCount,
          isSyncing: false,
          lastSyncAt: _lastSyncAt,
          lastError: _lastError,
        ),
      );
    } finally {
      _manualSyncRunning = false;
      // Ensure the UI leaves syncing state even if _refresh hasn't yet run.
      if (state.isSyncing) {
        _setIfChanged(
          SyncStatusSnapshot(
            level: state.level == SyncStatusLevel.syncing
                ? SyncStatusLevel.synced
                : state.level,
            pendingCount: state.pendingCount,
            failedCount: state.failedCount,
            isSyncing: false,
            lastSyncAt: _lastSyncAt,
            lastError: _lastError,
          ),
        );
      }
    }
  }

  Future<void> _refresh() async {
    final session = ref.read(syncSessionProvider);
    if (session.phase == SyncSessionPhase.idle) {
      _setIfChanged(
        SyncStatusSnapshot(
          level: SyncStatusLevel.idle,
          isSyncing: _manualSyncRunning,
          lastSyncAt: _lastSyncAt,
          lastError: _lastError,
        ),
      );
      return;
    }

    final connectivity = ref.read(connectivityServiceProvider).status;
    final isOnline = connectivity == ConnectivityStatus.online;

    int pending = 0;
    int failed = 0;
    try {
      final repo = ref.read(syncRepositoryProvider);
      pending = await repo.pendingOutboxCount();
      failed = await repo.failedOutboxCount();
    } catch (_) {
      // DB read failure — degrade gracefully.
    }

    if (!session.cloudConfirmed) {
      _setIfChanged(
        SyncStatusSnapshot(
          level: SyncStatusLevel.unconfirmed,
          pendingCount: pending,
          failedCount: failed,
          isSyncing: _manualSyncRunning,
          lastSyncAt: _lastSyncAt,
          lastError: _lastError,
        ),
      );
      return;
    }

    if (!isOnline) {
      _setIfChanged(
        SyncStatusSnapshot(
          level: SyncStatusLevel.offline,
          pendingCount: pending,
          failedCount: failed,
          isSyncing: _manualSyncRunning,
          lastSyncAt: _lastSyncAt,
          lastError: _lastError,
        ),
      );
      return;
    }

    // If a manual sync is in progress, keep showing syncing regardless of
    // pending count — the manual flow controls the final synced/error state.
    if (_manualSyncRunning) return;

    _setIfChanged(
      SyncStatusSnapshot(
        level: pending > 0 ? SyncStatusLevel.pending : SyncStatusLevel.synced,
        pendingCount: pending,
        failedCount: failed,
        isSyncing: false,
        lastSyncAt: _lastSyncAt,
        lastError: _lastError,
      ),
    );
  }

  void _setIfChanged(SyncStatusSnapshot next) {
    if (state == next) return;
    state = next;
  }
}
