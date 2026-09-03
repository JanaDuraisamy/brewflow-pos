import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/storage_cleanup_gateway.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Cloud gateway for storage monitoring/cleanup. Tests override with a fake;
/// production wires the Supabase edge-function client.
final storageCleanupGatewayProvider = Provider<StorageCleanupGateway>(
  (ref) => SupabaseStorageCleanupGateway(Supabase.instance.client.functions),
);

/// Local bookkeeping (notifications + per-shop cleanup state).
final storageCleanupRepositoryProvider =
    Provider<DriftStorageCleanupRepository>(
      (ref) => DriftStorageCleanupRepository(ref.watch(appDatabaseProvider)),
    );

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Storage Cleanup Controller
///
/// Owner-only surface for storage monitoring + monthly orphan cleanup.
///
/// Gating: every mutating/scanning action first resolves the signed-in profile
/// and refuses unless it is an active OWNER. Staff never reach the usage data:
/// the controller throws [StorageCleanupForbiddenFailure] and the UI behind
/// the owner-only route is never built for staff anyway.
///
/// Cleanup is strictly owner-confirmed: scan() NEVER deletes; the owner reviews
/// candidates and calls [deleteOrphans] with the explicit paths, which is the
/// only place permanent deletion happens.
/// ---------------------------------------------------------------------------

/// Snapshot of the storage-cleanup surface for the owner.
class StorageCleanupState {
  const StorageCleanupState({
    this.report,
    this.notification,
    this.lastCleanupAt,
    this.isScanning = false,
    this.isDeleting = false,
    this.lastError,
    this.busy = false,
  });

  /// Latest usage/scan report (null before the first scan).
  final StorageUsageReport? report;

  /// Active owner notification, if any.
  final StorageCleanupNotificationRecord? notification;

  final DateTime? lastCleanupAt;
  final bool isScanning;
  final bool isDeleting;
  final String? lastError;
  final bool busy;

  static const _unset = Object();

  StorageCleanupState copyWith({
    StorageUsageReport? report,
    Object? notification = _unset,
    DateTime? lastCleanupAt,
    bool? isScanning,
    bool? isDeleting,
    String? lastError,
    bool clearError = false,
    bool? busy,
  }) => StorageCleanupState(
    report: report ?? this.report,
    notification: identical(notification, _unset)
        ? this.notification
        : notification as StorageCleanupNotificationRecord?,
    lastCleanupAt: lastCleanupAt ?? this.lastCleanupAt,
    isScanning: isScanning ?? this.isScanning,
    isDeleting: isDeleting ?? this.isDeleting,
    lastError: clearError ? null : (lastError ?? this.lastError),
    busy: busy ?? this.busy,
  );
}

final storageCleanupControllerProvider =
    NotifierProvider<StorageCleanupController, StorageCleanupState>(
      StorageCleanupController.new,
    );

final class StorageCleanupController extends Notifier<StorageCleanupState> {
  @override
  StorageCleanupState build() => const StorageCleanupState();

  bool _ownsActiveShop() {
    final profile = ref.read(userProfileProvider).value;
    if (profile == null || !profile.isActive || !profile.isOwner) return false;
    final shopId = profile.shopId;
    return shopId != null && shopId.isNotEmpty;
  }

  String _activeShopId() {
    final shopId = ref.read(userProfileProvider).value?.shopId;
    if (shopId == null || shopId.isEmpty) {
      throw const StorageCleanupForbiddenFailure();
    }
    return shopId;
  }

  StorageCleanupGateway get _gateway => ref.read(storageCleanupGatewayProvider);
  DriftStorageCleanupRepository get _repo =>
      ref.read(storageCleanupRepositoryProvider);

  /// Runs a read-only usage + orphan scan for the owner's active shop and
  /// posts a monthly cleanup-available notification when orphans exist.
  /// NEVER deletes anything.
  Future<void> scan() async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    state = state.copyWith(isScanning: true, clearError: true);
    try {
      final report = await _gateway.scan(shopId: shopId);
      await _repo.recordScan(
        shopId: shopId,
        usedBytes: report.usedBytes,
        reclaimableBytes: report.reclaimableBytes,
      );
      // Post a notification only when there is something reclaimable, and only
      // once per open (undismissed) notice — the repository dedupes.
      StorageCleanupNotificationRecord? notification = state.notification;
      if (report.orphanCount > 0) {
        final posted = await _repo.postNotification(
          shopId: shopId,
          orphanCount: report.orphanCount,
          reclaimableBytes: report.reclaimableBytes,
        );
        if (posted) {
          notification = await _repo.activeNotification(shopId: shopId);
        }
      }
      state = state.copyWith(
        report: report,
        notification: notification,
        isScanning: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(isScanning: false, lastError: error.toString());
      rethrow;
    }
  }

  /// Permanently deletes the given orphan [paths] AFTER the owner confirms.
  /// The function re-verifies each path is still unreferenced. Then refreshes
  /// usage + records the cleanup.
  Future<CleanupDeleteResult> deleteOrphans(List<String> paths) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    if (paths.isEmpty) {
      return const CleanupDeleteResult(deletedPaths: [], deletedCount: 0);
    }
    final shopId = _activeShopId();
    state = state.copyWith(isDeleting: true, clearError: true);
    try {
      final result = await _gateway.deleteOrphans(shopId: shopId, paths: paths);
      if (result.deletedCount > 0) {
        await _repo.recordCleanup(
          shopId: shopId,
          usedBytes: state.report?.usedBytes ?? 0,
          reclaimableBytes: state.report?.reclaimableBytes ?? 0,
        );
        // Dismiss the cleanup-available notification once handled.
        final note = state.notification;
        if (note != null) {
          await _repo.markNotification(
            id: note.id,
            isRead: true,
            dismissed: false,
          );
        }
        state = state.copyWith(
          isDeleting: false,
          clearError: true,
          lastCleanupAt: DateTime.now().toUtc(),
        );
        // Refresh usage so the screen reflects freed space.
        await scan();
      } else {
        state = state.copyWith(isDeleting: false, clearError: true);
      }
      return result;
    } catch (error) {
      state = state.copyWith(isDeleting: false, lastError: error.toString());
      rethrow;
    }
  }

  /// Marks the active notification as read (not dismissed).
  Future<void> markNotificationRead() async {
    final note = state.notification;
    if (note == null || note.isRead) return;
    await _repo.markNotification(id: note.id, isRead: true);
    state = state.copyWith(notification: note.copyWith(isRead: true));
  }

  /// Dismisses (clears) the active owner notification.
  Future<void> dismissNotification() async {
    final note = state.notification;
    if (note == null) return;
    await _repo.markNotification(id: note.id, dismissed: true);
    state = state.copyWith(notification: null);
  }

  /// Hydrates the active notification + last-cleanup timestamp from local state
  /// on first build (called by the UI; owner-only).
  Future<void> hydrate() async {
    if (!_ownsActiveShop()) return;
    final shopId = _activeShopId();
    final notification = await _repo.activeNotification(shopId: shopId);
    final lastCleanupAt = await _repo.lastCleanupAt(shopId);
    state = state.copyWith(
      notification: notification,
      lastCleanupAt: lastCleanupAt,
    );
  }
}
