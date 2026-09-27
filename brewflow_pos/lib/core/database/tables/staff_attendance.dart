import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';
import 'users.dart';

/// ---------------------------------------------------------------------------
/// Staff attendance — clock-in/clock-out shifts
///
/// One row per attendance shift. A shift is open while [outAt] is null;
/// closing it fixes [workedMinutes] so the month's salary derivation never
/// changes retroactively. Each staff member may have at most one open shift;
/// a business day may hold several closed shifts (split shifts are allowed).
/// Local-first mirror of the cloud attendance rows: writes commit to the
/// cloud first, and reads pull the cloud for the requested month before the
/// local rows are served, including deletes made on another device.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_staff_attendance_shop_date',
  columns: {#shopId, #attendanceDate},
)
@TableIndex(
  name: 'idx_staff_attendance_staff_date',
  columns: {#staffUserId, #attendanceDate},
)
@TableIndex(name: 'idx_staff_attendance_updated_at', columns: {#updatedAt})
class StaffAttendance extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop ([Shops.id]); null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The staff member this shift belongs to ([Users.id]).
  TextColumn get staffUserId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  /// UTC instant of clock-in.
  DateTimeColumn get inAt => dateTime()();

  /// UTC instant of clock-out; null while the shift is open.
  DateTimeColumn get outAt => dateTime().nullable()();

  /// Local business day this shift falls under (stored as UTC midnight).
  DateTimeColumn get attendanceDate => dateTime()();

  /// Worked minutes once the shift is closed; 0 while open.
  IntColumn get workedMinutes => integer().withDefault(const Constant(0))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
