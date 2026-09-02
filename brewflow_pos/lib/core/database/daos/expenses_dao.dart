import 'package:brewflow_pos/core/database/app_database.dart';
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

  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}
