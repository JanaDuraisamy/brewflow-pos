import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Monthly report confirmations — owner-recorded "report generated/saved for
/// this month" markers. A month's destructive cleanup is gated on one of
/// these rows existing.
///
/// Unlike the snapshot cache, confirmations SYNC across owner devices through
/// the existing outbox/engine (MONTHLY_REPORT_CONFIRMATION entity): the owner
/// confirms on one device and may clean from any device for the shop.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_monthly_report_confirmations_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_monthly_report_confirmations_month',
  columns: {#shopId, #month},
)
class MonthlyReportConfirmations extends Table {
  /// UUID identifier. Client-generated; stable per confirm action.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop; null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// First-of-month UTC cookie the report covers.
  DateTimeColumn get month => dateTime()();

  /// When the owner confirmed the report.
  DateTimeColumn get confirmedAt => dateTime()();

  /// Auth identity that confirmed, when known.
  TextColumn get confirmedBy => text().nullable()();

  /// Where the report came from (e.g. 'management-report').
  TextColumn get source =>
      text().withDefault(const Constant('management-report'))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives incremental sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
