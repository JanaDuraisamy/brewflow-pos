import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';

/// One seeded bill (a customer-linked sale) a [FakeCustomerLedgerRepository]
/// knows about.
final class FakeLedgerBill {
  FakeLedgerBill({
    required this.id,
    required this.customerId,
    required this.receiptNumber,
    required this.createdAt,
    required this.totalPaise,
    this.customerName,
    this.phone,
    this.shopId,
    this.isOpeningBalance = false,
  });

  final String id;
  final String customerId;
  final String receiptNumber;
  final DateTime createdAt;
  final int totalPaise;

  /// Optional display name used by [FakeCustomerLedgerRepository.receivables]
  /// and [FakeCustomerLedgerRepository.outstandingAsOf]; defaults to the
  /// customer id when absent.
  final String? customerName;

  /// Optional phone surfaced by [FakeCustomerLedgerRepository.outstandingAsOf].
  final String? phone;

  /// Optional business/shop this bill belongs to. Mirrors the Drift query:
  /// when a shop scope is applied, only bills whose shop is in the scope
  /// count — a null shop is excluded exactly like SQL NULL inside an IN list.
  final String? shopId;

  /// True for opening-balance (pre-billing debt) entries, which participate
  /// in due exactly like open credit bills.
  final bool isOpeningBalance;
}

/// In-memory [CustomerLedgerRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// payments are validated against the seeded bills (sale must exist, belong
/// to the paying customer, and not be overpaid), dues are derived, and
/// configured failures ([recordPaymentError]) can be injected. Seed bills
/// through [bills]; payments accumulate in [payments].
final class FakeCustomerLedgerRepository implements CustomerLedgerRepository {
  final List<FakeLedgerBill> bills = [];
  final List<CustomerPayment> storedPayments = [];

  /// Customers that exist (mirrors the customers table); customers seeded
  /// through [bills] are always known.
  final Set<String> knownCustomers = {};

  /// When set, [recordPayment] throws this error before touching state.
  Object? recordPaymentError;

  /// When set, [collectCustomerPayment] throws this error before touching
  /// state.
  Object? collectError;

  /// When set, [dueCustomersSummary] throws this error.
  Object? dueSummaryError;

  /// When set, [outstandingAsOf] throws this error.
  Object? outstandingAsOfError;

  /// Next payment id handed out.
  int _paymentSequence = 0;

  /// Next opening-balance entry id handed out.
  int _openingSequence = 0;

  @override
  Future<CustomerLedgerSummary> summary(String customerId) async {
    final myBills = bills.where((b) => b.customerId == customerId).toList();
    final myPayments = storedPayments
        .where((p) => p.customerId == customerId && !p.reversed)
        .toList();
    final totalPurchases = myBills.fold(0, (sum, b) => sum + b.totalPaise);
    final totalPaid = myPayments.fold(0, (sum, p) => sum + p.amountPaise);
    return CustomerLedgerSummary(
      customerId: customerId,
      totalPurchasesPaise: totalPurchases,
      totalPaidPaise: totalPaid,
      outstandingPaise: totalPurchases - totalPaid,
      purchaseCount: myBills.length,
      paymentCount: myPayments.length,
    );
  }

  @override
  Future<List<CustomerPurchase>> purchases(String customerId) async {
    final myBills = bills.where((b) => b.customerId == customerId).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [for (final bill in myBills) _purchaseFor(bill)];
  }

