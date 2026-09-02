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
  ///
  /// Only NOT_PAID (credit) sales contribute to a customer's debt. A PAID sale
  /// is settled immediately at the counter — it never creates due — so it is
  /// excluded here. Payments recorded on a credit sale move it to PAID via
  /// [DriftCustomerLedgerRepository._recordPaymentCore], dropping it from the
  /// debt total exactly when it is fully settled.
  Future<({int count, int totalPaise})?> salesAggregateFor(
    String customerId,
  ) async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count(), _db.sales.totalPaise.sum()])
      ..where(
        _db.sales.customerId.equals(customerId) &
            _db.sales.paymentStatus.equals('NOT_PAID'),
      );
    final row = await query.getSingle();
    final count = row.read(_db.sales.id.count())!;
    if (count == 0) return null;
    return (count: count, totalPaise: row.read(_db.sales.totalPaise.sum())!);
  }

  /// Count and total of one customer's non-reversed payments; null when
  /// there are none.
  ///
  /// Only payments on still-open NOT_PAID (credit) sales offset a customer's
  /// debt. A payment that fully settles a credit bill flips that sale to PAID
  /// (see [DriftCustomerLedgerRepository._recordPaymentCore]); from then on
  /// both the sale's debt and its payment rows drop out, so outstanding can
  /// never go negative.
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
            _db.customerPayments.reversed.equals(false) &
            _isOpenCreditSale(_db.customerPayments.saleId),
      );
    final row = await query.getSingle();
    final count = row.read(_db.customerPayments.id.count())!;
    if (count == 0) return null;
    return (
      count: count,
      totalPaise: row.read(_db.customerPayments.amountPaise.sum())!,
    );
  }

  /// True when the given payment's sale row is still NOT_PAID (open credit).
  /// Payments on settled (PAID) sales no longer offset any outstanding.
  /// Null `saleId`s (reserved for future advance payments) never offset debt.
  Expression<bool> _isOpenCreditSale(Column<String> saleId) {
    final salesTable = _db.sales;
    return saleId.isInQuery(
      _db.selectOnly(salesTable)
        ..addColumns([salesTable.id])
        ..where(salesTable.paymentStatus.equals('NOT_PAID')),
    );
  }

  /// Sum of NOT_PAID (credit) sale totals per customer. PAID sales never
  /// create debt and are excluded.
  Future<Map<String, int>> salesTotalsByCustomer() async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.customerId, _db.sales.totalPaise.sum()])
      ..where(
        _db.sales.customerId.isNotNull() &
            _db.sales.paymentStatus.equals('NOT_PAID'),
      )
      ..groupBy([_db.sales.customerId]);
    final rows = await query.get();
    return {
      for (final row in rows)
        row.read(_db.sales.customerId)!: row.read(_db.sales.totalPaise.sum())!,
    };
  }

  /// Sum of non-reversed payments per customer, restricted to payments on
  /// still-open NOT_PAID (credit) sales. Payments on settled (PAID) sales no
  /// longer offset any outstanding, so a fully-settled bill stays at zero.
  Future<Map<String, int>> paymentsTotalByCustomer() async {
    final query = _db.selectOnly(_db.customerPayments)
      ..addColumns([
        _db.customerPayments.customerId,
        _db.customerPayments.amountPaise.sum(),
      ])
      ..where(
        _db.customerPayments.reversed.equals(false) &
            _isOpenCreditSale(_db.customerPayments.saleId),
      )
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
