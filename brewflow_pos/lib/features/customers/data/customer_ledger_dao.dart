import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger DAO
///
/// All Drift reads for the customer ledger. Aggregations run in SQLite
/// (never in memory over whole tables); writes happen inside the ledger
/// repository's payment transaction, so no insert lives here.
/// ---------------------------------------------------------------------------

final class CustomerLedgerDao {
  CustomerLedgerDao(this._db);

  final AppDatabase _db;

  Future<bool> customerExists(String id) async {
    final query = _db.selectOnly(_db.customers)..addColumns([_db.customers.id]);
    query.where(_db.customers.id.equals(id));
    query.limit(1);
    return (await query.get()).isNotEmpty;
  }

  /// All sales linked to one customer, newest first.
  Future<List<Sale>> salesFor(String customerId) {
    final query = _db.select(_db.sales)
      ..where((t) => t.customerId.equals(customerId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  Future<Sale?> saleById(String id) {
    final query = _db.select(_db.sales)
      ..where((t) => t.id.equals(id))
      ..limit(1);
    return query.getSingleOrNull();
  }

  /// Sum of non-reversed payments per sale, for the given [saleIds].
  Future<Map<String, int>> paidPerSale(Iterable<String> saleIds) async {
    final ids = saleIds.toList();
    if (ids.isEmpty) return const {};
    final query = _db.selectOnly(_db.customerPayments)
      ..addColumns([
        _db.customerPayments.saleId,
        _db.customerPayments.amountPaise.sum(),
      ])
      ..where(
        _db.customerPayments.saleId.isIn(ids) &
            _db.customerPayments.reversed.equals(false),
      )
      ..groupBy([_db.customerPayments.saleId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.customerPayments.saleId)!: row.read(
          _db.customerPayments.amountPaise.sum(),
        )!,
    };
  }

  /// All payments of one customer, newest first.
  Future<List<CustomerPayment>> paymentsFor(String customerId) {
    final query = _db.select(_db.customerPayments)
      ..where((t) => t.customerId.equals(customerId))
      ..orderBy([
        (t) => OrderingTerm.desc(t.paidAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    return query.get();
  }

  /// Count and total of one customer's sales; null when there are none.
  Future<({int count, int totalPaise})?> salesAggregateFor(
    String customerId,
  ) async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count(), _db.sales.totalPaise.sum()])
      ..where(_db.sales.customerId.equals(customerId));
    final row = await query.getSingle();
    final count = row.read(_db.sales.id.count())!;
    if (count == 0) return null;
    return (count: count, totalPaise: row.read(_db.sales.totalPaise.sum())!);
  }

  /// Count and total of one customer's non-reversed payments; null when
  /// there are none.
  Future<({int count, int totalPaise})?> paymentsAggregateFor(
    String customerId,
  ) async {
    final query = _db.selectOnly(_db.customerPayments)
      ..addColumns([
        _db.customerPayments.id.count(),
        _db.customerPayments.amountPaise.sum(),
      ])
      ..where(
        _db.customerPayments.customerId.equals(customerId) &
            _db.customerPayments.reversed.equals(false),
      );
    final row = await query.getSingle();
    final count = row.read(_db.customerPayments.id.count())!;
    if (count == 0) return null;
    return (
      count: count,
      totalPaise: row.read(_db.customerPayments.amountPaise.sum())!,
    );
  }

  /// Sum of sale totals per customer (customer-linked sales only).
  Future<Map<String, int>> salesTotalsByCustomer() async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.customerId, _db.sales.totalPaise.sum()])
      ..where(_db.sales.customerId.isNotNull())
      ..groupBy([_db.sales.customerId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.sales.customerId)!: row.read(_db.sales.totalPaise.sum())!,
    };
  }

  /// Sum of non-reversed payments per customer.
  Future<Map<String, int>> paymentsTotalByCustomer() async {
    final query = _db.selectOnly(_db.customerPayments)
      ..addColumns([
        _db.customerPayments.customerId,
        _db.customerPayments.amountPaise.sum(),
      ])
      ..where(_db.customerPayments.reversed.equals(false))
      ..groupBy([_db.customerPayments.customerId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.customerPayments.customerId)!: row.read(
          _db.customerPayments.amountPaise.sum(),
        )!,
    };
  }
}
