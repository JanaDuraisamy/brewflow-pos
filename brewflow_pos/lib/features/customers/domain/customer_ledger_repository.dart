/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger Repository Contract
///
/// The single boundary between customer-ledger state/UI and the local Drift
/// database. Failures are always safe-to-display [CustomerLedgerFailure]
/// values; database details are never exposed to callers.
///
/// Semantics (locked in the Phase 8 architecture):
/// - Every payment is allocated to exactly one sale ([saleId] is required
///   here even though the DB column is nullable, reserving null for future
///   advance payments).
/// - Overpayment is rejected transactionally: a payment is written only when
///   amountPaise <= the sale's remaining due at write time.
/// - Payments are append-only; no edit, delete or reversal API exists.
/// - All due/outstanding values are derived (NOT_PAID sales totals minus
///   non-reversed payments), never persisted. A PAID sale never creates due.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

import 'customer_ledger_models.dart';

/// Base for all customer-ledger failures. Every subtype carries a user-safe
/// message.
sealed class CustomerLedgerFailure implements Exception {
  const CustomerLedgerFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Payment amount is zero or negative.
final class InvalidPaymentAmountFailure extends CustomerLedgerFailure {
  const InvalidPaymentAmountFailure([
    super.message = 'Enter an amount greater than zero.',
  ]);
}

/// Payment would exceed the sale's remaining due (includes concurrent
/// double-payment conflicts — same user-visible outcome).
final class PaymentExceedsDueFailure extends CustomerLedgerFailure {
  const PaymentExceedsDueFailure([
    super.message = 'This payment is more than the remaining balance.',
  ]);
}

/// The customer profile does not exist.
final class CustomerNotFoundFailure extends CustomerLedgerFailure {
  const CustomerNotFoundFailure([super.message = 'Customer not found.']);
}

/// The sale does not exist, or is not linked to this customer.
final class SaleNotFoundFailure extends CustomerLedgerFailure {
  const SaleNotFoundFailure([
    super.message = 'Bill not found for this customer.',
  ]);
}

/// Anything else — logged, and shown as a generic failure.
final class UnexpectedLedgerFailure extends CustomerLedgerFailure {
  const UnexpectedLedgerFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first customer ledger persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class CustomerLedgerRepository {
  /// Aggregated totals for one customer.
  ///
  /// Throws [CustomerNotFoundFailure] when the customer does not exist; a
  /// customer without sales or payments returns all-zero totals.
  Future<CustomerLedgerSummary> summary(String customerId);

  /// Customer-linked sales with allocated payment totals, newest first.
  Future<List<CustomerPurchase>> purchases(String customerId);

  /// Recorded payments for one customer, newest first.
  Future<List<CustomerPayment>> payments(String customerId);

  /// Records a payment of [amountPaise] against [saleId] for [customerId],
  /// atomically and race-safely.
  ///
  /// Throws [InvalidPaymentAmountFailure] for non-positive amounts,
  /// [CustomerNotFoundFailure] when the customer is missing,
  /// [SaleNotFoundFailure] when the sale is missing or not linked to the
  /// customer, and [PaymentExceedsDueFailure] when the payment would exceed
  /// the remaining due (including under concurrent submissions). On any
  /// failure nothing is written.
  Future<CustomerPayment> recordPayment({
    required String customerId,
    required String saleId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  });

  /// Remaining due of one customer across all customer-linked sales.
  Future<int> outstandingForCustomer(String customerId);

  /// Customers with outstanding balances and the total across all of them
  /// (dashboard Due Reminders surface).
  Future<DueCustomersSummary> dueCustomersSummary();

  /// Ids of customers that currently have an outstanding balance (> 0),
  /// derived from the same sales/payments aggregation as
  /// [dueCustomersSummary]. Includes deactivated customers — their debt
  /// still exists. The authoritative source for the customers-with-due
  /// list; callers join profiles through the customers repository.
  Future<List<String>> customerIdsWithDue();
}
