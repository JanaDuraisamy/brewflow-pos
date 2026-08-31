/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Ledger Domain Models
///
/// Read models for a customer's financial history: what they bought, what
/// they paid and what they still owe. Money is always integer paise (see
/// core/utils/money.dart); timestamps are UTC instants, converted to local
/// time only for display.
///
/// Every amount here is DERIVED from persisted rows — sales totals minus
/// non-reversed customer payments — never stored. Sale payment status is
/// computed, never persisted.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

/// Derived payment state of one sale, computed as:
/// paidPaise == 0 → unpaid; 0 < paidPaise < totalPaise → partial;
/// paidPaise >= totalPaise → paid.
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
  final DateTime createdAt;
  final DateTime updatedAt;

  CustomerPayment copyWith({
    String? note,
    bool? reversed,
    DateTime? reversedAt,
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

  /// Sum of all customer-linked sale totals.
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
