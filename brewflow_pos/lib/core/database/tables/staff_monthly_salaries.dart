import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';
import 'users.dart';

/// ---------------------------------------------------------------------------
/// Staff monthly salaries — owner-entered manual salary per staff per month
///
/// Salary is NEVER derived from an hourly rate: attendance working hours are
/// calculated and displayed, but the payable salary is entered manually by
/// the owner for the staff/month. Final payable = salary − advances.
///
/// One row per (shop, staff, month). Local-first cache: Supabase
/// `staff_monthly_salaries` is the authoritative store and is read first when
/// online (see the payroll cloud gateway).
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_staff_monthly_salaries_shop_month',
  columns: {#shopId, #monthDate},
)
@TableIndex(
  name: 'idx_staff_monthly_salaries_staff_month',
  columns: {#staffUserId, #monthDate},
)
@TableIndex(
  name: 'idx_staff_monthly_salaries_updated_at',
  columns: {#updatedAt},
)
class StaffMonthlySalaries extends Table {
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

  /// First of the month this salary covers (stored as UTC midnight).
  DateTimeColumn get monthDate => dateTime()();

  /// Owner-entered salary amount in integer paise (>= 0).
  IntColumn get salaryPaise => integer()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