  @override
  Future<List<CustomerPayment>> payments(String customerId) async {
    final result =
        storedPayments.where((p) => p.customerId == customerId).toList()
          ..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return result;
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
    final error = recordPaymentError;
    if (error != null) {
      throw error;
    }
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (!_isKnownCustomer(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    final bill = bills.where((b) => b.id == saleId).firstOrNull;
    if (bill == null || bill.customerId != customerId) {
      throw const SaleNotFoundFailure();
    }
    final paidSoFar = _paidFor(saleId);
    if (paidSoFar + amountPaise > bill.totalPaise) {
      throw const PaymentExceedsDueFailure();
    }
    final now = DateTime.now().toUtc();
    final payment = CustomerPayment(
      id: 'payment-${++_paymentSequence}',
      customerId: customerId,
      saleId: saleId,
      amountPaise: amountPaise,
      paymentMethod: paymentMethod,
      note: note,
      paidAt: now,
      reversed: false,
      reversedAt: null,
      createdAt: now,
      updatedAt: now,
    );
    storedPayments.add(payment);
    return payment;
  }

  @override
  Future<void> recordOpeningDue({
    required String customerId,
    required int amountPaise,
    String? shopId,
  }) async {
    final error = recordPaymentError;
    if (error != null) {
      throw error;
    }
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (!_isKnownCustomer(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    bills.add(
      FakeLedgerBill(
        id: 'opening-${++_openingSequence}',
        customerId: customerId,
        receiptNumber: 'BF-${9000 + _openingSequence}',
        createdAt: DateTime.now().toUtc(),
        totalPaise: amountPaise,
        isOpeningBalance: true,
      ),
    );
  }

  @override
  Future<List<CustomerPayment>> collectCustomerPayment({
    required String customerId,
    required String paymentGroupId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  }) async {
    final error = collectError;
    if (error != null) {
      throw error;
    }
    if (amountPaise <= 0) {
      throw const InvalidPaymentAmountFailure();
    }
    if (!_isKnownCustomer(customerId)) {
      throw const CustomerNotFoundFailure();
    }
    final existing = storedPayments
        .where((p) => p.paymentGroupId == paymentGroupId)
        .toList();
    if (existing.isNotEmpty) {
      return existing;
    }
    final openBills =
        bills
            .where((b) => b.customerId == customerId)
            .where((b) => _paidFor(b.id) < b.totalPaise)
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final outstanding = openBills.fold(
      0,
      (sum, b) => sum + b.totalPaise - _paidFor(b.id),
    );
    if (amountPaise > outstanding) {
      throw const PaymentExceedsDueFailure();
    }
    final now = DateTime.now().toUtc();
    var remaining = amountPaise;
    final created = <CustomerPayment>[];
    for (final bill in openBills) {
      if (remaining <= 0) {
        break;
      }
      final due = bill.totalPaise - _paidFor(bill.id);
      if (due <= 0) {
        continue;
      }
      final applied = remaining < due ? remaining : due;
      remaining -= applied;
      final payment = CustomerPayment(
        id: 'payment-${++_paymentSequence}',
        customerId: customerId,
        saleId: bill.id,
        amountPaise: applied,
        paymentMethod: paymentMethod,
        note: note,
        paidAt: now,
        reversed: false,
        reversedAt: null,
        paymentGroupId: paymentGroupId,
        createdAt: now,
        updatedAt: now,
      );
      storedPayments.add(payment);
      created.add(payment);
    }
    return created;
  }

  @override
  Future<List<CustomerReceivable>> receivables({
    List<String>? shopIds,
    DateTime? fromUtc,
    DateTime? toUtc,
  }) async {
    final error = dueSummaryError;
    if (error != null) {
      throw error;
    }
    final scoped = shopIds != null && shopIds.isNotEmpty;
    final groupings = <String, List<CustomerReceivableBill>>{};
    for (final bill in bills) {
      // Mirrors the DAO: candidate bills are bounded by the requested window
      // (inclusive, on the bill's own createdAt) and by the read scope.
      if (fromUtc != null && bill.createdAt.isBefore(fromUtc)) continue;
      if (toUtc != null && bill.createdAt.isAfter(toUtc)) continue;
      if (scoped && !shopIds.contains(bill.shopId)) continue;
      final due = bill.totalPaise - _paidFor(bill.id);
      if (due <= 0) {
        continue;
      }
      groupings
          .putIfAbsent(bill.customerId, () => [])
          .add(
            CustomerReceivableBill(
              saleId: bill.id,
              receiptNumber: bill.receiptNumber,
              createdAt: bill.createdAt,
              totalPaise: bill.totalPaise,
              duePaise: due,
              isOpeningBalance: bill.isOpeningBalance,
            ),
          );
    }
    final receivables = [
      for (final entry in groupings.entries)
        CustomerReceivable(
          customerId: entry.key,
          customerName:
              bills.firstWhere((b) => b.customerId == entry.key).customerName ??
              entry.key,
          outstandingBillCount: entry.value.length,
          totalDuePaise: entry.value.fold(
            0,
            (sum, bill) => sum + bill.duePaise,
          ),
          bills: entry.value
            ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
        ),
    ]..sort((a, b) => a.customerName.compareTo(b.customerName));
    return receivables;
  }

  @override
  Future<List<CustomerOutstandingBalance>> outstandingAsOf({
    required DateTime toUtc,
    List<String>? shopIds,
  }) async {
    final error = outstandingAsOfError;
    if (error != null) {
      throw error;
    }
    final dueByCustomer = <String, int>{};
    for (final bill in bills) {
      if (bill.createdAt.isAfter(toUtc)) {
        continue;
      }
      final scoped = shopIds != null && shopIds.isNotEmpty;
      if (scoped && !shopIds.contains(bill.shopId)) {
        continue;
      }
      final paidAsOf = storedPayments
          .where(
            (p) =>
                p.saleId == bill.id && !p.reversed && !p.paidAt.isAfter(toUtc),
          )
          .fold(0, (sum, p) => sum + p.amountPaise);
      final due = bill.totalPaise - paidAsOf;
      if (due <= 0) {
        continue;
      }
      dueByCustomer.update(
        bill.customerId,
        (total) => total + due,
        ifAbsent: () => due,
      );
    }
    if (dueByCustomer.isEmpty) {
      return const [];
    }
    final result = <CustomerOutstandingBalance>[
      for (final entry in dueByCustomer.entries)
        CustomerOutstandingBalance(
          customerId: entry.key,
          customerName: _nameFor(entry.key),
          phone: _phoneFor(entry.key),
          outstandingPaise: entry.value,
        ),
    ]..sort((a, b) => a.customerName.compareTo(b.customerName));
    return result;
  }

  String _nameFor(String customerId) {
    for (final bill in bills.where((b) => b.customerId == customerId)) {
      final name = bill.customerName;
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return customerId;
  }

  String? _phoneFor(String customerId) {
    for (final bill in bills.where((b) => b.customerId == customerId)) {
      if (bill.phone != null) {
        return bill.phone;
      }
    }
    return null;
  }

  @override
  Future<int> outstandingForCustomer(String customerId) async {
    final ledgerSummary = await summary(customerId);
    return ledgerSummary.outstandingPaise;
  }

  @override
  Future<DueCustomersSummary> dueCustomersSummary() async {
    final error = dueSummaryError;
    if (error != null) {
      throw error;
    }
    var count = 0;
    var total = 0;
    final customerIds = bills.map((b) => b.customerId).toSet();
    for (final customerId in customerIds) {
      final outstanding = await outstandingForCustomer(customerId);
      if (outstanding > 0) {
        count += 1;
        total += outstanding;
      }
    }
    return DueCustomersSummary(
      dueCustomerCount: count,
      totalOutstandingPaise: total,
    );
  }

  @override
  Future<List<String>> customerIdsWithDue() async {
    final error = dueSummaryError;
    if (error != null) {
      throw error;
    }
    final ids = <String>{};
    for (final customerId in bills.map((b) => b.customerId).toSet()) {
      if (await outstandingForCustomer(customerId) > 0) {
        ids.add(customerId);
      }
    }
    return ids.toList()..sort();
  }

  bool _isKnownCustomer(String customerId) =>
      knownCustomers.contains(customerId) ||
      bills.any((b) => b.customerId == customerId);

  CustomerPurchase _purchaseFor(FakeLedgerBill bill) {
    final paidPaise = _paidFor(bill.id);
    final duePaise = bill.totalPaise - paidPaise;
    final status = paidPaise <= 0
        ? SalePaymentStatus.unpaid
        : paidPaise >= bill.totalPaise
        ? SalePaymentStatus.paid
        : SalePaymentStatus.partial;
    return CustomerPurchase(
      saleId: bill.id,
      receiptNumber: bill.receiptNumber,
      customerId: bill.customerId,
      createdAt: bill.createdAt,
      totalPaise: bill.totalPaise,
      paidPaise: paidPaise,
      duePaise: duePaise,
      status: status,
      isOpeningBalance: bill.isOpeningBalance,
    );
  }

  int _paidFor(String saleId) => storedPayments
      .where((p) => p.saleId == saleId && !p.reversed)
      .fold(0, (sum, p) => sum + p.amountPaise);
}
