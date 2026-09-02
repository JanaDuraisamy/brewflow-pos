import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/data/customer_ledger_dao.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Customer Ledger Repository
///
/// Implements [CustomerLedgerRepository] on the local Drift database.
///
/// All reads are SQL aggregations over the sales and customer_payments
/// tables (never whole-table loads); every due/outstanding value is derived,
/// never stored. Only NOT_PAID (credit) sales count toward debt — a PAID sale
/// is settled at the counter and never increases a customer's due. All
/// failures are translated into safe [CustomerLedgerFailure] values (details
/// logged via [AppLog], never shown).
///
/// Sync: when a [SyncOutboxCoordinator] is provided, recordPayment appends
/// its outbox row in the SAME database transaction as the business change;
/// without one the repository behaves exactly as before (offline-first, tests,
/// signed-out usage).
///
/// recordPayment runs inside a single transaction: the sale is re-read and
/// checked against the paying customer, then a database-level conditional
/// UPDATE re-validates the remaining due against the latest committed
/// payments before the payment row is inserted — everything commits together
/// or rolls back together. The guard mirrors the checkout stock-deduction
/// guard in the billing repository, so concurrent payments cannot
/// collectively exceed a sale's total.
/// ---------------------------------------------------------------------------

final class DriftCustomerLedgerRepository implements CustomerLedgerRepository {
  DriftCustomerLedgerRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _dao = CustomerLedgerDao(database),
       _database = database,
       _outbox = outboxCoordinator;

  static const String tag = 'Ledger';

  final CustomerLedgerDao _dao;
  final db.AppDatabase _database;
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<CustomerLedgerSummary> summary(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesAggregateFor(customerId);
      final payments = await _dao.paymentsAggregateFor(customerId);
      final totalPurchases = sales?.totalPaise ?? 0;
      final totalPaid = payments?.totalPaise ?? 0;
      return CustomerLedgerSummary(
        customerId: customerId,
        totalPurchasesPaise: totalPurchases,
        totalPaidPaise: totalPaid,
        outstandingPaise: totalPurchases - totalPaid,
        purchaseCount: sales?.count ?? 0,
        paymentCount: payments?.count ?? 0,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load ledger summary', error, stackTrace);
    }
  }

