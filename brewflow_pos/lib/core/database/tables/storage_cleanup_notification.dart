import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// StorageCleanupNotification — owner-only local notice that a monthly orphan
/// cleanup is available.
///
/// This is a device-local notification (there is no generic server notification
/// system in BrewFlow yet). It is created only when the signed-in profile is an
/// OWNER and never surfaced to STAFF (the UI gates on role). The row carries the
/// count + reclaimable size so the owner can decide whether to review files.
///
/// Expected lifecycle: unread -> read (via details) -> dismissed (cleared), or
/// superseded by a newer monthly notification for the same shop/kind. A single
/// active notification per shop is the norm; the month-sensitivity is enforced
/// by callers comparing [createdAt] against the month window, not by a unique
/// constraint.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_storage_cleanup_notification', columns: {#shopId, #kind})
class StorageCleanupNotification extends Table {
  /// Local UUID v4 identifier.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Shop scope of the cleanup (isolation boundary).
  TextColumn get shopId => text()();

  /// Notification kind: 'CLEANUP_AVAILABLE'.
  TextColumn get kind => text()();

  /// Number of orphan (unreferenced) product images found.
  IntColumn get orphanCount => integer().withDefault(const Constant(0))();

  /// Total reclaimable bytes across the orphan images.
  IntColumn get reclaimableBytes => integer().withDefault(const Constant(0))();

  /// Whether the owner has opened the notification details.
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  /// Whether the owner has dismissed/cleared the notification.
  BoolColumn get dismissed => boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
