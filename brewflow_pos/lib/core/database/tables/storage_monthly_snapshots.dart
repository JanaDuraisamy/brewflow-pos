import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Storage monthly snapshots — device-local cache of the server-side monthly
/// usage ledger (`public.storage_monthly_snapshots`).
///
/// Written when the owner refreshes a month's stats (the Edge Function
/// computes exact row counts + estimated logical bytes and records the
/// server row). The cache lets the month history render offline; it is
/// derived data, never synced — each device refreshes from the server.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_storage_monthly_snapshots_shop', columns: {#shopId})
@TableIndex(name: 'idx_storage_monthly_snapshots_month', columns: {#month})
class StorageMonthlySnapshots extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop; null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// First-of-month UTC cookie this snapshot covers.
  DateTimeColumn get month => dateTime()();

  /// Exact row counts by category key, JSON-encoded.
  TextColumn get countsJson => text()();

  /// Estimated logical bytes for the month (server estimate, labeled so).
  IntColumn get logicalBytesEst => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (logical_bytes_est >= 0)',
  )();

  /// Physical database size when computed, DB-wide (nullable when unknown).
  IntColumn get dbBytesTotal => integer().nullable()();

  /// When the server recorded the snapshot.
  DateTimeColumn get snapshotAt => dateTime()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
