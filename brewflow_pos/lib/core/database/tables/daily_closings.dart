import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Daily closing — end-of-day cash/sales tallies
///
/// One row per closing record for a business day (several revisions of the
/// same day are allowed; the UI groups by day). All amounts are integer
/// paise. Local-first: this table is device-local and not part of cloud sync
/// yet.
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_daily_closings_shop_date',
  columns: {#shopId, #businessDate},
)
@TableIndex(name: 'idx_daily_closings_updated_at', columns: {#updatedAt})
class DailyClosings extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop ([Shops.id]); null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The business day this closing covers (stored as UTC midnight of the
  /// local business day).
  DateTimeColumn get businessDate => dateTime()();

  /// Total cash received during the day, in paise.
  IntColumn get totalCashPaise => integer().withDefault(const Constant(0))();

  /// Total UPI received, in paise.
  IntColumn get totalUpiPaise => integer().withDefault(const Constant(0))();

  /// Total sales value billed during the day, in paise.
  IntColumn get totalSalesPaise => integer().withDefault(const Constant(0))();

  /// Total expenses incurred during the day, in paise.
  IntColumn get totalExpensePaise => integer().withDefault(const Constant(0))();

  /// Cash physically remaining in the box at close, in paise.
  IntColumn get cashLeftInBoxPaise =>
      integer().withDefault(const Constant(0))();

  /// Cash taken out of the box (owner draw/etc.) during the day, in paise.
  IntColumn get cashTakenOutPaise => integer().withDefault(const Constant(0))();

  /// Who took the cash out (optional free text).
  TextColumn get takenOutBy => text().nullable()();

  /// Who tallied/closed the day (optional free text).
  TextColumn get talliedBy => text().nullable()();

  /// Optional note for the closing record.
  TextColumn get note => text().nullable()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
