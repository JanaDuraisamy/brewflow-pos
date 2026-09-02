import 'package:brewflow_pos/core/database/app_database.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sale Items DAO
///
/// Read access to persisted sale lines. Inserts happen inside the billing
/// repository's checkout transaction.
/// ---------------------------------------------------------------------------

final class SaleItemsDao {
  SaleItemsDao(this._db);

  final AppDatabase _db;

  /// Lines of one sale in the order they were inserted (insertion order is
  /// preserved by SQLite rowid ordering).
  Future<List<SaleItem>> bySale(String saleId, {String? shopId}) {
    final query = _db.select(_db.saleItems)
      ..where((t) => t.saleId.equals(saleId));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }
}
