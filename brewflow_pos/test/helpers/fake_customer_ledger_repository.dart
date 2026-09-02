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
  });

  final String id;
  final String customerId;
  final String receiptNumber;
  final DateTime createdAt;
  final int totalPaise;
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

  /// When set, [dueCustomersSummary] throws this error.
  Object? dueSummaryError;

  /// Next payment id handed out.
  int _paymentSequence = 0;

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
    );
  }

  int _paidFor(String saleId) => storedPayments
      .where((p) => p.saleId == saleId && !p.reversed)
      .fold(0, (sum, p) => sum + p.amountPaise);
}
