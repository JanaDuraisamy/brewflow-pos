import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Billing Failures
///
/// Every recoverable billing problem surfaced to the UI. Messages are safe,
/// user-facing text; implementation details never leak past the repository.
/// ---------------------------------------------------------------------------

sealed class BillingFailure implements Exception {
  const BillingFailure(this.message);

  /// Safe, user-facing message.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Checkout attempted with nothing in the cart.
final class EmptyCartFailure extends BillingFailure {
  const EmptyCartFailure([super.message = 'Your cart is empty.']);
}

/// Quantity outside the allowed range (below 1 or above the stock cap).
final class InvalidQuantityFailure extends BillingFailure {
  const InvalidQuantityFailure([
    super.message = 'Quantity must be at least 1.',
  ]);
}

/// Not enough stock left for the requested quantity.
final class InsufficientStockFailure extends BillingFailure {
  InsufficientStockFailure(this.productName, [String? message])
    : super(message ?? '$productName does not have enough stock.');

  final String productName;
}

/// The product is no longer sellable (deleted or inactive).
final class UnavailableProductFailure extends BillingFailure {
  UnavailableProductFailure(this.productName, [String? message])
    : super(message ?? '$productName is no longer available.');

  final String productName;
}

/// No payment method was selected (or an unknown one was passed).
final class InvalidPaymentFailure extends BillingFailure {
  const InvalidPaymentFailure([
    super.message = 'Select a payment method to complete the sale.',
  ]);
}

/// A NOT_PAID (credit) sale requires a linked customer — the unpaid total
/// becomes the customer's ledger debt, and walk-ins have no ledger.
final class MissingCustomerForCreditSaleFailure extends BillingFailure {
  const MissingCustomerForCreditSaleFailure([
    super.message = 'Select a customer to save this bill as Not Paid.',
  ]);
}

/// The sale has already been voided and cannot be voided again.
final class SaleAlreadyVoidedFailure extends BillingFailure {
  const SaleAlreadyVoidedFailure([
    super.message = 'This sale has already been voided.',
  ]);
}

/// A customer-linked sale referenced a customer that no longer exists.
final class CustomerNotFoundFailure extends BillingFailure {
  const CustomerNotFoundFailure([super.message = 'Customer not found.']);
}

/// The selected customer is deactivated and cannot be billed.
final class InactiveCustomerFailure extends BillingFailure {
  const InactiveCustomerFailure([
    super.message =
        'This customer is deactivated. Re-activate them to bill them.',
  ]);
}

/// The referenced sale does not exist in the database.
final class SaleNotFoundFailure extends BillingFailure {
  const SaleNotFoundFailure([super.message = 'Sale not found.']);
}

/// Anything else — logged, and shown as a generic failure.
final class UnexpectedBillingFailure extends BillingFailure {
  const UnexpectedBillingFailure([super.message = 'Please try again.']);
}

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Billing Repository
///
/// Persists a completed POS transaction atomically: sale header, snapshot
/// line items and conditional stock deduction in one transaction. Read APIs
/// exist for tests and as the foundation the future Orders module builds on.
/// ---------------------------------------------------------------------------

abstract interface class BillingRepository {
  /// Atomically validates and persists a sale, deducting stock, and returns
  /// the completed sale with its persisted items.
  ///
  /// [paymentStatus] describes collection: [PaymentStatus.paid] keeps the
  /// existing flow (a payment method is mandatory); [PaymentStatus.notPaid]
  /// records a credit sale — [customerId] becomes mandatory, no payment
  /// method is persisted (NULL), and the sale total shows up as customer
  /// debt through the existing customer ledger (derived from sales minus
  /// payments, so no separate debt record is written).
  ///
  /// [customerId] optionally links the sale to a customer profile (walk-in
  /// sales pass null); a non-null customer is re-validated inside the
  /// transaction (must exist and be active).
  ///
  /// Throws [BillingFailure] for every recoverable condition
  /// ([EmptyCartFailure], [UnavailableProductFailure],
  /// [InsufficientStockFailure], [InvalidPaymentFailure],
  /// [MissingCustomerForCreditSaleFailure], [CustomerNotFoundFailure],
  /// [InactiveCustomerFailure], [UnexpectedBillingFailure]). On failure the
  /// database is left untouched (full rollback).
  Future<CompletedSale> completeSale({
    required List<CartLine> lines,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    PaymentMethod? paymentMethod,
    String? customerId,
  });

  /// The sale header with this id, or null when missing.
  Future<Sale?> saleById(String id);

  /// The persisted items of one sale, in insertion order.
  Future<List<SaleItem>> saleItemsFor(String saleId);

  /// All completed sales, newest first.
  Future<List<Sale>> sales();

  /// Marks a sale as voided, restores stock, and reverses customer payments.
  ///
  /// The sale row is never deleted — [Sale.voided] is set to true and
  /// [Sale.voidedAt] records the instant. Stock added back by each tracked
  /// line and any customer payments linked to this sale are reversed in the
  /// same transaction.
  ///
  /// Throws [SaleNotFoundFailure] when [saleId] does not exist,
  /// [SaleAlreadyVoidedFailure] when the sale is already voided, or
  /// [UnexpectedBillingFailure] on unexpected errors.
  Future<void> voidSale(String saleId);
}
