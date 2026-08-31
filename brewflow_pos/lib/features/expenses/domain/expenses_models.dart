/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expenses Domain Models
///
/// [Expense] is a pure record of one business expense. Money is always
/// integer paise (see core/utils/money.dart); timestamps are UTC instants,
/// converted to local time only for display ([expenseDate] is the UTC
/// instant at local midnight of the business day the user picked).
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

/// Predefined expense categories. Fixed enum-style values with stable DB
/// strings, mirroring the [PaymentMethod] convention: the CHECK constraint on
/// the expenses table only accepts these exact values, so aggregations
/// (future reports) always group by clean, unchanged labels. Custom
/// categories are intentionally out of scope; they would arrive as an
/// additive migration in a later phase.
enum ExpenseCategory {
  supplies,
  utilities,
  rent,
  salaries,
  maintenance,
  marketing,
  transport,
  misc;

  /// Database-storage value, kept stable for CHECK constraints and history.
  String get dbValue => switch (this) {
    ExpenseCategory.supplies => 'SUPPLIES',
    ExpenseCategory.utilities => 'UTILITIES',
    ExpenseCategory.rent => 'RENT',
    ExpenseCategory.salaries => 'SALARIES',
    ExpenseCategory.maintenance => 'MAINTENANCE',
    ExpenseCategory.marketing => 'MARKETING',
    ExpenseCategory.transport => 'TRANSPORT',
    ExpenseCategory.misc => 'MISC',
  };

  static ExpenseCategory? fromDbValue(String value) => switch (value) {
    'SUPPLIES' => ExpenseCategory.supplies,
    'UTILITIES' => ExpenseCategory.utilities,
    'RENT' => ExpenseCategory.rent,
    'SALARIES' => ExpenseCategory.salaries,
    'MAINTENANCE' => ExpenseCategory.maintenance,
    'MARKETING' => ExpenseCategory.marketing,
    'TRANSPORT' => ExpenseCategory.transport,
    'MISC' => ExpenseCategory.misc,
    _ => null,
  };

  /// Display label, e.g. 'Supplies', 'Miscellaneous'.
  String get label => switch (this) {
    ExpenseCategory.supplies => 'Supplies',
    ExpenseCategory.utilities => 'Utilities',
    ExpenseCategory.rent => 'Rent',
    ExpenseCategory.salaries => 'Salaries',
    ExpenseCategory.maintenance => 'Maintenance',
    ExpenseCategory.marketing => 'Marketing',
    ExpenseCategory.transport => 'Transport',
    ExpenseCategory.misc => 'Miscellaneous',
  };
}

/// Active/inactive restriction for the expenses list.
enum ExpenseStatusFilter { all, active, inactive }

/// Payment status of an expense. Stable DB values mirror the
/// [ExpenseCategory]/[PaymentMethod] convention: the CHECK constraint on the
/// expenses table only accepts these exact values.
///
/// A [notPaid] expense is still a real recorded expense — it counts in
/// history and totals — and its outstanding amount becomes shop payable
/// until the record is marked [paid]. Settlements (partial payments,
/// due dates) are a later module; today a NOT_PAID expense is payable in
/// full.
enum ExpensePaymentStatus {
  paid,
  notPaid;

  /// Database-storage value, kept stable for CHECK constraints and history.
  String get dbValue => switch (this) {
    ExpensePaymentStatus.paid => 'PAID',
    ExpensePaymentStatus.notPaid => 'NOT_PAID',
  };

  static ExpensePaymentStatus? fromDbValue(String value) => switch (value) {
    'PAID' => ExpensePaymentStatus.paid,
    'NOT_PAID' => ExpensePaymentStatus.notPaid,
    _ => null,
  };

  /// Display label, e.g. 'Paid', 'Not paid'.
  String get label => switch (this) {
    ExpensePaymentStatus.paid => 'Paid',
    ExpensePaymentStatus.notPaid => 'Not paid',
  };
}

/// One recorded business expense.
final class Expense {
  const Expense({
    required this.id,
    required this.name,
    required this.amountPaise,
    required this.category,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.expenseDate,
    this.note,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Amount spent in paise; always >= 0 (the form enforces > 0).
  final int amountPaise;
  final ExpenseCategory category;
  final PaymentMethod paymentMethod;

  /// Whether the expense is settled; NOT_PAID expenses are shop payable.
  final ExpensePaymentStatus paymentStatus;

  /// UTC instant at local midnight of the business day of the expense.
  final DateTime expenseDate;

  /// Optional free-form note; null when blank.
  final String? note;

  /// Soft switch; inactive expenses are hidden from active lists.
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
}
