import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Local Storage Cleanup Bookkeeping
///
/// Device-local storage for the owner notification and per-shop cleanup state.
/// Nothing here is privileged: rows hold counts, byte sizes and timestamps —
/// never Storage object bytes and never service-role credentials.
/// ---------------------------------------------------------------------------

class DriftStorageCleanupRepository {
  DriftStorageCleanupRepository(this._db);

  final AppDatabase _db;

  /// Creates an unread owner notification for [shopId] unless an identical
  /// notification for the same shop+kind is still open (undismissed). Returns
  /// true when a new notification was inserted.
  Future<bool> postNotification({
    required String shopId,
    required int orphanCount,
    required int reclaimableBytes,
  }) async {
    final existing = await _activeFor(
      shopId,
      StorageCleanupNotificationKind.cleanupAvailable,
    );
    if (existing != null) return false;
    await _db
        .into(_db.storageCleanupNotification)
        .insert(
          StorageCleanupNotificationCompanion.insert(
            id: Value(Uuid().v4()),
            shopId: shopId,
            kind: StorageCleanupNotificationKind.cleanupAvailable.storageValue,
            orphanCount: Value(orphanCount),
            reclaimableBytes: Value(reclaimableBytes),
          ),
        );
    return true;
  }

  /// Latest open (undismissed) owner notification for [shopId] + [kind].
  Future<StorageCleanupNotificationRecord?> activeNotification({
    required String shopId,
    StorageCleanupNotificationKind kind =
        StorageCleanupNotificationKind.cleanupAvailable,
  }) => _activeFor(shopId, kind);

  Future<StorageCleanupNotificationRecord?> _activeFor(
    String shopId,
    StorageCleanupNotificationKind kind,
  ) async {
    final row =
        await (_db.select(_db.storageCleanupNotification)
              ..where(
                (n) =>
                    n.shopId.equals(shopId) &
                    n.kind.equals(kind.storageValue) &
                    n.dismissed.equals(false),
              )
              ..orderBy([(n) => OrderingTerm.desc(n.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : StorageCleanupNotificationRecord.fromRow(row);
  }

  /// Marks the notification as read/seen (or applies [dismissed]).
  Future<void> markNotification({
    required String id,
    bool isRead = true,
    bool dismissed = false,
  }) async {
    await (_db.update(
      _db.storageCleanupNotification,
    )..where((n) => n.id.equals(id))).write(
      StorageCleanupNotificationCompanion(
        isRead: Value(isRead),
        dismissed: Value(dismissed),
      ),
    );
  }

  /// Timestamp of the last owner-confirmed cleanup for [shopId], or null.
  Future<DateTime?> lastCleanupAt(String shopId) async {
    final row = await _stateRow(shopId);
    return row?.lastCleanupAt;
  }

  /// Records that an owner-confirmed cleanup completed for [shopId].
  Future<void> recordCleanup({
    required String shopId,
    required int usedBytes,
    required int reclaimableBytes,
  }) async {
    await _db
        .into(_db.storageCleanupState)
        .insertOnConflictUpdate(
          StorageCleanupStateCompanion.insert(
            shopId: shopId,
            lastCleanupAt: Value(DateTime.now().toUtc()),
            lastScanAt: Value(DateTime.now().toUtc()),
            lastUsedBytes: Value(usedBytes),
            lastReclaimableBytes: Value(reclaimableBytes),
          ),
        );
  }

  /// Records that a usage scan completed for [shopId] (for offline display).
  Future<void> recordScan({
    required String shopId,
    required int usedBytes,
    required int reclaimableBytes,
  }) async {
    await _db
        .into(_db.storageCleanupState)
        .insertOnConflictUpdate(
          StorageCleanupStateCompanion.insert(
            shopId: shopId,
            lastScanAt: Value(DateTime.now().toUtc()),
            lastUsedBytes: Value(usedBytes),
            lastReclaimableBytes: Value(reclaimableBytes),
          ),
        );
  }

  Future<StorageCleanupStateData?> _stateRow(String shopId) => (_db.select(
    _db.storageCleanupState,
  )..where((s) => s.shopId.equals(shopId))).getSingleOrNull();
}
