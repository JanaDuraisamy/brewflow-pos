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
import 'shop_payables_models.dart';

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

/// A payment was for zero or a negative amount.
final class InvalidPayablePaymentFailure extends ExpensesFailure {
  const InvalidPayablePaymentFailure()
    : super('Enter an amount greater than zero.');
}

/// The payment was larger than the payee's outstanding balance.
final class PayablePaymentExceedsDueFailure extends ExpensesFailure {
  const PayablePaymentExceedsDueFailure()
    : super('Amount is more than the remaining balance.');
}

/// The named payee has nothing outstanding to pay.
final class PayableNotFoundFailure extends ExpensesFailure {
  const PayableNotFoundFailure() : super('No pending payable for this payee.');
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
    List<String>? shopIds,
  });

  /// Total number of expense records ever recorded, unfiltered. The landing
  /// page uses it to pick the empty state: a brand-new shop sees the "add your
  /// first expense" invitation even though the default date view is narrowed
  /// to today; a shop with history but nothing matching shows the
  /// "no matches" state instead.
  Future<int> expensesCount({List<String>? shopIds});

  Future<Expense?> expenseById(String id, {List<String>? shopIds});

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

  /// Total amount still owed by the shop: the sum of active NOT_PAID expenses
  /// MINUS the payments already made against them. Zero when everything is
  /// settled.
  ///
  /// Both terms are summed per payee key and only then added up, so a payment
  /// can never reduce a different payee's contribution below zero.
  Future<int> payablePaise({List<String>? shopIds});

  /// Every active NOT_PAID expense — the shop's payable ledger rows, oldest
  /// expense date first. [shopIds] restricts the read to the given
  /// businesses; when null the whole local database is scanned.
  Future<List<Expense>> payables({List<String>? shopIds});

  /// Unpaid expenses grouped by payee/item name, most pressing first.
  ///
  /// Repeated names collapse into one entry: two "Milk" expenses of ₹700 and
  /// ₹900 produce a single payable of ₹1,600, never two rows. [shopIds]
  /// restricts the read to the given businesses so Cafe and Food Truck
  /// balances stay separate.
  Future<List<ShopPayable>> shopPayables({List<String>? shopIds});

  /// Records money paid against [payeeName], reducing its remaining balance by
  /// [amountPaise].
  ///
  /// The original expense rows are never modified, reduced or deleted — the
  /// payment is its own append-only record, so the expense history stays
  /// exactly as recorded. [amountPaise] must be greater than zero and at most
  /// the payee's remaining balance; otherwise
  /// [InvalidPayablePaymentFailure] / [PayablePaymentExceedsDueFailure] /
  /// [PayableNotFoundFailure] is thrown.
  Future<ExpensePayment> recordPayablePayment({
    required String payeeName,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    required DateTime paidAt,
    String? note,
    String? shopId,
  });

  /// Payment history for one payee, newest first, optionally narrowed to
  /// [payeeName]. Reversed payments are included so history stays a faithful
  /// record; the sums elsewhere ignore them.
  Future<List<ExpensePayment>> payablePayments({
    String? payeeName,
    List<String>? shopIds,
  });
}
