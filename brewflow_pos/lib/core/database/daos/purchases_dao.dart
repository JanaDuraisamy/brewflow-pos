import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchases DAO
///
/// Read access to purchase headers. Header inserts happen inside the
/// purchase repository's receiving transaction (header + items + stock must
/// commit together, Phase 10 Step 5); the single-insert helper exists for the
/// DAO foundation and for the receiving transaction to use.
/// ---------------------------------------------------------------------------

final class PurchasesDao {
  PurchasesDao(this._db);

  final AppDatabase _db;

  /// All purchases, newest first.
  Future<List<Purchase>> all({String? shopId}) {
    final query = _db.select(_db.purchases)
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  Future<Purchase?> byId(String id, {String? shopId}) {
    final query = _db.select(_db.purchases)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.getSingleOrNull();
  }

  /// Inserts a purchase header and returns the persisted row. The caller
  /// owns transaction semantics when multiple rows must commit together.
  Future<Purchase> insert(PurchasesCompanion companion) =>
      _db.into(_db.purchases).insertReturning(companion);
}
