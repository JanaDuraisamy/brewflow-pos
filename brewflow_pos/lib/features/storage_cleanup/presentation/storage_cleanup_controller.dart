import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/storage_cleanup_gateway.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

/// Cloud gateway for storage monitoring/cleanup. Tests override with a fake;
/// production wires the Supabase edge-function client.
final storageCleanupGatewayProvider = Provider<StorageCleanupGateway>(
  (ref) => SupabaseStorageCleanupGateway(Supabase.instance.client.functions),
);

/// Local bookkeeping (notifications + per-shop cleanup state + monthly
/// mirrors). The shared outbox coordinator binds confirmation writes to the
/// durable sync queue atomically (no-op when no session is active).
final storageCleanupRepositoryProvider =
    Provider<DriftStorageCleanupRepository>(
      (ref) => DriftStorageCleanupRepository(
        ref.watch(appDatabaseProvider),
        outbox: ref.watch(syncOutboxCoordinatorProvider),
      ),
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
    this.metrics,
    this.snapshots = const [],
    this.activeMonths = const [],
    this.isLoadingMetrics = false,
    this.previewMonth,
    this.preview,
    this.isLoadingPreview = false,
    this.lastCleanupResult,
    this.scanStatus = StorageScanStatus.notScanned,
    this.selectedCategories = _allCategoryKeys,
    this.cleanupCategories = const [],
    this.lastMonthStats,
  });

  /// Latest usage/scan report (null before the first scan).
  final StorageUsageReport? report;

  /// Truthful scan status — a failed or never-run scan is never shown as
  /// real zero values.
  final StorageScanStatus scanStatus;

  /// Active owner notification, if any.
  final StorageCleanupNotificationRecord? notification;

  final DateTime? lastCleanupAt;
  final bool isScanning;
  final bool isDeleting;
  final String? lastError;
  final bool busy;

  /// Physical database metrics (DB-wide sizes + limit), null until loaded.
  final DatabaseMetrics? metrics;

  /// Monthly ledger snapshots, newest month first.
  final List<MonthlySnapshot> snapshots;

  /// Months with local transactional activity, newest first. The snapshot
  /// ledger only covers months someone refreshed; these months let the
  /// history list offer every month the shop actually traded in.
  final List<DateTime> activeMonths;

  final bool isLoadingMetrics;

  /// Month the [preview] belongs to (UTC first-of-month cookie).
  final DateTime? previewMonth;

  /// Read-only cleanup preview for [previewMonth], null until loaded.
  final MonthCleanupPreview? preview;

  final bool isLoadingPreview;

  /// Result of the latest month cleanup (actual affected-row counts).
  final MonthCleanupResult? lastCleanupResult;

  /// Months selected for cleanup (keys of [kCleanupCategoryMeta]). Defaults
  /// to every category — the full month scope.
  final Set<String> selectedCategories;

  /// Per-category cleanup options with exact counts + estimated logical
  /// bytes, built from the latest preview + month stats.
  final List<CleanupCategory> cleanupCategories;

  /// Latest month stats (carries the server-measured average row widths).
  final MonthlyUsageStats? lastMonthStats;

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
    DatabaseMetrics? metrics,
    List<MonthlySnapshot>? snapshots,
    List<DateTime>? activeMonths,
    bool? isLoadingMetrics,
    DateTime? previewMonth,
    Object? preview = _unset,
    bool? isLoadingPreview,
    Object? lastCleanupResult = _unset,
    StorageScanStatus? scanStatus,
    Set<String>? selectedCategories,
    List<CleanupCategory>? cleanupCategories,
    MonthlyUsageStats? lastMonthStats,
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
    metrics: metrics ?? this.metrics,
    snapshots: snapshots ?? this.snapshots,
    activeMonths: activeMonths ?? this.activeMonths,
    isLoadingMetrics: isLoadingMetrics ?? this.isLoadingMetrics,
    previewMonth: previewMonth ?? this.previewMonth,
    preview: identical(preview, _unset)
        ? this.preview
        : preview as MonthCleanupPreview?,
    isLoadingPreview: isLoadingPreview ?? this.isLoadingPreview,
    lastCleanupResult: identical(lastCleanupResult, _unset)
        ? this.lastCleanupResult
        : lastCleanupResult as MonthCleanupResult?,
    scanStatus: scanStatus ?? this.scanStatus,
    selectedCategories: selectedCategories ?? this.selectedCategories,
    cleanupCategories: cleanupCategories ?? this.cleanupCategories,
    lastMonthStats: lastMonthStats ?? this.lastMonthStats,
  );
}

