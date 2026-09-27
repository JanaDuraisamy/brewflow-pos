import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing DAO
///
/// All Drift access for daily closing records. SQL-side ordering; amounts are
/// integer paise and validated (>= 0) at the repository boundary.
/// ---------------------------------------------------------------------------

final class DailyClosingDao {
  DailyClosingDao(this._db);

  final AppDatabase _db;

  /// Records with a [businessDate] in [fromDate]..[toDate) (half-open range
  /// of UTC-midnight day cookies), newest business day first then newest
  /// created first — the review-list ordering. [shopIds] restricts rows to
  /// those businesses (Cafe/Food Truck isolation); null reads every scope.
  Future<List<DailyClosing>> query({
    List<String>? shopIds,
    DateTime? fromDate,
    DateTime? toDate,
  }) {
    final query = _db.select(_db.dailyClosings)
      ..orderBy([
        (t) => OrderingTerm.desc(t.businessDate),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (fromDate != null) {
      query.where((t) => t.businessDate.isBiggerOrEqualValue(fromDate));
    }
    if (toDate != null) {
      query.where((t) => t.businessDate.isSmallerThanValue(toDate));
    }
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    return query.get();
  }

  Future<DailyClosing> insert(DailyClosingsCompanion closing) =>
      _db.into(_db.dailyClosings).insertReturning(closing);

  Future<void> deleteById(String id) async {
    await (_db.delete(_db.dailyClosings)..where((t) => t.id.equals(id))).go();
  }
}
