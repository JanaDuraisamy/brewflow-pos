import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Devices — registered installations of BrewFlow for one shop
///
/// One row per physical installation that has signed in. A device belongs to
/// exactly one shop and is associated with the user that registered it;
/// the SAME user may register MANY devices (owner phone + tablet + …), so
/// there is intentionally NO unique constraint on user_id.
///
/// Device identity is separate from authorization: role/permissions stay on
/// the USER (users/staff_permissions). This table only answers "which
/// installations exist for this shop" for future sync.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_devices_shop', columns: {#shopId})
@TableIndex(name: 'idx_devices_updated_at', columns: {#updatedAt})
class Devices extends Table {
  /// Local UUID v4 identifier — also used as the server device id.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop ([Shops.id]).
  TextColumn get shopId => text().references(Shops, #id)();

  /// Supabase auth user id that registered this installation.
  TextColumn get userId => text()();

  /// Optional human-friendly label (e.g. 'Counter tablet').
  TextColumn get deviceName => text().nullable()();

  /// Platform hint (e.g. 'android', 'windows'); informational.
  TextColumn get platform => text().nullable()();

  /// UTC timestamp of registration.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last heartbeat/registration refresh.
  DateTimeColumn get lastSeenAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// Soft switch so a shop can retire a lost device without deleting it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
