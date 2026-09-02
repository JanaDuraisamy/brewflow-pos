/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expenses Repository Contract
///
/// The single boundary between expenses state/UI and the local Drift
/// database. Failures are always safe-to-display [ExpensesFailure] values;
/// database details are never exposed to callers.
///
/// Scope: expense records only (name, amount, predefined category, payment
/// method, payment status, business date, optional note, soft activity).
/// Payment status drives the shop payable total ([payablePaise]); partial
/// settlements and due-date management are a later module and intentionally
/// out of scope here.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';

import 'expenses_models.dart';

/// Base for all expenses failures. Every subtype carries a user-safe message.
sealed class ExpensesFailure implements Exception {
  const ExpensesFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The requested expense does not exist.
final class MissingExpenseFailure extends ExpensesFailure {
  const MissingExpenseFailure() : super('Expense not found.');
}

/// Database-level surprise; details are logged, never shown to the user.
final class UnexpectedExpensesFailure extends ExpensesFailure {
  const UnexpectedExpensesFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first expense persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class ExpensesRepository {
  /// Expenses matching the filters, sorted by expense date (newest first,
  /// then most recently created first).
  ///
  /// [search] matches name or note (case-insensitive substring).
  /// [status] restricts to active/inactive expenses (default: all).
  Future<List<Expense>> expenses({
    String? search,
    ExpenseCategory? category,
    PaymentMethod? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    ExpenseStatusFilter status,
  });

  Future<Expense?> expenseById(String id);

  Future<Expense> createExpense({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive,
    ExpensePaymentStatus paymentStatus,
    String? shopId,
  });

  Future<void> updateExpense({
    required String id,
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    required bool isActive,
    required ExpensePaymentStatus paymentStatus,
  });

  /// Soft switch to hide an expense without deleting its record. The only
  /// removal path; expenses are never hard-deleted.
  Future<void> setExpenseActive(String id, bool isActive);

  /// Permanently deletes an expense record. Because no other table references
  /// an expense, this is always safe: the row and its sync tombstone are
  /// removed together (other devices deactivate on receipt). Throws
  /// [MissingExpenseFailure] when the expense does not exist.
  Future<void> deleteExpense(String id);

  /// Total amount still owed by the shop: the sum of active NOT_PAID
  /// expenses in paise. Zero when everything is settled. Settlement history
  /// does not exist yet, so every NOT_PAID expense is payable in full.
  Future<int> payablePaise();
}