final storageCleanupControllerProvider =
    NotifierProvider<StorageCleanupController, StorageCleanupState>(
      StorageCleanupController.new,
    );

/// Every cleanup category key — the default selection (full month scope).
const _allCategoryKeys = {
  'sales',
  'purchases',
  'expenses',
  'stockMovements',
  'dailyClosings',
  'staffAttendance',
  'staffAdvances',
  'staffDailySalaries',
  'staffMonthlySalaries',
};

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
    state = state.copyWith(
      isScanning: true,
      scanStatus: StorageScanStatus.scanning,
      clearError: true,
    );
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
        scanStatus: StorageScanStatus.succeeded,
        clearError: true,
      );
    } catch (error) {
      AppLog.error(
        'Storage scan failed for shop $shopId: $error (${error.runtimeType})',
        tag: 'StorageScan',
        error: error,
      );
      // Truthful failure: keep any previous successful report (the UI labels
      // it stale) but never fabricate zero values for a failed scan.
      state = state.copyWith(
        isScanning: false,
        scanStatus: StorageScanStatus.failed,
        lastError: error.toString(),
      );
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

  /// Loads physical database metrics for the owner's active shop. Read-only;
  /// sizes are DB-wide figures labeled as such in the UI.
  Future<void> loadMetrics() async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    state = state.copyWith(isLoadingMetrics: true, clearError: true);
    try {
      final metrics = await _gateway.dbMetrics(shopId: shopId);
      state = state.copyWith(
        metrics: metrics,
        isLoadingMetrics: false,
        clearError: true,
      );
    } catch (error) {
      state = state.copyWith(
        isLoadingMetrics: false,
        lastError: error.toString(),
      );
      rethrow;
    }
  }

  /// Refreshes one month's logical stats (computes server-side, records the
  /// server ledger row) and caches the snapshot locally for offline history.
  Future<MonthlyUsageStats> refreshMonth(DateTime month) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final stats = await _gateway.monthStats(shopId: shopId, month: month);
    await _repo.cacheSnapshot(shopId: shopId, stats: stats);
    await loadHistory();
    state = state.copyWith(lastMonthStats: stats);
    // Rebuild the cleanup categories so their estimated sizes stay in sync.
    _rebuildCleanupCategories();
    return stats;
  }

  /// Loads one month's logical stats for the table-detail sheet (record
  /// counts + server-measured average row widths) without touching the
  /// snapshot cache or history.
  Future<MonthlyUsageStats> loadMonthStats(DateTime month) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final stats = await _gateway.monthStats(shopId: shopId, month: month);
    state = state.copyWith(lastMonthStats: stats);
    return stats;
  }

  /// Rebuilds the per-category cleanup options from the latest preview counts
  /// and the server-measured average row widths. Estimated bytes per category
  /// = exact in-month count x average physical row width (an honest logical
  /// estimate — Postgres cannot attribute shared-table bytes to a month).
  void _rebuildCleanupCategories() {
    final preview = state.preview;
    final stats = state.lastMonthStats;
    if (preview == null) return;
    state = state.copyWith(
      cleanupCategories: [
        for (final meta in kCleanupCategoryMeta)
          CleanupCategory(
            key: meta.key,
            label: meta.label,
            description: meta.description,
            deletes: meta.deletes,
            count: meta.countKeys.fold(
              0,
              (sum, k) => sum + (preview.counts[k] ?? 0),
            ),
            estimatedBytes: meta.countKeys.fold(0, (sum, k) {
              final estimate = stats?.estimatedBytesFor(k) ?? 0;
              return sum + estimate;
            }),
          ),
      ],
    );
  }

  /// Loads the monthly ledger: server history when reachable, else the local
  /// snapshot cache (offline history). Server rows win when both exist.
  Future<void> loadHistory() async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    try {
      final remote = await _gateway.monthHistory(shopId: shopId);
      for (final snapshot in remote) {
        await _repo.cacheSnapshot(
          shopId: shopId,
          stats: MonthlyUsageStats(
            month: snapshot.month,
            counts: snapshot.counts,
            logicalBytesEst: snapshot.logicalBytesEst,
            dbBytesTotal: snapshot.dbBytesTotal,
          ),
        );
      }
    } on StorageCleanupFailure {
      // Offline or undeployed service: fall through to the local cache so
      // history still renders. The error surfaces on explicit refresh, not
      // on passive history loads.
    }
    final cached = await _repo.cachedSnapshots(shopId);
    final active = await _repo.activeMonths(shopId);
    state = state.copyWith(
      snapshots: cached,
      activeMonths: active,
      clearError: true,
    );
  }

  /// Loads the read-only cleanup preview for [month]. The preview comes from
  /// the same SQL the atomic cleanup runs, so confirmed counts match.
  Future<void> previewMonth(DateTime month) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final cookie = DateTime.utc(month.year, month.month);
    state = state.copyWith(
      isLoadingPreview: true,
      previewMonth: cookie,
      preview: null,
      clearError: true,
    );
    try {
      final preview = await _gateway.monthPreview(
        shopId: shopId,
        month: cookie,
      );
      state = state.copyWith(
        preview: preview,
        isLoadingPreview: false,
        clearError: true,
      );
      _rebuildCleanupCategories();
    } catch (error) {
      state = state.copyWith(
        isLoadingPreview: false,
        lastError: error.toString(),
      );
      rethrow;
    }
  }

  /// Toggles one cleanup category in the current selection.
  void toggleCleanupCategory(String key) {
    final selected = {...state.selectedCategories};
    if (selected.contains(key)) {
      selected.remove(key);
    } else {
      selected.add(key);
    }
    state = state.copyWith(selectedCategories: selected);
  }

  /// Selects every cleanup category (the full month scope).
  void selectAllCleanupCategories() {
    state = state.copyWith(selectedCategories: {..._allCategoryKeys});
  }

  /// Clears the selection — nothing will be deleted.
  void clearCleanupSelection() {
    state = state.copyWith(selectedCategories: const {});
  }

  /// Records the owner's "report generated/saved" confirmation for [month].
  /// Syncs through the existing outbox so every owner device agrees the month
  /// is report-backed before cleanup is allowed anywhere.
  Future<void> confirmReport(DateTime month) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final cookie = DateTime.utc(month.year, month.month);
    final profile = ref.read(userProfileProvider).value;
    await _repo.confirmReport(
      shopId: shopId,
      month: cookie,
      confirmedBy: profile?.email,
    );
    // Refresh the preview so the confirmation gate opens immediately.
    await previewMonth(cookie);
  }

  /// Loads the month-detail status: whether a snapshot is cached locally, the
  /// monthly report is confirmed, and the month was already cleaned.
  Future<({bool snapshotSaved, bool reportConfirmed, bool alreadyCleaned})>
  loadMonthStatus(DateTime month) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final cookie = DateTime.utc(month.year, month.month);
    final confirmation = await _repo.confirmationFor(shopId, cookie);
    final cleaned = await _repo.monthCleaned(shopId, cookie);
    final snapshotSaved = state.snapshots.any(
      (s) => s.month.year == cookie.year && s.month.month == cookie.month,
    );
    return (
      snapshotSaved: snapshotSaved,
      reportConfirmed: confirmation != null,
      alreadyCleaned: cleaned,
    );
  }

  /// Runs the owner-confirmed month-scoped HARD DELETE for [month].
  ///
  /// Gates (each a [MonthCleanupBlockedFailure], month untouched):
  /// - a fresh [preview] for this month showing it is report-confirmed and
  ///   not already cleaned,
  /// - an empty sync outbox (cleanup never runs under unsynced writes, or a
  ///   queued row pushed afterwards would resurrect without a tombstone).
  ///
  /// Then: atomic server delete (actual affected-row counts) → local mirrors
  /// deleted in the same dependency order + marker recorded, atomically →
  /// metrics rescanned. Physical disk reclamation is NOT claimed: Postgres
  /// reuses the freed space via vacuum; only the post-delete metrics are
  /// shown.
  ///
  /// [categories] narrows the delete to specific cleanup categories (used by
  /// the per-table month delete). Null = the current selection. Every existing
  /// gate (preview, report confirmation, open bills, outbox) still applies.
  Future<MonthCleanupResult> cleanupMonth(
    DateTime month, {
    List<String>? categories,
  }) async {
    if (!_ownsActiveShop()) {
      throw const StorageCleanupForbiddenFailure();
    }
    final shopId = _activeShopId();
    final selected = categories ?? state.selectedCategories;
    final cookie = DateTime.utc(month.year, month.month);
    final preview = state.preview;
    if (state.previewMonth != cookie || preview == null) {
      throw const MonthCleanupBlockedFailure(
        'Preview this month first — cleanup needs a fresh confirmation view.',
      );
    }
    if (!preview.reportConfirmed) {
      throw const MonthCleanupBlockedFailure(
        'Generate and confirm this month\u2019s report before cleanup.',
      );
    }
    if (preview.alreadyCleaned) {
      throw const MonthCleanupBlockedFailure(
        'This month was already cleaned up.',
      );
    }
    // Open-bill protection: never delete unpaid/partially-paid customer bills —
    // doing so would erase customer outstanding and break the ledger. The
    // server enforces the same guard; this blocks the flow before any call.
    if (selected.contains('sales') && preview.openBillCount > 0) {
      throw MonthCleanupBlockedFailure(
        'This month has ${preview.openBillCount} unpaid or partially-paid '
        'customer bill${preview.openBillCount == 1 ? '' : 's'}. Settle them '
        'before cleanup — deleting them would erase customer outstanding.',
      );
    }
    if (selected.isEmpty) {
      throw const MonthCleanupBlockedFailure(
        'Select at least one category to clean up.',
      );
    }
    final pending = await ref.read(syncRepositoryProvider).pendingOutboxCount();
    if (pending > 0) {
      throw MonthCleanupBlockedFailure(
        'Sync $pending pending change${pending == 1 ? '' : 's'} first — '
        'cleanup never runs under unsynced writes.',
      );
    }
    state = state.copyWith(isDeleting: true, clearError: true);
    try {
      final markerId = const Uuid().v4();
      final result = await _gateway.monthCleanup(
        shopId: shopId,
        month: cookie,
        markerId: markerId,
        categories: selected.toList(),
      );
      await _repo.applyLocalMonthCleanup(
        shopId: shopId,
        month: cookie,
        markerId: result.markerId,
        tables: result.deleted.keys.toList(),
        deletedCounts: result.deleted,
      );
      state = state.copyWith(
        isDeleting: false,
        clearError: true,
        lastCleanupAt: DateTime.now().toUtc(),
        lastCleanupResult: result,
      );
      // Refresh everything the deletion moved: physical metrics, the month's
      // snapshot row and the preview itself.
      await loadMetrics();
      await refreshMonth(cookie);
      await previewMonth(cookie);
      return result;
    } catch (error) {
      state = state.copyWith(isDeleting: false, lastError: error.toString());
      rethrow;
    }
  }
}
