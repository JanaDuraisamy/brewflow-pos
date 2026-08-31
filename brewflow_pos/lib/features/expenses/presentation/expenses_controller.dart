import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/drift_expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/data/quick_expense_store.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../staff/presentation/staff_controller.dart';
import '../../sync/presentation/sync_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expenses State (Riverpod)
///
/// Composition:
/// - [expensesRepositoryProvider] → Drift-backed repository (override in
///                                  tests with a fake).
/// - [expensesFilterProvider]     → current expense list filter.
/// - [expensesProvider]           → expenses matching the filter.
///
/// Mutations go through a shared [_mutate] helper: run the repository call,
/// then invalidate the affected state so the UI refreshes. Every failure is
/// translated into a safe [ExpensesFailure] (details logged, never shown).
/// ---------------------------------------------------------------------------

/// Owns the single expenses repository for the application scope.
final expensesRepositoryProvider = Provider<ExpensesRepository>((ref) {
  return DriftExpensesRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// Immutable expense list filter state.
final class ExpensesFilter {
  const ExpensesFilter({
    this.query = '',
    this.category,
    this.paymentMethod,
    this.datePreset = OrdersDatePreset.all,
    this.fromUtc,
    this.toUtc,
    this.status = ExpenseStatusFilter.all,
  });

  /// Search text matched against the expense name and note.
  final String query;

  /// Category restriction; null for all categories.
  final ExpenseCategory? category;

  /// Payment-method restriction; null for all methods.
  final PaymentMethod? paymentMethod;

  /// Date-range preset driving [fromUtc]/[toUtc].
  final OrdersDatePreset datePreset;

  /// Inclusive UTC range bounds; both null for "all time".
  final DateTime? fromUtc;
  final DateTime? toUtc;

  /// Active/inactive restriction.
  final ExpenseStatusFilter status;

  /// Whether anything restricts the list beyond the default state.
  bool get isActive =>
      query.trim().isNotEmpty ||
      category != null ||
      paymentMethod != null ||
      fromUtc != null ||
      status != ExpenseStatusFilter.all;

  ExpensesFilter copyWith({
    String? query,
    ExpenseCategory? Function()? category,
    PaymentMethod? Function()? paymentMethod,
    OrdersDatePreset? datePreset,
    DateTime? Function()? fromUtc,
    DateTime? Function()? toUtc,
    ExpenseStatusFilter? status,
  }) => ExpensesFilter(
    query: query ?? this.query,
    category: category != null ? category() : this.category,
    paymentMethod: paymentMethod != null ? paymentMethod() : this.paymentMethod,
    datePreset: datePreset ?? this.datePreset,
    fromUtc: fromUtc != null ? fromUtc() : this.fromUtc,
    toUtc: toUtc != null ? toUtc() : this.toUtc,
    status: status ?? this.status,
  );
}

/// Holds the current expense list filter; changes rebuild [expensesProvider].
final expensesFilterProvider =
    NotifierProvider<ExpensesFilterController, ExpensesFilter>(
      ExpensesFilterController.new,
    );

/// Bounds for a whole "local day" converted to UTC instants.
final class _DayBound {
  const _DayBound(this.fromUtc, this.toUtc);

  final DateTime fromUtc;
  final DateTime toUtc;
}

final class ExpensesFilterController extends Notifier<ExpensesFilter> {
  @override
  ExpensesFilter build() => const ExpensesFilter();

  void setQuery(String query) => state = state.copyWith(query: query);

  void setCategory(ExpenseCategory? category) =>
      state = state.copyWith(category: () => category);

  void setPaymentMethod(PaymentMethod? paymentMethod) =>
      state = state.copyWith(paymentMethod: () => paymentMethod);

  void setStatus(ExpenseStatusFilter status) =>
      state = state.copyWith(status: status);

  /// Applies a named date-range preset, computed from the current time.
  void setPreset(OrdersDatePreset preset) {
    if (preset == OrdersDatePreset.custom) {
      return;
    }
    if (preset == OrdersDatePreset.all) {
      state = state.copyWith(
        datePreset: OrdersDatePreset.all,
        fromUtc: () => null,
        toUtc: () => null,
      );
      return;
    }
    final now = DateTime.now();
    final offsetDays = switch (preset) {
      OrdersDatePreset.today => 0,
      OrdersDatePreset.last7 => 6,
      OrdersDatePreset.last30 => 29,
      OrdersDatePreset.last90 => 89,
      _ => 0,
    };
    final fromDay = _localDay(now.subtract(Duration(days: offsetDays)));
    final toDay = _localDay(now);
    final bounds = _boundsOf(toDay);
    state = state.copyWith(
      datePreset: preset,
      fromUtc: () => fromDay.toUtc(),
      toUtc: () => bounds.toUtc,
    );
  }

  /// Sets a custom inclusive local date range (picker dates, local timezone).
  void setCustomRange(DateTime fromLocal, DateTime toLocal) {
    if (!toLocal.isAfter(fromLocal)) return;
    final bounds = _boundsOf(_localDay(toLocal));
    state = state.copyWith(
      datePreset: OrdersDatePreset.custom,
      fromUtc: () => _localDay(fromLocal).toUtc(),
      toUtc: () => bounds.toUtc,
    );
  }

  void clear() => state = const ExpensesFilter();

  static _DayBound _boundsOf(DateTime startOfDay) => _DayBound(
    startOfDay.toUtc(),
    startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1))
        .toUtc(),
  );

  static DateTime _localDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}

