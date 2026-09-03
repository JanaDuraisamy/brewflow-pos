import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// StorageCleanupState — per-shop bookkeeping for storage monitoring + cleanup.
///
/// One row per shop. Tracks when the last scan ran and when the last
/// owner-confirmed cleanup completed, so the usage screen can show "Last
/// cleanup" and the controller can avoid re-issuing a monthly notification for
/// the same window. Pure metadata — never holds Storage object bytes.
/// ---------------------------------------------------------------------------
class StorageCleanupState extends Table {
  /// Shop scope (isolation boundary). The natural key for this bookkeeping.
  TextColumn get shopId => text()();

  @override
  Set<Column> get primaryKey => {shopId};

  /// UTC timestamp of the last completed usage scan.
  DateTimeColumn get lastScanAt => dateTime().nullable()();

  /// UTC timestamp of the last owner-confirmed cleanup.
  DateTimeColumn get lastCleanupAt => dateTime().nullable()();

  /// Latest known used bytes (snapshot, informational for offline display).
  IntColumn get lastUsedBytes => integer().nullable()();

  /// Latest known reclaimable bytes (snapshot).
  IntColumn get lastReclaimableBytes => integer().nullable()();
}
