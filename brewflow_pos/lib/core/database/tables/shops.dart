import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// Shops — the business context all local data belongs to
///
/// BrewFlow is currently single-shop: exactly one row exists, created once
/// during owner bootstrap. Every future synced entity will carry this id, so
/// multi-device sync (Step 3) can scope data without another migration.
/// Multi-shop switching is deliberately NOT implemented.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_shops_updated_at', columns: {#updatedAt})
class Shops extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business display name; informational until business identity settings
  /// are linked to the shop row.
  TextColumn get name => text()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
