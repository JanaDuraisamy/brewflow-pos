import 'package:brewflow_pos/core/database/app_database.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchase Items DAO
///
/// Read access to persisted purchase lines. Inserts happen inside the
/// purchase repository's receiving transaction (Phase 10 Step 5); the
/// single-insert helper exists for the DAO foundation and for the receiving
/// transaction to use.
/// ---------------------------------------------------------------------------

final class PurchaseItemsDao {
  PurchaseItemsDao(this._db);

  final AppDatabase _db;

  /// Lines of one purchase in the order they were inserted (insertion order
  /// is preserved by SQLite rowid ordering).
  Future<List<PurchaseItem>> byPurchase(String purchaseId, {String? shopId}) {
    final query = _db.select(_db.purchaseItems)
      ..where((t) => t.purchaseId.equals(purchaseId));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  /// Inserts a purchase line. The caller owns transaction semantics when
  /// multiple rows must commit together.
  Future<PurchaseItem> insert(PurchaseItemsCompanion companion) =>
      _db.into(_db.purchaseItems).insertReturning(companion);
}
