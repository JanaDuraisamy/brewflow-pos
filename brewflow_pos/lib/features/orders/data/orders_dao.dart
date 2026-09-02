import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Orders DAO
///
/// Read-only queries over the sales / sale_items tables written by the
/// Billing module. Filtering, search and pagination happen in SQLite so the
/// history list stays efficient at large volumes; no query here ever writes.
/// ---------------------------------------------------------------------------

final class OrdersDao {
  OrdersDao(this._db);

  final AppDatabase _db;

  /// Newest-first page of sales matching [search]/[paymentMethod]/[fromUtc]/
  /// [toUtc], truncated at [limit] rows starting at [offset].
  ///
  /// Search matches the receipt number and the persisted product-name
  /// snapshots (via an EXISTS sub-query, so joining is avoided entirely).
  Future<List<Sale>> salesPage({
    String search = '',
    String? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 50,
    int offset = 0,
    List<String>? shopIds,
  }) {
    final query = _db.select(_db.sales);
    query
      ..where(
        (t) => _matchesSales(
          t,
          search: search,
          paymentMethod: paymentMethod,
          fromUtc: fromUtc,
          toUtc: toUtc,
        ),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit, offset: offset);
    if (shopIds != null) {
      query.where((t) => t.shopId.isIn(shopIds));
    }
    return query.get();
  }

  /// Number of sold pieces per sale, for the given [saleIds].
  Future<Map<String, int>> itemCountsFor(Iterable<String> saleIds) async {
    final ids = saleIds.toList();
    if (ids.isEmpty) return const {};
    final query = _db.selectOnly(_db.saleItems)
      ..addColumns([_db.saleItems.saleId, _db.saleItems.quantity.sum()])
      ..where(_db.saleItems.saleId.isIn(ids))
      ..groupBy([_db.saleItems.saleId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.saleItems.saleId)!: row.read(
          _db.saleItems.quantity.sum(),
        )!,
    };
  }

  Future<Sale?> saleById(String id) {
    final query = _db.select(_db.sales)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Display names for the given customer ids. Ids with no matching row are
  /// absent from the map (customers are soft-deactivated, never deleted, so
  /// this only happens for legacy rows).
  Future<Map<String, String>> customerNamesFor(
    Iterable<String> customerIds,
  ) async {
    final ids = customerIds.toList();
    if (ids.isEmpty) return const {};
    final query = _db.select(_db.customers)..where((t) => t.id.isIn(ids));
    final rows = await query.get();
    return {for (final row in rows) row.id: row.name};
  }

  Future<String?> customerNameFor(String customerId) async =>
      (await customerNamesFor([customerId]))[customerId];

  Future<List<SaleItem>> itemsBySale(String saleId) {
    final query = _db.select(_db.saleItems)
      ..where((t) => t.saleId.equals(saleId));
    return query.get();
  }

  /// Shared WHERE expression for the sales table.
  ///
  /// LIKE wildcards in [search] are escaped so user input is matched
  /// literally; ASCII searches are case-insensitive by default in SQLite.
  /// Product-name matching uses an EXISTS sub-query over the sale items so
  /// the sales scan stays flat.
  Expression<bool> _matchesSales(
    $SalesTable t, {
    required String search,
    required String? paymentMethod,
    required DateTime? fromUtc,
    required DateTime? toUtc,
  }) {
    Expression<bool> expression = const Constant<bool>(true);
    final needle = search.trim();
    if (needle.isNotEmpty) {
      final pattern = '%${_escapeLike(needle)}%';
      final byReceipt = t.receiptNumber.like(pattern, escapeChar: r'\');
      final byProduct = existsQuery(
        _db.select(_db.saleItems)
          ..where(
            (item) =>
                item.saleId.equalsExp(t.id) &
                item.productName.like(pattern, escapeChar: r'\'),
          )
          ..limit(1),
      );
      expression = expression & (byReceipt | byProduct);
    }
    if (paymentMethod != null) {
      expression = expression & t.paymentMethod.equals(paymentMethod);
    }
    if (fromUtc != null) {
      expression = expression & t.createdAt.isBiggerOrEqualValue(fromUtc);
    }
    if (toUtc != null) {
      expression = expression & t.createdAt.isSmallerOrEqualValue(toUtc);
    }
    return expression;
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
