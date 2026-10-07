import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Month cleanup markers — applied-ledger for completed month cleanups.
///
/// One row per (shop, month) the owner cleaned. Peers pull markers through
/// the normal sync pull and delete their local month mirrors, so every device
/// converges without per-row tombstone floods. Markers are never deleted
/// (tiny ledger rows). The cleaning device records its marker in the same
/// local transaction as its own month deletes.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_month_cleanup_markers_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_month_cleanup_markers_month',
  columns: {#shopId, #month},
)
class MonthCleanupMarkers extends Table {
  /// UUID identifier. The cleaning device generates one per cleanup flow and
  /// reuses it across retries so a retry converges instead of duplicating.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop; null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// First-of-month UTC cookie that was cleaned.
  DateTimeColumn get month => dateTime()();

  /// Affected tables, JSON-encoded key set (for display/audit).
  TextColumn get tablesJson => text().withDefault(const Constant('{}'))();

  /// Actual affected-row counts by category key, JSON-encoded.
  TextColumn get deletedCountsJson =>
      text().withDefault(const Constant('{}'))();

  /// When the cleanup completed server-side.
  DateTimeColumn get completedAt => dateTime()();

  /// Whether this device already applied the marker (deleted its month
  /// mirrors). A pulled marker that arrives while transactional writes are
  /// still queued is recorded unapplied and retried on later cycles — the
  /// pull cursor must never advance past work that has not happened yet.
  BoolColumn get applied => boolean().withDefault(const Constant(false))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives incremental sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
