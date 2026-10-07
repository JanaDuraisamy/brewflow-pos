import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';

import 'test_providers.dart';

/// Accumulator while grouping unpaid expenses by payee key.
final class _GroupedPayable {
  _GroupedPayable({
    required this.shopId,
    required this.payeeKey,
    required this.payeeName,
    required this.oldestExpenseDate,
  });

  final String? shopId;
  final String payeeKey;
  final String payeeName;
  int totalPaise = 0;
  int paidPaise = 0;
  int expenseCount = 0;
  DateTime oldestExpenseDate;
}

/// In-memory [ExpensesRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// search over name/note, category/payment/status filtering, inclusive UTC
/// date ranges, newest-date-first ordering and blank-optional normalization
/// (empty notes never store a value). Probe hooks ([loadError], [loadGate])
/// drive loading and error states.
final class FakeExpensesRepository implements ExpensesRepository {
  final List<Expense> storedExpenses = [];

  /// Append-only payments recorded against shop payables.
  final List<ExpensePayment> storedPayablePayments = [];

  /// When set, every load and mutation throws this error instead of running.
  Object? loadError;

  /// When set, expense loads wait for this (loading-state tests).
  Completer<void>? loadGate;

  /// When set, [payables] throws this error before running.
  Object? payablesError;

  /// Shop id treated as the owner of any seeded row that omits one.
  ///
  /// Mirrors [FakeInventoryRepository.unscopedShopIdFallback]: fixtures predate
  /// shop scoping, so a missing shop resolves here and stays visible to a
  /// scoped read, while a row that DOES carry a shop id is filtered strictly.
  /// Set it to null to assert that an unscoped (legacy) row stays invisible
  /// under a scope.
  String? unscopedShopIdFallback = kTestCafeShopId;

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

  /// Resolves the shop an expense belongs to for scoped reads, mirroring
  /// the Drift `shop_id = ?` predicate with a legacy fallback: a row that
  /// carries a shop id is matched strictly, while a row without one resolves
  /// to [unscopedShopIdFallback] (null keeps it invisible under any scope).
  String? _resolvedShop(Expense expense) =>
      expense.shopId ?? unscopedShopIdFallback;

