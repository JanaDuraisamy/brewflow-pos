import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expenses DAO
///
/// All Drift access for the expenses table lives here. Search, filtering and
/// ordering happen in SQL (never in memory); the category/payment enums map
/// through stable DB values at the repository boundary.
/// ---------------------------------------------------------------------------

final class ExpensesDao {
  ExpensesDao(this._db);

  final AppDatabase _db;

  /// Expenses matching [search]/[category]/[paymentMethod]/[fromUtc]/
  /// [toUtc]/[active], sorted by expense date (newest first, then created
  /// newest first).
  ///
  /// [search] matches name or note (case-insensitive substring); LIKE
  /// wildcards in user input are escaped so it is matched literally.
  Future<List<Expense>> query({
    String search = '',
    String? category,
    String? paymentMethod,
    DateTime? fromUtc,
    DateTime? toUtc,
    bool? active,
    String? shopId,
  }) {
    final query = _db.select(_db.expenses)
      ..where(
        (t) => _matches(
          t,
          search: search,
          category: category,
          paymentMethod: paymentMethod,
          fromUtc: fromUtc,
          toUtc: toUtc,
          active: active,
        ),
      )
      ..orderBy([
        (t) => OrderingTerm.desc(t.expenseDate),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  Future<Expense?> byId(String id, {String? shopId}) {
    final query = _db.select(_db.expenses)..where((t) => t.id.equals(id));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.getSingleOrNull();
  }

  /// Sum of the active NOT_PAID expenses — the shop payable total in paise.
  /// Zero when there is nothing outstanding.
  Future<int> payablePaise({String? shopId}) async {
    final expression = _db.expenses.amountPaise.sum();
    var condition =
        _db.expenses.paymentStatus.equals('NOT_PAID') &
        _db.expenses.isActive.equals(true);
    if (shopId != null) {
      condition = condition & _db.expenses.shopId.equals(shopId);
    }
    final rows =
        await (_db.selectOnly(_db.expenses)
              ..addColumns([expression])
              ..where(condition))
            .get();
    return rows.first.read(expression) ?? 0;
  }

  /// Active NOT_PAID expenses — the shop's payable rows — oldest expense
  /// date first (oldest dues surface at the top of the payables report).
  Future<List<Expense>> payables({String? shopId}) {
    final query = _db.select(_db.expenses)
      ..where(
        (t) => t.paymentStatus.equals('NOT_PAID') & t.isActive.equals(true),
      )
      ..orderBy([
        (t) => OrderingTerm.asc(t.expenseDate),
        (t) => OrderingTerm.asc(t.createdAt),
      ]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  Future<Expense> insert(ExpensesCompanion companion) =>
      _db.into(_db.expenses).insertReturning(companion);

  Future<void> update(String id, ExpensesCompanion companion) async {
    final updated = companion.copyWith(
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(
      _db.expenses,
    )..where((t) => t.id.equals(id))).write(updated);
  }

  Future<void> updateActive(String id, bool isActive) async {
    await (_db.update(_db.expenses)..where((t) => t.id.equals(id))).write(
      ExpensesCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Permanently removes an expense row.
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.expenses)..where((t) => t.id.equals(id))).go();
  }

  /// Shared WHERE expression for the expenses table.
  Expression<bool> _matches(
    $ExpensesTable t, {
    required String search,
    required String? category,
    required String? paymentMethod,
    required DateTime? fromUtc,
    required DateTime? toUtc,
    required bool? active,
  }) {
    Expression<bool> expression = const Constant<bool>(true);
    final needle = search.trim();
    if (needle.isNotEmpty) {
      final pattern = '%${_escapeLike(needle)}%';
      expression =
          expression &
          (t.name.like(pattern, escapeChar: r'\') |
              t.note.like(pattern, escapeChar: r'\'));
    }
    if (category != null) {
      expression = expression & t.category.equals(category);
    }
    if (paymentMethod != null) {
      expression = expression & t.paymentMethod.equals(paymentMethod);
    }
    if (fromUtc != null) {
      expression = expression & t.expenseDate.isBiggerOrEqualValue(fromUtc);
    }
    if (toUtc != null) {
      expression = expression & t.expenseDate.isSmallerOrEqualValue(toUtc);
    }
    if (active != null) {
      expression = expression & t.isActive.equals(active);
    }
    return expression;
  }

  /// Total still owed across every payee: the sum of active NOT_PAID expenses
  /// minus the non-reversed payments made against them.
  ///
  /// Payment subtraction happens PER PAYEE KEY in SQL before the totals are
  /// added, so an over-payment on one payee can never silently cancel another
  /// payee's debt. [paymentsForPayee] is the authoritative remaining-balance
  /// query; this is the same arithmetic reduced to a single number.
  Future<int> payablePaiseWithPayments({String? shopId}) async {
    final remaining = await remainingByPayeeKey(shopId: shopId);
    var total = 0;
    for (final value in remaining.values) {
      total += value;
    }
    return total;
  }

  /// Remaining balance per normalized payee key, in paise and never negative.
  ///
  /// This is the single source of truth for a payable balance. Both devices and
  /// the server derive the number from these two row sets with no stored state,
  /// which is what makes every device agree on it.
  ///
  /// Ordering is not guaranteed — callers sort for display.
  Future<Map<String, int>> remainingByPayeeKey({String? shopId}) async {
    final totals = await unpaidTotalsByPayeeKey(shopId: shopId);
    final paid = await paidTotalsByPayeeKey(shopId: shopId);

    final keys = <String>{...totals.keys, ...paid.keys};
    final result = <String, int>{};
    for (final key in keys) {
      final remaining = (totals[key] ?? 0) - (paid[key] ?? 0);
      // Clamp: a reversed or hidden expense must never surface as a negative
      // payable that the UI would render as credit.
      result[key] = remaining < 0 ? 0 : remaining;
    }
    return result;
  }

  /// Sum of active NOT_PAID expense amounts per normalized payee key.
  ///
  /// Grouping happens in SQL on `lower(trim(name))`, matching [PayeeKey.of]
  /// exactly, so "Milk" and "milk " land in the same bucket.
  Future<Map<String, int>> unpaidTotalsByPayeeKey({String? shopId}) async {
    final key = _db.expenses.name.trim().lower();
    final sum = _db.expenses.amountPaise.sum();
    var condition =
        _db.expenses.paymentStatus.equals('NOT_PAID') &
        _db.expenses.isActive.equals(true);
    if (shopId != null) {
      condition = condition & _db.expenses.shopId.equals(shopId);
    }
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([key, sum])
      ..where(condition)
      ..groupBy([key]);
    final rows = await query.get();
    final out = <String, int>{};
    for (final row in rows) {
      out[row.read(key)!] = row.read(sum) ?? 0;
    }
    return out;
  }

  /// Sum of non-reversed payment amounts per payee key.
  Future<Map<String, int>> paidTotalsByPayeeKey({String? shopId}) async {
    final key = _db.expensePayments.payeeKey;
    final sum = _db.expensePayments.amountPaise.sum();
    var condition = _db.expensePayments.reversed.equals(false);
    if (shopId != null) {
      condition = condition & _db.expensePayments.shopId.equals(shopId);
    }
    final query = _db.selectOnly(_db.expensePayments)
      ..addColumns([key, sum])
      ..where(condition)
      ..groupBy([key]);
    final rows = await query.get();
    final out = <String, int>{};
    for (final row in rows) {
      out[row.read(key)!] = row.read(sum) ?? 0;
    }
    return out;
  }

  /// Grouped payable inputs per payee key: unpaid total, how many expense rows
  /// are grouped, the oldest expense date, the display name, and the most
  /// recent payment date (null when never paid).
  ///
  /// [displayName] picks the trimmed original casing of the most recently
  /// created expense in the group, so the UI shows the name as the user last
  /// typed it while grouping still works on the normalized key.
  Future<Map<String, PayableGroupRow>> payableGroups({String? shopId}) async {
    final key = _db.expenses.name.trim().lower();
    final display = _db.expenses.name.trim();
    final sum = _db.expenses.amountPaise.sum();
    final count = _db.expenses.id.count();
    final oldest = _db.expenses.expenseDate.min();
    final newest = _db.expenses.createdAt.max();
    var condition =
        _db.expenses.paymentStatus.equals('NOT_PAID') &
        _db.expenses.isActive.equals(true);
    if (shopId != null) {
      condition = condition & _db.expenses.shopId.equals(shopId);
    }

    // `max(created_at)` picks the row whose trimmed name becomes the display
    // label: SQLite's bare-column-with-max() rule returns the values from the
    // row holding the maximum, which is exactly the latest-created expense.
    final rows =
        await (_db.selectOnly(_db.expenses)
              ..addColumns([key, sum, count, oldest, newest, display])
              ..where(condition)
              ..groupBy([key]))
            .get();

    final groups = <String, PayableGroupRow>{};
    for (final row in rows) {
      final groupKey = row.read(key)!;
      final lastPaidAt = await _lastPaidAtForPayee(groupKey, shopId);
      groups[groupKey] = PayableGroupRow(
        payeeKey: groupKey,
        payeeName: row.read(display) ?? groupKey,
        totalPaise: row.read(sum) ?? 0,
        expenseCount: row.read(count) ?? 0,
        oldestExpenseDate: row.read(oldest)!,
        lastPaidAt: lastPaidAt,
      );
    }
    return groups;
  }

  Future<DateTime?> _lastPaidAtForPayee(String payeeKey, String? shopId) async {
    final column = _db.expensePayments.paidAt;
    var condition =
        _db.expensePayments.payeeKey.equals(payeeKey) &
        _db.expensePayments.reversed.equals(false);
    if (shopId != null) {
      condition = condition & _db.expensePayments.shopId.equals(shopId);
    }
    final row =
        await (_db.selectOnly(_db.expensePayments)
              ..addColumns([column.max()])
              ..where(condition))
            .getSingleOrNull();
    return row?.read(column.max());
  }

  /// One recorded payment row, for validating a payee before paying.
  Future<db.ExpensePayment?> expensePaymentById(String id) {
    return (_db.select(
      _db.expensePayments,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Non-reversed payments for a payee, newest first.
  Future<List<db.ExpensePayment>> expensePaymentsForPayee(
    String payeeKey, {
    String? shopId,
  }) {
    final query = _db.select(_db.expensePayments)
      ..where((t) => t.payeeKey.equals(payeeKey) & t.reversed.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.paidAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  /// All non-reversed payments, newest first, optionally for one payee.
  Future<List<db.ExpensePayment>> expensePayments({
    String? payeeKey,
    String? shopId,
  }) {
    final query = _db.select(_db.expensePayments)
      ..where((t) => t.reversed.equals(false))
      ..orderBy([
        (t) => OrderingTerm.desc(t.paidAt),
        (t) => OrderingTerm.desc(t.createdAt),
      ]);
    if (payeeKey != null) {
      query.where((t) => t.payeeKey.equals(payeeKey));
    }
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  /// Inserts an append-only payment row and returns the stored row, so the
  /// caller can build the matching sync envelope without a second lookup.
  /// Callers run this inside their own transaction.
  Future<db.ExpensePayment> insertExpensePayment(
    db.ExpensePaymentsCompanion row,
  ) {
    return _db.into(_db.expensePayments).insertReturning(row);
  }

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Grouped payable inputs for one payee key, as read by
/// [ExpensesDao.payableGroups].
///
/// The repository combines this with the paid total to build the public
/// [ShopPayable] model, keeping grouping SQL in the DAO and money math in the
/// domain.
final class PayableGroupRow {
  const PayableGroupRow({
    required this.payeeKey,
    required this.payeeName,
    required this.totalPaise,
    required this.expenseCount,
    required this.oldestExpenseDate,
    this.lastPaidAt,
  });

  final String payeeKey;
  final String payeeName;
  final int totalPaise;
  final int expenseCount;
  final DateTime oldestExpenseDate;
  final DateTime? lastPaidAt;
}