  @override
  Future<List<CustomerPurchase>> purchases(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesFor(customerId);
      final paid = await _dao.paidPerSale(sales.map((sale) => sale.id));
      return [
        for (final sale in sales) _purchaseFrom(sale, paid[sale.id] ?? 0),
      ];
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load purchase history', error, stackTrace);
    }
  }

  @override
  Future<List<CustomerPayment>> payments(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final rows = await _dao.paymentsFor(customerId);
      return rows.map(_paymentFromRow).toList();
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load payment history', error, stackTrace);
    }
  }

  @override
  Future<CustomerPayment> recordPayment({
    required String customerId,
    required String saleId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  }) async {
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    final normalizedNote = _optionalText(note);
    final resolvedShopId = await resolveWritableShopId(_database, shopId);
    try {
      final payment = await (_outbox == null
          ? _database.transaction(
              () => _recordPaymentCore(
                customerId,
                saleId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
            )
          : _outbox.run(
              write: () => _recordPaymentCore(
                customerId,
                saleId,
                amountPaise,
                paymentMethod,
                normalizedNote,
                resolvedShopId,
              ),
              snapshots: (payment, ctx) async => [
                OutboxAppend(
                  entity: MasterEntity.customerPayment,
                  entityId: payment.id,
                  payload: SyncCustomerPayment(
                    id: payment.id,
                    shopId: ctx.shopId,
                    customerId: payment.customerId,
                    saleId: payment.saleId,
                    amountPaise: payment.amountPaise,
                    paymentMethod: payment.paymentMethod.dbValue,
                    note: payment.note,
                    paidAt: payment.paidAt,
                    reversed: payment.reversed,
                    reversedAt: payment.reversedAt,
                    createdAt: payment.createdAt,
                  ).toJson(),
                ),
              ],
            ));
      return payment;
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record payment', error, stackTrace);
    }
  }

  Future<CustomerPayment> _recordPaymentCore(
    String customerId,
    String saleId,
    int amountPaise,
    PaymentMethod paymentMethod,
    String? normalizedNote,
    String shopId,
  ) async {
    if (!await _dao.customerExists(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    final sale = await _dao.saleById(saleId);
    if (sale == null || sale.customerId != customerId) {
      throw const SaleNotFoundFailure();
    }

    final now = DateTime.now().toUtc();

    // Race-safe remaining-due guard: SQLite re-evaluates the subquery
    // against the latest committed payments at write time, so two
    // concurrent payments serialize — the loser matches zero rows here
    // and is rejected instead of overpaying the sale.
    final updated = await _database.customUpdate(
      'UPDATE sales SET updated_at = ? WHERE id = ? AND '
      'total_paise - (SELECT COALESCE(SUM(amount_paise), 0) '
      'FROM customer_payments WHERE sale_id = ? AND reversed = 0) >= ?',
      variables: [
        Variable.withDateTime(now),
        Variable.withString(saleId),
        Variable.withString(saleId),
        Variable.withInt(amountPaise),
      ],
      updateKind: UpdateKind.update,
    );
    if (updated != 1) {
      throw const PaymentExceedsDueFailure();
    }

    final id = const Uuid().v4();
    await _database
        .into(_database.customerPayments)
        .insert(
          db.CustomerPaymentsCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            customerId: customerId,
            saleId: Value(saleId),
            amountPaise: amountPaise,
            paymentMethod: paymentMethod.dbValue,
            note: Value(normalizedNote),
            paidAt: now,
            reversed: const Value(false),
            reversedAt: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    // Settle the AUTHORITATIVE bill state when this payment clears the
    // total: orders/receipt read sales.payment_status, so it must move
    // to PAID here — in the same transaction as the payment insert —
    // otherwise every derived view would keep showing a stale
    // "Not paid". Partial payments intentionally leave NOT_PAID (the
    // ledger already derives the partial amount from history), and a
    // fully-paid sale keeps its original receipt number and line items
    // untouched.
    final paidSoFar = await _database
        .customSelect(
          'SELECT COALESCE(SUM(amount_paise), 0) AS paid '
          'FROM customer_payments WHERE sale_id = ? AND reversed = 0',
          variables: [Variable.withString(saleId)],
        )
        .getSingle();
    final settled = (paidSoFar.data['paid'] as int? ?? 0) >= sale.totalPaise;
    if (settled && sale.paymentStatus != 'PAID') {
      await (_database.update(
        _database.sales,
      )..where((t) => t.id.equals(saleId))).write(
        db.SalesCompanion(
          paymentStatus: const Value('PAID'),
          paymentMethod: Value(paymentMethod.dbValue),
          updatedAt: Value(now),
        ),
      );
    }

    return CustomerPayment(
      id: id,
      customerId: customerId,
      saleId: saleId,
      amountPaise: amountPaise,
      paymentMethod: paymentMethod,
      note: normalizedNote,
      paidAt: now,
      reversed: false,
      reversedAt: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  @override
  Future<int> outstandingForCustomer(String customerId) async {
    try {
      if (!await _dao.customerExists(customerId)) {
        throw const CustomerNotFoundFailure();
      }
      final sales = await _dao.salesAggregateFor(customerId);
      final payments = await _dao.paymentsAggregateFor(customerId);
      return (sales?.totalPaise ?? 0) - (payments?.totalPaise ?? 0);
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load outstanding balance',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<DueCustomersSummary> dueCustomersSummary() async {
    try {
      final sales = await _dao.salesTotalsByCustomer();
      final payments = await _dao.paymentsTotalByCustomer();
      var dueCustomerCount = 0;
      var totalOutstandingPaise = 0;
      for (final entry in sales.entries) {
        final outstanding = entry.value - (payments[entry.key] ?? 0);
        if (outstanding > 0) {
          dueCustomerCount += 1;
          totalOutstandingPaise += outstanding;
        }
      }
      return DueCustomersSummary(
        dueCustomerCount: dueCustomerCount,
        totalOutstandingPaise: totalOutstandingPaise,
      );
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected(
        'Failed to load due customers summary',
        error,
        stackTrace,
      );
    }
  }

  @override
  Future<List<String>> customerIdsWithDue() async {
    try {
      final sales = await _dao.salesTotalsByCustomer();
      final payments = await _dao.paymentsTotalByCustomer();
      return [
        for (final entry in sales.entries)
          if (entry.value - (payments[entry.key] ?? 0) > 0) entry.key,
      ]..sort();
    } on CustomerLedgerFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load due customers', error, stackTrace);
    }
  }

  /// Returns trimmed non-empty text, or null when blank.
  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedLedgerFailure();
  }

  static CustomerPurchase _purchaseFrom(db.Sale sale, int paidPaise) {
    // The authoritative `sales.payment_status` decides whether debt exists: a
    // PAID sale is settled at the counter and carries no due, regardless of
    // any ledger payment rows. Only NOT_PAID (credit) sales derive due from
    // their payments history.
    final isSettledAtCounter = sale.paymentStatus == 'PAID';
    final duePaise = isSettledAtCounter ? 0 : sale.totalPaise - paidPaise;
    final status = isSettledAtCounter
        ? SalePaymentStatus.paid
        : paidPaise <= 0
        ? SalePaymentStatus.unpaid
        : paidPaise >= sale.totalPaise
        ? SalePaymentStatus.paid
        : SalePaymentStatus.partial;
    return CustomerPurchase(
      saleId: sale.id,
      receiptNumber: sale.receiptNumber,
      customerId: sale.customerId!,
      createdAt: sale.createdAt,
      totalPaise: sale.totalPaise,
      paidPaise: isSettledAtCounter ? sale.totalPaise : paidPaise,
      duePaise: duePaise,
      status: status,
    );
  }

  static CustomerPayment _paymentFromRow(db.CustomerPayment row) =>
      CustomerPayment(
        id: row.id,
        customerId: row.customerId,
        saleId: row.saleId!,
        amountPaise: row.amountPaise,
        paymentMethod: PaymentMethod.fromDbValue(row.paymentMethod)!,
        note: row.note,
        paidAt: row.paidAt,
        reversed: row.reversed,
        reversedAt: row.reversedAt,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