  bool _inScope(Expense expense, List<String>? shopIds) {
    if (shopIds == null) return true;
    if (shopIds.isEmpty) return false;
    return shopIds.contains(_resolvedShop(expense));
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
    List<String>? shopIds,
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
            // NOTE: intentionally unscoped (unlike payables/shopPayables
            // below): the historical expense list tests seed rows without a
            // shop and read through a resolved scope, so strict filtering
            // here would hide every legacy row. Scoped isolation for the
            // list lives in the Drift repository; the payable surfaces carry
            // the shop-aware contract.
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
  Future<int> expensesCount({List<String>? shopIds}) async {
    _throwIfLoadError();
    return storedExpenses.length;
  }

  @override
  Future<Expense?> expenseById(String id, {List<String>? shopIds}) async {
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
    String? shopId,
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
      shopId: shopId,
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
        shopId: existing.shopId,
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
        shopId: existing.shopId,
      ),
    );
  }

  @override
  Future<int> payablePaise({List<String>? shopIds}) async {
    _throwIfLoadError();
    // Net of payments, matching the Drift repository: a payment reduces what is
    // owed, and the total is never negative.
    final total = _unpaidTotal() - _paidTotal();
    return total < 0 ? 0 : total;
  }

  @override
  Future<List<Expense>> payables({List<String>? shopIds}) async {
    _throwIfLoadError();
    final error = payablesError;
    if (error != null) {
      throw error;
    }
    final due =
        [
          for (final expense in storedExpenses)
            if (_inScope(expense, shopIds) &&
                expense.isActive &&
                expense.paymentStatus == ExpensePaymentStatus.notPaid)
              expense,
        ]..sort((a, b) {
          final byDate = a.expenseDate.compareTo(b.expenseDate);
          return byDate != 0 ? byDate : a.createdAt.compareTo(b.createdAt);
        });
    return due;
  }

  // ---- Shop payables ---------------------------------------------------------------

  @override
  Future<List<ShopPayable>> shopPayables({List<String>? shopIds}) async {
    _throwIfLoadError();
    if (shopIds != null && shopIds.isEmpty) return const [];
    // Grouped per (shop, payee): a same-named payee in two businesses is two
    // payables that never mix (mirrors the Drift per-shop grouping).
    final groups = <String, _GroupedPayable>{};
    for (final expense in storedExpenses) {
      if (!_inScope(expense, shopIds)) continue;
      if (!expense.isActive ||
          expense.paymentStatus != ExpensePaymentStatus.notPaid) {
        continue;
      }
      final shop = _resolvedShop(expense);
      final key = PayeeKey.of(expense.name);
      final groupKey = '${shop ?? '-'}|$key';
      final group = groups.putIfAbsent(
        groupKey,
        () => _GroupedPayable(
          shopId: shop,
          payeeKey: key,
          payeeName: PayeeKey.display(expense.name),
          oldestExpenseDate: expense.expenseDate,
        ),
      );
      group.totalPaise += expense.amountPaise;
      group.expenseCount += 1;
      if (expense.expenseDate.isBefore(group.oldestExpenseDate)) {
        group.oldestExpenseDate = expense.expenseDate;
      }
    }
    for (final payment in storedPayablePayments) {
      if (payment.reversed) continue;
      for (final group in groups.values) {
        if (group.payeeKey == payment.payeeKey) {
          group.paidPaise += payment.amountPaise;
        }
      }
    }
    final result =
        [
          for (final group in groups.values)
            ShopPayable(
              payeeKey: group.payeeKey,
              payeeName: group.payeeName,
              totalPaise: group.totalPaise,
              paidPaise: group.paidPaise,
              expenseCount: group.expenseCount,
              oldestExpenseDate: group.oldestExpenseDate,
              lastPaidAt: _lastPaidAt(group.payeeKey),
              shopId: group.shopId,
            ),
        ]..sort((a, b) {
          final byRemaining = b.remainingPaise.compareTo(a.remainingPaise);
          if (byRemaining != 0) return byRemaining;
          return a.oldestExpenseDate.compareTo(b.oldestExpenseDate);
        });
    return result;
  }

  @override
  Future<ExpensePayment> recordPayablePayment({
    required String payeeName,
    required int amountPaise,
    required PaymentMethod paymentMethod,
    required DateTime paidAt,
    String? note,
    String? shopId,
  }) async {
    _throwIfLoadError();
    if (amountPaise <= 0) throw const InvalidPayablePaymentFailure();
    final displayName = PayeeKey.display(payeeName);
    if (displayName.isEmpty) throw const PayableNotFoundFailure();
    final payeeKey = PayeeKey.of(displayName);
    final remaining = _unpaidTotalFor(payeeKey) - _paidTotalFor(payeeKey);
    if (remaining <= 0) throw const PayableNotFoundFailure();
    if (amountPaise > remaining) {
      throw const PayablePaymentExceedsDueFailure();
    }
    final payment = ExpensePayment(
      id: 'expense-payment-${storedPayablePayments.length + 1}',
      payeeKey: payeeKey,
      payeeName: displayName,
      amountPaise: amountPaise,
      paymentMethod: paymentMethod,
      paidAt: paidAt.toUtc(),
      note: _optionalText(note),
      reversed: false,
      reversedAt: null,
      createdAt: DateTime.now().toUtc(),
    );
    storedPayablePayments.add(payment);
    return payment;
  }

  @override
  Future<List<ExpensePayment>> payablePayments({
    String? payeeName,
    List<String>? shopIds,
  }) async {
    _throwIfLoadError();
    final key = payeeName == null ? null : PayeeKey.of(payeeName);
    final matching = [
      for (final payment in storedPayablePayments)
        if (key == null || payment.payeeKey == key) payment,
    ]..sort((a, b) => b.paidAt.compareTo(a.paidAt));
    return matching;
  }

  int _unpaidTotal() {
    var total = 0;
    for (final expense in storedExpenses) {
      if (expense.isActive &&
          expense.paymentStatus == ExpensePaymentStatus.notPaid) {
        total += expense.amountPaise;
      }
    }
    return total;
  }

  int _unpaidTotalFor(String payeeKey) {
    var total = 0;
    for (final expense in storedExpenses) {
      if (expense.isActive &&
          expense.paymentStatus == ExpensePaymentStatus.notPaid &&
          PayeeKey.of(expense.name) == payeeKey) {
        total += expense.amountPaise;
      }
    }
    return total;
  }

  int _paidTotal() {
    var total = 0;
    for (final payment in storedPayablePayments) {
      if (!payment.reversed) total += payment.amountPaise;
    }
    return total;
  }

  int _paidTotalFor(String payeeKey) {
    var total = 0;
    for (final payment in storedPayablePayments) {
      if (!payment.reversed && payment.payeeKey == payeeKey) {
        total += payment.amountPaise;
      }
    }
    return total;
  }

  DateTime? _lastPaidAt(String payeeKey) {
    DateTime? latest;
    for (final payment in storedPayablePayments) {
      if (payment.reversed || payment.payeeKey != payeeKey) continue;
      if (latest == null || payment.paidAt.isAfter(latest)) {
        latest = payment.paidAt;
      }
    }
    return latest;
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
    String? shopId,
  }) => _store(
    name: name,
    amountPaise: amountPaise,
    category: category,
    paymentMethod: paymentMethod,
    expenseDate: expenseDate,
    note: note,
    isActive: isActive,
    paymentStatus: paymentStatus,
    shopId: shopId,
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
    String? shopId,
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
      shopId: shopId,
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
