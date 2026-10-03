import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart'
    hide CustomerPayment;
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

  /// All non-voided sales linked to one customer, newest first.
  ///
  /// Voided sales generate no due (the same `voided = false` premise the
  /// collection RPC and [openCreditSalesFor] enforce), so they are excluded
  /// from the ledger's purchase history.
  Future<List<Sale>> salesFor(String customerId) {
    final query = _db.select(_db.sales)
      ..where((t) => t.customerId.equals(customerId) & t.voided.equals(false))
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
  ///
  /// Voided sales are excluded too: the authoritative collection RPC only ever
  /// aggregates `voided = false` sales, so anything else would make the local
  /// deadline look higher than what can actually be collected.
  Future<({int count, int totalPaise})?> salesAggregateFor(
    String customerId,
  ) async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.id.count(), _db.sales.totalPaise.sum()])
      ..where(
        _db.sales.customerId.equals(customerId) &
            _db.sales.paymentStatus.equals('NOT_PAID') &
            _db.sales.voided.equals(false),
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
  /// Voided sales never accept collection (same `voided = false` premise as
  /// the collection RPC and [openCreditSalesFor]), so they are excluded too.
  Expression<bool> _isOpenCreditSale(
    Column<String> saleId, [
    List<String>? shopIds,
  ]) {
    final salesTable = _db.sales;
    return saleId.isInQuery(
      _db.selectOnly(salesTable)
        ..addColumns([salesTable.id])
        ..where(
          salesTable.paymentStatus.equals('NOT_PAID') &
              salesTable.voided.equals(false) &
              (shopIds != null
                  ? salesTable.shopId.isIn(shopIds)
                  : const Constant(true)),
        ),
    );
  }

  /// Sum of NOT_PAID (credit) sale totals per customer. PAID sales never
  /// create debt and are excluded, as are voided sales (the collection RPC
  /// only ever aggregates `voided = false`).
  Future<Map<String, int>> salesTotalsByCustomer({
    List<String>? shopIds,
  }) async {
    final query = _db.selectOnly(_db.sales)
      ..addColumns([_db.sales.customerId, _db.sales.totalPaise.sum()])
      ..where(
        _db.sales.customerId.isNotNull() &
            _db.sales.paymentStatus.equals('NOT_PAID') &
            _db.sales.voided.equals(false) &
            (shopIds != null
                ? _db.sales.shopId.isIn(shopIds)
                : const Constant(true)),
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
  Future<Map<String, int>> paymentsTotalByCustomer({
    List<String>? shopIds,
  }) async {
    final query = _db.selectOnly(_db.customerPayments)
      ..addColumns([
        _db.customerPayments.customerId,
        _db.customerPayments.amountPaise.sum(),
      ])
      ..where(
        _db.customerPayments.reversed.equals(false) &
            _isOpenCreditSale(_db.customerPayments.saleId, shopIds),
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

  /// A customer's open credit bills — NOT_PAID, non-voided — oldest first.
  ///
  /// This is the allocation queue for customer-level collections: a
  /// [DriftCustomerLedgerRepository.collectCustomerPayment] walk orders the
  /// same way, so due is cleared from the oldest bill before the next.
  Future<List<Sale>> openCreditSalesFor(String customerId) {
    final query = _db.select(_db.sales)
      ..where(
        (t) =>
            t.customerId.equals(customerId) &
            t.paymentStatus.equals('NOT_PAID') &
            t.voided.equals(false),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Every payment row sharing one [paymentGroupId] (in creation order).
  ///
  /// A group is the whole unit of a customer-level collection. It is always
  /// committed atomically, so the group is either fully present or fully
  /// absent locally; this query is the idempotent-replay guard.
  Future<List<CustomerPayment>> paymentsForGroup(String paymentGroupId) {
    final query = _db.select(_db.customerPayments)
      ..where((t) => t.paymentGroupId.equals(paymentGroupId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    return query.get();
  }

  /// Every customer with an outstanding balance, read-only and optionally
  /// bounded to the credit bills raised inside one window.
  ///
  /// Open NOT_PAID, non-voided credit sales generate due; each customer's row
  /// carries the per-bill drill-down (oldest bill first) so the Receivables
  /// report section can show exactly which bills are still owed on. [shopIds]
  /// restricts the scan to the given businesses; null/empty scans everything
  /// locally (single-shop devices).
  ///
  /// [fromUtc]/[toUtc] (both inclusive, UTC) filter the candidate bills by
  /// their own `createdAt` — the same sale-date semantics the sales windows
  /// use, deliberately not a second definition. The due derivation below is
  /// unchanged: a bill already collected in full is no longer NOT_PAID, so it
  /// drops out on its own, and a part-paid bill contributes only what is left.
  /// Bill counts and totals are therefore scoped to the window as well.
  Future<List<CustomerReceivable>> receivables(
    List<String>? shopIds, {
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    final query = _db.select(_db.sales)
      ..where(
        (t) =>
            t.customerId.isNotNull() &
            t.paymentStatus.equals('NOT_PAID') &
            t.voided.equals(false) &
            (fromUtc != null
                ? t.createdAt.isBiggerOrEqualValue(fromUtc)
                : const Constant(true)) &
            (toUtc != null
                ? t.createdAt.isSmallerOrEqualValue(toUtc)
                : const Constant(true)) &
            (shopIds != null ? t.shopId.isIn(shopIds) : const Constant(true)),
      )
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    final openSales = await query.get();
    if (openSales.isEmpty) return const [];

    final openIds = openSales.map((s) => s.id);
    final paidBySale = await paidPerSale(openIds);

    final customerIds = openSales.map((s) => s.customerId!).toSet().toList();
    final customers = await (_db.select(
      _db.customers,
    )..where((t) => t.id.isIn(customerIds))).get();
    final nameById = {for (final c in customers) c.id: c.name};

    final billsByCustomer = <String, List<CustomerReceivableBill>>{};
    for (final sale in openSales) {
      final due = sale.totalPaise - (paidBySale[sale.id] ?? 0);
      if (due <= 0) continue;
      billsByCustomer
          .putIfAbsent(sale.customerId!, () => [])
          .add(
            CustomerReceivableBill(
              saleId: sale.id,
              receiptNumber: sale.receiptNumber,
              createdAt: sale.createdAt,
              totalPaise: sale.totalPaise,
              duePaise: due,
              isOpeningBalance: sale.isOpeningBalance,
            ),
          );
    }

    final result = <CustomerReceivable>[
      for (final entry in billsByCustomer.entries)
        CustomerReceivable(
          customerId: entry.key,
          // A customer-linked sale whose customer row no longer exists: the
          // customer was genuinely deleted (schema v25 -> v26), while the debt
          // they left behind stays owed and collectible. Naming the reason is
          // better than a bare 'Customer', which is indistinguishable from a
          // blank name and would send an owner hunting for a missing record.
          customerName: nameById[entry.key] ?? 'Deleted customer',
          outstandingBillCount: entry.value.length,
          totalDuePaise: entry.value.fold(
            0,
            (sum, bill) => sum + bill.duePaise,
          ),
          bills: entry.value,
        ),
    ];
    result.sort((a, b) => a.customerName.compareTo(b.customerName));
    return result;
  }

  /// Customer-wise outstanding balances exactly as of [toUtc] — the
  /// date-bounded variant of [receivables] behind the management report.
  ///
  /// Candidate sales are customer-linked, non-voided and created on/before
  /// [toUtc]. A sale settled at the counter (PAID with no payment rows) never
  /// generates due. A credit bill — still open (`NOT_PAID`) or since collected
  /// (carries payment rows) — contributes its total minus the non-reversed
  /// payments recorded on/before [toUtc]; because a fully-collected bill keeps
  /// its payment history, a bill settled after [toUtc] still shows the full
  /// as-of-date amount. Only balances > 0 survive, ordered by customer name.
  Future<List<CustomerOutstandingBalance>> outstandingAsOf(
    DateTime toUtc,
    List<String>? shopIds,
  ) async {
    final query = _db.select(_db.sales)
      ..where(
        (t) =>
            t.customerId.isNotNull() &
            t.voided.equals(false) &
            t.createdAt.isSmallerOrEqualValue(toUtc) &
            (shopIds != null ? t.shopId.isIn(shopIds) : const Constant(true)),
      );
    final sales = await query.get();
    if (sales.isEmpty) return const [];

    final saleIds = sales.map((s) => s.id);
    final payments = await (_db.select(
      _db.customerPayments,
    )..where((t) => t.saleId.isIn(saleIds) & t.reversed.equals(false))).get();

    final paidAsOfBySale = <String, int>{};
    final collectedSaleIds = <String>{};
    for (final row in payments) {
      collectedSaleIds.add(row.saleId!);
      if (!row.paidAt.isAfter(toUtc)) {
        paidAsOfBySale.update(
          row.saleId!,
          (total) => total + row.amountPaise,
          ifAbsent: () => row.amountPaise,
        );
      }
    }

    final dueByCustomer = <String, int>{};
    for (final sale in sales) {
      final counterSettled =
          sale.paymentStatus == 'PAID' && !collectedSaleIds.contains(sale.id);
      if (counterSettled) continue;
      final due = sale.totalPaise - (paidAsOfBySale[sale.id] ?? 0);
      if (due <= 0) continue;
      dueByCustomer.update(
        sale.customerId!,
        (total) => total + due,
        ifAbsent: () => due,
      );
    }
    if (dueByCustomer.isEmpty) return const [];

    final customers = await (_db.select(
      _db.customers,
    )..where((t) => t.id.isIn(dueByCustomer.keys))).get();
    final customerById = {for (final c in customers) c.id: c};

    final result = <CustomerOutstandingBalance>[
      for (final entry in dueByCustomer.entries)
        CustomerOutstandingBalance(
          customerId: entry.key,
          customerName: customerById[entry.key]?.name ?? 'Customer',
          phone: customerById[entry.key]?.phone,
          outstandingPaise: entry.value,
        ),
    ];
    result.sort((a, b) => a.customerName.compareTo(b.customerName));
    return result;
  }
}