/// Expenses matching the current [expensesFilterProvider] state.
final expensesProvider =
    AsyncNotifierProvider<ExpensesController, List<Expense>>(
      ExpensesController.new,
    );

/// Total amount the shop still owes on expenses (active NOT_PAID records).
/// Rebuilt by [ExpensesController] after every mutation.
final shopPayableProvider = FutureProvider<int>((ref) async {
  try {
    return await ref.watch(expensesRepositoryProvider).payablePaise();
  } on ExpensesFailure {
    rethrow;
  } catch (error, stackTrace) {
    AppLog.error(
      'Failed to load payable total',
      tag: ExpensesController.tag,
      error: error,
      stackTrace: stackTrace,
    );
    throw const UnexpectedExpensesFailure();
  }
});

final class ExpensesController extends AsyncNotifier<List<Expense>> {
  static const String tag = 'Expenses';

  @override
  Future<List<Expense>> build() async {
    final filter = ref.watch(expensesFilterProvider);
    final repository = ref.watch(expensesRepositoryProvider);
    try {
      return await repository.expenses(
        search: filter.query,
        category: filter.category,
        paymentMethod: filter.paymentMethod,
        fromUtc: filter.fromUtc,
        toUtc: filter.toUtc,
        status: filter.status,
      );
    } on ExpensesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load expenses',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedExpensesFailure();
    }
  }

  Future<Expense?> byId(String id) async {
    try {
      return await ref.read(expensesRepositoryProvider).expenseById(id);
    } on ExpensesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load expense',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedExpensesFailure();
    }
  }

  Future<void> create({
    required String name,
    required int amountPaise,
    required ExpenseCategory category,
    required PaymentMethod paymentMethod,
    required DateTime expenseDate,
    String? note,
    bool isActive = true,
    ExpensePaymentStatus paymentStatus = ExpensePaymentStatus.paid,
  }) {
    requirePermission(ref, Permission.expenses);
    return _mutate(
      () => ref
          .read(expensesRepositoryProvider)
          .createExpense(
            name: name,
            amountPaise: amountPaise,
            category: category,
            paymentMethod: paymentMethod,
            expenseDate: expenseDate,
            note: note,
            isActive: isActive,
            paymentStatus: paymentStatus,
          ),
    );
  }

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
  }) {
    requirePermission(ref, Permission.expenses);
    return _mutate(
      () => ref
          .read(expensesRepositoryProvider)
          .updateExpense(
            id: id,
            name: name,
            amountPaise: amountPaise,
            category: category,
            paymentMethod: paymentMethod,
            expenseDate: expenseDate,
            note: note,
            isActive: isActive,
            paymentStatus: paymentStatus,
          ),
    );
  }

  Future<void> setActive(String id, bool isActive) {
    requirePermission(ref, Permission.expenses);
    return _mutate(
      () => ref.read(expensesRepositoryProvider).setExpenseActive(id, isActive),
    );
  }

  Future<void> delete(String id) {
    requireOwner(ref);
    return _mutate(
      () => ref.read(expensesRepositoryProvider).deleteExpense(id),
    );
  }

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [ExpensesFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedExpensesFailure].
  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidateSelf();
      ref.invalidate(shopPayableProvider);
      ref.invalidate(reportsControllerProvider);
    } on ExpensesFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Expenses mutation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedExpensesFailure();
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [ExpensesFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String expensesErrorMessage(Object error, {String? fallback}) {
  if (error is ExpensesFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}

/// ---------------------------------------------------------------------------
/// Quick Expenses (P0 FIX 8)
///
/// Pinned one-tap templates for recurring daily purchases (milk, sugar, …).
/// Templates are a device-local counter convenience persisted through the
/// app's existing preferences layer; they never hold money and never replace
/// the expense ledger — tapping a template creates a NORMAL [Expense] for
/// today via [ExpensesController.create].
/// ---------------------------------------------------------------------------

/// Owns the template persistence boundary for the app scope.
final quickExpenseStoreProvider = Provider<QuickExpenseStore>((ref) {
  return QuickExpenseStore();
});

final quickExpensesProvider =
    AsyncNotifierProvider<QuickExpensesController, List<QuickExpenseTemplate>>(
      QuickExpensesController.new,
    );

final class QuickExpensesController
    extends AsyncNotifier<List<QuickExpenseTemplate>> {
  static const String tag = 'Expenses';

  @override
  Future<List<QuickExpenseTemplate>> build() =>
      ref.watch(quickExpenseStoreProvider).load();

  /// Pins [template]; pinning an existing identity refreshes its default
  /// amount. Identity is (category, lowercase name). Always loads FRESH from
  /// the store — rapid successive pins must never resurrect a stale snapshot
  /// while an invalidation-driven rebuild is still pending.
  Future<void> pin(QuickExpenseTemplate template) async {
    final store = ref.read(quickExpenseStoreProvider);
    final current = await store.load();
    final next = <QuickExpenseTemplate>[];
    var replaced = false;
    for (final existing in current) {
      if (existing.id == template.id) {
        next.add(template);
        replaced = true;
      } else {
        next.add(existing);
      }
    }
    if (!replaced) next.add(template);
    await store.save(next);
    ref.invalidateSelf();
  }

  /// Removes the template with [template]'s identity; no-op when absent.
  Future<void> unpin(QuickExpenseTemplate template) async {
    final store = ref.read(quickExpenseStoreProvider);
    final current = await store.load();
    if (!current.any((existing) => existing.id == template.id)) return;
    final next = [
      for (final existing in current)
        if (existing.id != template.id) existing,
    ];
    await store.save(next);
    ref.invalidateSelf();
  }
}
