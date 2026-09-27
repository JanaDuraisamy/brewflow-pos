/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger Domain Models
///
/// Read models for a customer's financial history: what they bought, what
/// they paid and what they still owe. Money is always integer paise (see
/// core/utils/money.dart); timestamps are UTC instants, converted to local
/// time only for display.
///
/// Every amount here is DERIVED from persisted rows, never stored. The sale
/// [PaymentStatus] is authoritative: only NOT_PAID (credit) sales generate
/// debt, so PAID sales never contribute to a customer's outstanding balance.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

/// Derived payment state of one sale: a PAID sale is always `paid`; a
/// NOT_PAID sale is `unpaid` when nothing is recorded, `partial` when some is
/// recorded, or `paid` once recorded payments clear the total.
enum SalePaymentStatus { unpaid, partial, paid }

/// One customer-linked sale with its allocated payment totals.
///
/// Read-only view; [paidPaise]/[duePaise]/[status] come from the ledger
/// aggregation, never from stored columns.
final class CustomerPurchase {
  const CustomerPurchase({
    required this.saleId,
    required this.receiptNumber,
    required this.customerId,
    required this.createdAt,
    required this.totalPaise,
    required this.paidPaise,
    required this.duePaise,
    required this.status,
    this.isOpeningBalance = false,
  });

  final String saleId;
  final String receiptNumber;
  final String customerId;
  final DateTime createdAt;
  final int totalPaise;
  final int paidPaise;

  /// totalPaise - paidPaise; never negative by construction.
  final int duePaise;
  final SalePaymentStatus status;

  /// True for an opening-balance entry (a pre-billing debt), not a counter
  /// sale. Rendered distinctly in history so it is never mistaken for a
  /// receipt, while still participating in the same due derivation.
  final bool isOpeningBalance;
}

/// One recorded payment on a customer's bill.
final class CustomerPayment {
  const CustomerPayment({
    required this.id,
    required this.customerId,
    required this.saleId,
    required this.amountPaise,
    required this.paymentMethod,
    required this.paidAt,
    required this.reversed,
    this.note,
    this.reversedAt,
    this.paymentGroupId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String customerId;

  /// The sale this payment is allocated to. Phase 8 always allocates.
  final String saleId;
  final int amountPaise;
  final PaymentMethod paymentMethod;
  final String? note;

  /// Exact UTC instant the money moved (business timestamp).
  final DateTime paidAt;

  /// Compensating-entry flag; FALSE for every Phase 8 payment.
  final bool reversed;
  final DateTime? reversedAt;

  /// Groups the split rows of one customer-level collection. A customer-level
  /// "Collect Payment" is allocated across the oldest open bills first, so
  /// its total is naturally split into one row per bill — [paymentGroupId]
  /// links every row from the same collection, making the whole submission
  /// one idempotent unit (replayed groups are never double-applied). Legacy
  /// per-bill payments stay NULL.
  final String? paymentGroupId;
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerPayment copyWith({
    String? note,
    bool? reversed,
    DateTime? reversedAt,
    String? paymentGroupId,
    DateTime? updatedAt,
  }) => CustomerPayment(
    id: id,
    customerId: customerId,
    saleId: saleId,
    amountPaise: amountPaise,
    paymentMethod: paymentMethod,
    note: note ?? this.note,
    paidAt: paidAt,
    reversed: reversed ?? this.reversed,
    reversedAt: reversedAt ?? this.reversedAt,
    paymentGroupId: paymentGroupId ?? this.paymentGroupId,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Aggregated ledger totals for one customer.
final class CustomerLedgerSummary {
  const CustomerLedgerSummary({
    required this.customerId,
    required this.totalPurchasesPaise,
    required this.totalPaidPaise,
    required this.outstandingPaise,
    required this.purchaseCount,
    required this.paymentCount,
  });

  final String customerId;

  /// Sum of all NOT_PAID (credit) customer-linked sale totals — the open bill
  /// value. Paid sales are settled at the counter and never count as debt.
  final int totalPurchasesPaise;

  /// Sum of all non-reversed payments.
  final int totalPaidPaise;

  /// totalPurchasesPaise - totalPaidPaise; never negative by construction.
  final int outstandingPaise;
  final int purchaseCount;

  /// Count of non-reversed payments.
  final int paymentCount;
}

/// App-wide due totals for the dashboard Due Reminders surface.
final class DueCustomersSummary {
  const DueCustomersSummary({
    required this.dueCustomerCount,
    required this.totalOutstandingPaise,
  });

  /// Customers whose outstanding balance is > 0.
  final int dueCustomerCount;

  /// Sum of every due customer's outstanding balance.
  final int totalOutstandingPaise;
}

/// One open (NOT_PAID) bill inside a [CustomerReceivable], with the amount
/// still owed after allocated payments.
final class CustomerReceivableBill {
  const CustomerReceivableBill({
    required this.saleId,
    required this.receiptNumber,
    required this.createdAt,
    required this.totalPaise,
    required this.duePaise,
    this.isOpeningBalance = false,
  });

  final String saleId;
  final String receiptNumber;
  final DateTime createdAt;
  final int totalPaise;

  /// totalPaise − recorded payments; never negative by construction.
  final int duePaise;

  /// True for an opening-balance entry (a pre-billing debt), not a counter
  /// sale; shown distinctly wherever per-bill drill-downs render.
  final bool isOpeningBalance;
}

/// A customer with money still outstanding (read model for the Receivables
/// report section). Only open NOT_PAID, non-voided credit sales generate due;
/// paid sales are settled and never appear. Payments recorded on a bill stay
/// inside it as allocation history; [bills] keeps the oldest open bill first.
final class CustomerReceivable {
  const CustomerReceivable({
    required this.customerId,
    required this.customerName,
    required this.outstandingBillCount,
    required this.totalDuePaise,
    required this.bills,
  });

  final String customerId;
  final String customerName;

  /// Open bills with a remaining due (> 0 by the ledger invariant).
  final int outstandingBillCount;

  /// Sum of every open bill's remaining due.
  final int totalDuePaise;

  /// Per-bill drill-down, oldest first (matches the payment allocation
  /// order). Non-empty whenever [outstandingBillCount] > 0.
  final List<CustomerReceivableBill> bills;
}

/// A customer's outstanding balance exactly as of a historical date — the
/// read model behind the management report's Customer Outstanding section.
///
/// Unlike the current [CustomerReceivable] snapshot, this is date-bounded:
/// only customer-linked, non-voided sales created on/before the date count,
/// and only non-reversed payments recorded on/before the date offset them, so
/// the result is the balance the customer actually owed at that instant. A
/// credit bill collected in full AFTER the date still appears with its whole
/// as-of-date amount; a sale settled at the counter (PAID with no payment
/// rows) never produces due.
final class CustomerOutstandingBalance {
  const CustomerOutstandingBalance({
    required this.customerId,
    required this.customerName,
    this.phone,
    required this.outstandingPaise,
  });

  final String customerId;
  final String customerName;

  /// Phone of the profile joined from the customers table; null when the
  /// customer was never assigned one.
  final String? phone;

  /// Balance still owed as of the snapshot date; always > 0.
  final int outstandingPaise;
}
