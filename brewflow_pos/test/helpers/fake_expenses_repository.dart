import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';

/// In-memory [ExpensesRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// search over name/note, category/payment/status filtering, inclusive UTC
/// date ranges, newest-date-first ordering and blank-optional normalization
/// (empty notes never store a value). Probe hooks ([loadError], [loadGate])
/// drive loading and error states.
final class FakeExpensesRepository implements ExpensesRepository {
  final List<Expense> storedExpenses = [];

  /// When set, every load and mutation throws this error instead of running.
  Object? loadError;

  /// When set, expense loads wait for this (loading-state tests).
  Completer<void>? loadGate;

  /// Number of [expenses] calls.
  int loadCalls = 0;

  Future<void> _gate() async {
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
  }

  void _throwIfLoadError() {
    final error = loadError;
    if (error != null) {
      throw error;
    }
  }

  bool _matches(
    Expense expense, {
    required String search,
    required ExpenseCategory? category,
    required PaymentMethod? paymentMethod,
    required DateTime? fromUtc,
    required DateTime? toUtc,
    required bool? active,
  }) {
    final query = search.trim();
    if (query.isNotEmpty) {
      final lower = query.toLowerCase();
      final byName = expense.name.toLowerCase().contains(lower);
      final byNote = expense.note?.toLowerCase().contains(lower) ?? false;
      if (!byName && !byNote) return false;
    }
    if (category != null && expense.category != category) return false;
    if (paymentMethod != null && expense.paymentMethod != paymentMethod) {
      return false;
    }
    if (fromUtc != null && expense.expenseDate.isBefore(fromUtc)) return false;
    if (toUtc != null && expense.expenseDate.isAfter(toUtc)) return false;
    if (active != null && expense.isActive != active) return false;
    return true;
  }

  @override
  Future<List<Expense>> expenses({
    String? search,
    ExpenseCategory? category,
    PaymentMethod? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    ExpenseStatusFilter status = ExpenseStatusFilter.all,
  }) async {
    loadCalls += 1;
    await _gate();
    _throwIfLoadError();
    final active = switch (status) {
      ExpenseStatusFilter.all => null,
      ExpenseStatusFilter.active => true,
      ExpenseStatusFilter.inactive => false,
    };
    final matching =
        [
          for (final expense in storedExpenses)
            if (_matches(
              expense,
              search: search ?? '',
              category: category,
              paymentMethod: paymentMethod,
              fromUtc: fromUtc,
              toUtc: toUtc,
              active: active,
            ))
              expense,
        ]..sort((a, b) {
          final byDate = b.expenseDate.compareTo(a.expenseDate);
          return byDate != 0 ? byDate : b.createdAt.compareTo(a.createdAt);
        });
    return matching;
  }

  @override
  Future<Expense?> expenseById(String id) async {
    _throwIfLoadError();
    for (final expense in storedExpenses) {
      if (expense.id == id) {
        return expense;
      }
    }
    return null;
  }

  @override
  Future<Expense> createExpense({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) async {
    _throwIfLoadError();
    return _store(
      name: name,
      amountPaise: amountPaise,
      category: category,
      paymentMethod: paymentMethod,
      expenseDate: expenseDate,
      note: note,
      isActive: isActive,
      paymentStatus: paymentStatus,
    );
  }

  @override
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
  }) async {
    _throwIfLoadError();
    final existing = storedExpenses.firstWhere(
      (expense) => expense.id == id,
      orElse: () => throw const MissingExpenseFailure(),
    );
    _replace(
      Expense(
        id: existing.id,
        name: name,
        amountPaise: amountPaise,
        category: category,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        expenseDate: expenseDate,
        note: _optionalText(note),
        isActive: isActive,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<void> setExpenseActive(String id, bool isActive) async {
    _throwIfLoadError();
    final existing = storedExpenses.firstWhere(
      (expense) => expense.id == id,
      orElse: () => throw const MissingExpenseFailure(),
    );
    _replace(
      Expense(
        id: existing.id,
        name: existing.name,
        amountPaise: existing.amountPaise,
        category: existing.category,
        paymentMethod: existing.paymentMethod,
        paymentStatus: existing.paymentStatus,
        expenseDate: existing.expenseDate,
        note: existing.note,
        isActive: isActive,
        createdAt: existing.createdAt,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  @override
  Future<int> payablePaise() async {
    _throwIfLoadError();
    var total = 0;
    for (final expense in storedExpenses) {
      if (expense.isActive &&
          expense.paymentStatus == ExpensePaymentStatus.notPaid) {
        total += expense.amountPaise;
      }
    }
    return total;
  }

  @override
  Future<void> deleteExpense(String id) async {
    _throwIfLoadError();
    final index = storedExpenses.indexWhere((e) => e.id == id);
    if (index == -1) {
      throw const MissingExpenseFailure();
    }
    storedExpenses.removeAt(index);
  }

  /// Seeds one expense directly from form-style data (no error/gate hooks).
  Expense seed({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) => _store(
    name: name,
    amountPaise: amountPaise,
    category: category,
    paymentMethod: paymentMethod,
    expenseDate: expenseDate,
    note: note,
    isActive: isActive,
    paymentStatus: paymentStatus,
  );

  Expense _store({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) {
    final now = DateTime.now().toUtc();
    final expense = Expense(
      id: 'expense-${storedExpenses.length + 1}',
      name: name,
      amountPaise: amountPaise,
      category: category,
      paymentMethod: paymentMethod,
      paymentStatus: paymentStatus,
      expenseDate: expenseDate,
      note: _optionalText(note),
      isActive: isActive,
      createdAt: now,
      updatedAt: now,
    );
    storedExpenses.add(expense);
    return expense;
  }

  void _replace(Expense expense) {
    final index = storedExpenses.indexWhere((e) => e.id == expense.id);
    if (index == -1) {
      throw const MissingExpenseFailure();
    }
    storedExpenses[index] = expense;
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
