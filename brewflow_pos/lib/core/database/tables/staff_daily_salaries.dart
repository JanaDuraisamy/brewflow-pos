import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';
import 'users.dart';

/// ---------------------------------------------------------------------------
/// Staff daily salaries — owner-entered daily salary amount per staff per
/// business day.
///
/// Day-level (not per shift), so split shifts on the same day still carry ONE
/// salary; the month's calculated salary is the SUM of these daily amounts.
/// The owner may always override the month with a manual monthly salary
/// (staff_monthly_salaries) which wins over the calculated sum.
///
/// Salary is NEVER derived from an hourly rate: attendance working hours are
/// calculated and displayed, but the payable amount is the daily/monthly
/// salary the owner enters.
///
/// One row per (shop, staff, day). Device-local: unlike manual monthly
/// salaries, daily salary amounts are not part of cloud sync yet.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_staff_daily_salaries_shop_date',
  columns: {#shopId, #attendanceDate},
)
@TableIndex(
  name: 'idx_staff_daily_salaries_staff_date',
  columns: {#staffUserId, #attendanceDate},
)
@TableIndex(name: 'idx_staff_daily_salaries_updated_at', columns: {#updatedAt})
class StaffDailySalary extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop ([Shops.id]); null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The staff member this salary belongs to ([Users.id]).
  TextColumn get staffUserId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  /// Local business day this salary covers (stored as UTC midnight).
  DateTimeColumn get attendanceDate => dateTime()();

  /// Owner-entered salary amount for this day in integer paise (>= 0).
  IntColumn get salaryPaise => integer()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
