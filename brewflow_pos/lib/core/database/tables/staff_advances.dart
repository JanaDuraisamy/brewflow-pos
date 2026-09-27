import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';
import 'users.dart';

/// ---------------------------------------------------------------------------
/// Staff advances — money drawn against a staff member's salary
///
/// Owner-recorded payouts; each month's final payable is the month's gross
/// salary minus the sum of advances on its business days. Amounts are integer
/// paise and validated (>= 0) at the repository boundary. Local-first: this
/// table is device-local and not part of cloud sync yet.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_staff_advances_shop_date',
  columns: {#shopId, #advanceDate},
)
@TableIndex(
  name: 'idx_staff_advances_staff_date',
  columns: {#staffUserId, #advanceDate},
)
@TableIndex(name: 'idx_staff_advances_updated_at', columns: {#updatedAt})
class StaffAdvances extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop ([Shops.id]); null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The staff member this advance belongs to ([Users.id]).
  TextColumn get staffUserId =>
      text().references(Users, #id, onDelete: KeyAction.cascade)();

  /// Advance amount in integer paise (>= 0, validated at the repo boundary).
  IntColumn get amountPaise => integer()();

  /// Local business day the advance was paid (stored as UTC midnight).
  DateTimeColumn get advanceDate => dateTime()();

  /// Optional owner note (e.g. "Festival advance", "Salary top-up").
  TextColumn get note => text().nullable()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
