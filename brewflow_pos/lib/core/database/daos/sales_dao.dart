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
  Future<List<Sale>> all({String? shopId}) {
    final query = _db.select(_db.sales)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  Future<Sale?> byId(String id, {String? shopId}) {
    final query = _db.select(_db.sales)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.getSingleOrNull();
  }
}
