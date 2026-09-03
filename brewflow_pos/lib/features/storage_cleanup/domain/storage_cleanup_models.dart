import 'package:brewflow_pos/core/database/app_database.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Storage Cleanup Domain
///
/// Data shapes for owner-only storage monitoring and monthly orphan-image
/// cleanup. The client never lists Storage buckets or deletes objects directly
/// (that requires service-role privileges); everything crosses the
/// `storage-cleanup` Edge Function, which authorizes the owner server-side and
/// returns these shapes.
/// ---------------------------------------------------------------------------

/// Aggregate result of a storage scan for one shop.
class StorageUsageReport {
  const StorageUsageReport({
    required this.usedBytes,
    required this.imageCount,
    required this.orphanCount,
    required this.reclaimableBytes,
    required this.orphanPaths,
    required this.lastScanAt,
    this.storageLimitBytes,
  });

  /// Total bytes used by all product-image objects for this shop.
  final int usedBytes;

  /// Total number of product-image objects for this shop.
  final int imageCount;

  /// Number of unreferenced (orphan) product-image objects.
  final int orphanCount;

  /// Sum of bytes across the orphan objects (reclaimable if deleted).
  final int reclaimableBytes;

  /// The exact Storage object paths classified as orphans.
  final List<String> orphanPaths;

  /// Configured storage limit (bytes) for the shop, or null when unlimited.
  final int? storageLimitBytes;

  /// UTC time the scan snapshot was produced server-side.
  final DateTime lastScanAt;

  /// Storage usage as a 0..1 fraction when a limit is configured, else null.
  double? get usageFraction {
    final limit = storageLimitBytes;
    if (limit == null || limit <= 0) return null;
    return (usedBytes / limit).clamp(0.0, 1.0);
  }
}

/// One individual orphan candidate offered for review before deletion.
class OrphanImage {
  const OrphanImage({required this.cloudPath, required this.sizeBytes});

  final String cloudPath;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is OrphanImage && other.cloudPath == cloudPath;

  @override
  int get hashCode => cloudPath.hashCode;
}

/// Result of an owner-confirmed permanent deletion of orphan objects.
class CleanupDeleteResult {
  const CleanupDeleteResult({
    required this.deletedPaths,
    required this.deletedCount,
  });

  final List<String> deletedPaths;
  final int deletedCount;
}

/// Owner-notification kinds surfaced on-device.
enum StorageCleanupNotificationKind {
  /// A monthly scan found reclaimable (unreferenced) images.
  cleanupAvailable;

  String get storageValue => switch (this) {
    StorageCleanupNotificationKind.cleanupAvailable => 'CLEANUP_AVAILABLE',
  };

  static StorageCleanupNotificationKind? fromStorage(String value) =>
      switch (value) {
        'CLEANUP_AVAILABLE' => StorageCleanupNotificationKind.cleanupAvailable,
        _ => null,
      };
}

/// A local, owner-only notification record (mirrors the Drift table).
class StorageCleanupNotificationRecord {
  const StorageCleanupNotificationRecord({
    required this.id,
    required this.shopId,
    required this.kind,
    required this.orphanCount,
    required this.reclaimableBytes,
    required this.createdAt,
    this.isRead = false,
    this.dismissed = false,
  });

  final String id;
  final String shopId;
  final StorageCleanupNotificationKind kind;
  final int orphanCount;
  final int reclaimableBytes;
  final DateTime createdAt;
  final bool isRead;
  final bool dismissed;

  StorageCleanupNotificationRecord copyWith({bool? isRead, bool? dismissed}) =>
      StorageCleanupNotificationRecord(
        id: id,
        shopId: shopId,
        kind: kind,
        orphanCount: orphanCount,
        reclaimableBytes: reclaimableBytes,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        dismissed: dismissed ?? this.dismissed,
      );

  factory StorageCleanupNotificationRecord.fromRow(
    StorageCleanupNotificationData row,
  ) => StorageCleanupNotificationRecord(
    id: row.id,
    shopId: row.shopId,
    kind:
        StorageCleanupNotificationKind.fromStorage(row.kind) ??
        StorageCleanupNotificationKind.cleanupAvailable,
    orphanCount: row.orphanCount,
    reclaimableBytes: row.reclaimableBytes,
    createdAt: row.createdAt,
    isRead: row.isRead,
    dismissed: row.dismissed,
  );
}

/// Base for all storage-cleanup failures; every subtype carries a user-safe
/// message.
sealed class StorageCleanupFailure implements Exception {
  const StorageCleanupFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The signed-in profile is not an active OWNER of this shop.
final class StorageCleanupForbiddenFailure extends StorageCleanupFailure {
  const StorageCleanupForbiddenFailure()
    : super('Only an active shop owner can review or clean up storage.');
}

/// The storage-cleanup service (Edge Function) is unreachable or errored.
final class StorageCleanupServiceFailure extends StorageCleanupFailure {
  const StorageCleanupServiceFailure([
    super.message = 'Storage information is unavailable right now.',
  ]);
}

/// The signed-in session expired.
final class StorageCleanupSessionFailure extends StorageCleanupFailure {
  const StorageCleanupSessionFailure()
    : super('Your session has expired. Please sign in again and retry.');
}
