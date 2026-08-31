import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// SyncOutbox — durable local queue of business changes to upload
///
/// One row per local business change that still needs to reach the server.
/// Rows are appended ATOMICALLY with the business transaction they describe
/// (see SyncOutboxRepository.enqueueInTransaction) so a crash can never leave
/// local data permanently unsynced.
///
/// Duplicate safety: the identity index (entity, entity_id, operation)
/// collapses replays of the same logical change while it is still pending.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_sync_outbox_identity',
  columns: {#entity, #entityId, #operation},
)
@TableIndex(name: 'idx_sync_outbox_status', columns: {#status, #createdAt})
class SyncOutbox extends Table {
  /// Local UUID v4 identifier.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Installation that produced the change.
  TextColumn get deviceId => text()();

  /// Shop scope of the change (isolation boundary for upload/apply).
  TextColumn get shopId => text()();

  /// Entity type key, e.g. 'PRODUCT', 'SALE'.
  TextColumn get entity => text()();

  /// Stable UUID of the changed row.
  TextColumn get entityId => text()();

  /// Operation: 'UPSERT' or 'DELETE'.
  TextColumn get operation => text().withDefault(const Constant('UPSERT'))();

  /// JSON payload carrying the row snapshot required by the server apply.
  TextColumn get payload => text()();

  /// PENDING → IN_FLIGHT → DONE / FAILED (FAILED keeps rows for inspection
  /// and manual retry; retry counters live here too).
  TextColumn get status => text().withDefault(const Constant('PENDING'))();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
