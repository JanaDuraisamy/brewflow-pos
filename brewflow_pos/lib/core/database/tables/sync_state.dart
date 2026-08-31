import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// SyncState — per-device incremental pull/push cursors
///
/// One row per device installation. Cursors make future pulls incremental and
/// idempotent: a device only asks for rows with updated_at > last_pulled_at.
/// Nothing here is user-visible until real sync exists (Phase 6+).
/// ---------------------------------------------------------------------------

class SyncState extends Table {
  /// Device installation this state belongs to ([Devices.id]).
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {deviceId};

  /// Owning shop scope.
  TextColumn get shopId => text()();

  /// Incremental pull cursor (max server updated_at applied).
  DateTimeColumn get lastPulledAt => dateTime().nullable()();

  /// Last successful push drain.
  DateTimeColumn get lastPushedAt => dateTime().nullable()();

  /// Last sync error message (diagnostics only; never shown as success).
  TextColumn get lastError => text().nullable()();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
