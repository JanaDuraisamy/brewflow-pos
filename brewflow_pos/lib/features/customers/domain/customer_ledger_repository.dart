/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger Repository Contract
///
/// The single boundary between customer-ledger state/UI and the local Drift
/// database. Failures are always safe-to-display [CustomerLedgerFailure]
/// values; database details are never exposed to callers.
///
/// Semantics (locked in the Phase 8 architecture):
/// - Every payment row is allocated to exactly one sale ([saleId] is required
///   in [recordPayment], and a customer-level collection is split into one
///   row per bill — the DB column stays nullable, reserving null for future
///   advance payments).
/// - Overpayment is rejected transactionally: a payment is written only when
///   it fits the outstanding balance at write time.
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

  /// Records [amountPaise] as [customerId]'s opening balance — a debt that
  /// existed before the shop started on BrewFlow, NOT a counter sale.
  ///
  /// The entry is ledger-only: it carries no sale items (so no stock is ever
  /// deducted and no receipt is produced), never appears in Orders, Reports or
  /// Sales totals, and yet it flows through the exact same NOT_PAID
  /// derivation as a credit sale — it adds to [summary], [outstandingForCustomer]
  /// and [dueCustomersSummary], and a [collectCustomerPayment] pays it down
  /// exactly like any open bill.
  ///
  /// Throws [InvalidPaymentAmountFailure] for non-positive amounts and
  /// [CustomerNotFoundFailure] when the customer is missing. On failure
  /// nothing is written.
  Future<void> recordOpeningDue({
    required String customerId,
    required int amountPaise,
    String? shopId,
  });

  /// Collects [amountPaise] against [customerId]'s total outstanding, in one
  /// atomic submission.
  ///
  /// The amount may be any positive value up to the customer's full
  /// outstanding balance and is allocated against the OLDEST open (NOT_PAID,
  /// non-voided) bills first; every touched bill receives one payment row,
  /// and a bill whose due is cleared is moved to PAID in the same
  /// transaction. All rows share [paymentGroupId], making the submission one
  /// idempotent unit: replaying the same group is a no-op returning the
  /// existing rows, so a retried save can never double-charge.
  ///
  /// Throws [InvalidPaymentAmountFailure] for non-positive amounts,
  /// [CustomerNotFoundFailure] when the customer is missing, and
  /// [PaymentExceedsDueFailure] when the amount exceeds the total outstanding
  /// (including under concurrent submissions). On any failure nothing is
  /// written. Returns the created per-bill payment rows (empty never).
  Future<List<CustomerPayment>> collectCustomerPayment({
    required String customerId,
    required String paymentGroupId,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    String? note,
    String? shopId,
  });

  /// Remaining due of one customer across all customer-linked sales.
  Future<int> outstandingForCustomer(String customerId);

  /// Every customer with an outstanding balance and their open bills,
  /// current (not window-bounded) and read-only.
  ///
  /// Only open NOT_PAID, non-voided credit sales generate due; rows keep the
  /// per-bill drill-down (oldest bill first) so the Receivables report can
  /// show exactly which bills each customer still owes on. Customers are
  /// ordered by name. [shopIds] restricts the read to the given businesses;
  /// when null the whole local database is scanned (single-shop devices).
  Future<List<CustomerReceivable>> receivables({List<String>? shopIds});

  /// Customers with outstanding balances and the total across all of them
  /// (dashboard Due Reminders surface).
  Future<DueCustomersSummary> dueCustomersSummary();

  /// Customer-wise outstanding balances exactly as of [toUtc] (read-only,
  /// the management report's Customer Outstanding snapshot).
  ///
  /// Same sales/payments derivation family as [receivables], but date-bounded:
  /// only customer-linked, non-voided sales created on/before [toUtc] count,
  /// and only non-reversed payments recorded on/before [toUtc] offset them —
  /// so sales created after the snapshot date and payments made after it never
  /// affect the balance. A credit bill collected in full after [toUtc] keeps
  /// its whole as-of-date balance; a sale settled at the counter (PAID with no
  /// payment rows) never generates due. Rows are limited to balances > 0 and
  /// ordered by customer name. [shopIds] restricts the scan to the given
  /// businesses; null/empty scans everything locally.
  Future<List<CustomerOutstandingBalance>> outstandingAsOf({
    required DateTime toUtc,
    List<String>? shopIds,
  });

  /// Ids of customers that currently have an outstanding balance (> 0),
  /// derived from the same sales/payments aggregation as
  /// [dueCustomersSummary]. Includes deactivated customers — their debt
  /// still exists. The authoritative source for the customers-with-due
  /// list; callers join profiles through the customers repository.
  Future<List<String>> customerIdsWithDue();
}
