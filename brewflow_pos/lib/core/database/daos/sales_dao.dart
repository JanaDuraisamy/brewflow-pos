import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sales DAO
///
/// All Drift reads for the sales table. Writes happen inside the billing
/// repository's checkout transaction (header + items + stock must commit
/// together), so no insert lives here.
/// ---------------------------------------------------------------------------

final class SalesDao {
  SalesDao(this._db);

  final AppDatabase _db;

  /// All sales, newest first.
  Future<List<Sale>> all() {
    final query = _db.select(_db.sales)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  Future<Sale?> byId(String id) {
    final query = _db.select(_db.sales)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }
}
