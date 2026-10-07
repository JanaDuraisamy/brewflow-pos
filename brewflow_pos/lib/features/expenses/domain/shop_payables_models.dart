/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shop Payables Domain Models
///
/// The payable side of the ledger: what the shop still owes its payees.
///
/// An [Expense] is a record of what was spent and left unpaid. A
/// [ExpensePayment] is money actually handed over against those expenses. The
/// remaining balance is ALWAYS derived from both — never stored — so every
/// device reaches the same number from the same rows:
///
///     outstanding(payee) = Σ active NOT_PAID expenses(payee)
///                        − Σ non-reversed payments(payee)
///
/// Grouping: expenses are grouped by payee/item name, so "Milk" ₹700 and
/// "Milk" ₹900 surface as a single ₹1,600 payable rather than two rows.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

import 'expenses_models.dart';

/// The grouping rule for payee/item names, in one place.
///
/// Two expenses belong to the same payable when their names normalize to the
/// same [payeeKey]. Normalization is trim + lower-case and nothing more:
/// re-casing and stray whitespace are the mistakes a person actually makes
/// while typing "Milk" twice, and silently splitting those into two payables
/// would be worse than merging them. Deliberately NOT applied: collapsing
/// internal whitespace or punctuation ("Fresh  Milk" vs "Fresh Milk"), which
/// would risk merging genuinely different payees.
abstract final class PayeeKey {
  static String of(String name) => name.trim().toLowerCase();

  /// The trimmed original casing, for display.
  static String display(String name) => name.trim();
}

/// One grouped payable: everything the shop owes a single payee/item.
///
/// A [ShopPayable] is a computed view, not a row. Its [totalPaise] is the sum
/// of the underlying unpaid expenses and [paidPaise] the sum of payments made
/// against that payee, so paying part of it leaves [remainingPaise] lower
/// without altering a single expense.
///
/// Grouping identity is (shop, payee): the same name in Cafe and Food Truck
/// is two payables that never mix. [shopId] is null only for an unscoped
/// read with no shop to attribute the group to.
final class ShopPayable {
  const ShopPayable({
    required this.payeeKey,
    required this.payeeName,
    required this.totalPaise,
    required this.paidPaise,
    required this.expenseCount,
    required this.oldestExpenseDate,
    this.lastPaidAt,
    this.shopId,
  });

  /// Normalized name; the grouping identity.
  final String payeeKey;

  /// Trimmed original casing, for display.
  final String payeeName;

  /// Sum of active NOT_PAID expenses for this payee.
  final int totalPaise;

  /// Sum of non-reversed payments for this payee.
  final int paidPaise;

  /// How many expense rows are grouped under this payee.
  final int expenseCount;

  /// Oldest unpaid expense date, so the most pressing payable sorts first.
  final DateTime oldestExpenseDate;

  /// When the most recent payment against this payee landed; null if never
  /// paid.
  final DateTime? lastPaidAt;

  /// The shop this payable belongs to; null only for an unscoped read.
  /// The detail drill-down lists the unpaid expenses of exactly this shop.
  final String? shopId;

  /// What is still owed. Never negative: a payment above the outstanding
  /// balance is rejected up front, and this clamps defensively so a reversed
  /// or deleted expense can never surface as a negative payable.
  int get remainingPaise {
    final remaining = totalPaise - paidPaise;
    return remaining < 0 ? 0 : remaining;
  }

  bool get isSettled => remainingPaise == 0;

  /// Whether [amountPaise] is a valid payment against this payable: more than
  /// zero and no more than the outstanding balance.
  bool canPay(int amountPaise) =>
      amountPaise > 0 && amountPaise <= remainingPaise;
}

/// One recorded payment against a payee.
final class ExpensePayment {
  const ExpensePayment({
    required this.id,
    required this.payeeKey,
    required this.payeeName,
    required this.amountPaise,
    required this.paymentMethod,
    required this.paidAt,
    this.note,
    required this.reversed,
    this.reversedAt,
    required this.createdAt,
  });

  final String id;

  /// Normalized payee name this payment settles.
  final String payeeKey;

  /// Trimmed payee name as it was when the payment was recorded, so history
  /// reads "Milk" even if a later expense is typed with different casing.
  final String payeeName;

  final int amountPaise;
  final PaymentMethod paymentMethod;
  final DateTime paidAt;
  final String? note;
  final bool reversed;
  final DateTime? reversedAt;
  final DateTime createdAt;

  /// Reversed payments are excluded from every due/paid sum.
  bool get countsTowardPaid => !reversed;
}
