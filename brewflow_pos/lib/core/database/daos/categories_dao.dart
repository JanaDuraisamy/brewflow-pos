import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Categories DAO
///
/// All Drift access for the categories table lives here. Query/row logic only;
/// business rules (duplicate names, safe deletion) are enforced by the
/// inventory repository.
/// ---------------------------------------------------------------------------

final class CategoriesDao {
  CategoriesDao(this._db);

  final AppDatabase _db;

  Future<List<Category>> getAll({String? shopId}) {
    final query = _db.select(_db.categories);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.get();
  }

  Stream<List<Category>> watchAll({String? shopId}) {
    final query = _db.select(_db.categories);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    query.orderBy([(t) => OrderingTerm.asc(t.name)]);
    return query.watch();
  }

  Future<Category?> getById(String id) => (_db.select(
    _db.categories,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Whether a category with this name already exists (case-insensitive).
  ///
  /// [exceptId] excludes one category so an edit can keep its own name.
  /// When [shopId] is provided the check is scoped to that business.
  Future<bool> nameExists(
    String name, {
    String? exceptId,
    String? shopId,
  }) async {
    final table = _db.categories;
    final query = _db.selectOnly(table)..addColumns([table.id]);
    final conditions = <Expression<bool>>[
      table.name.lower().equals(name.toLowerCase()),
    ];
    if (exceptId != null) {
      conditions.add(table.id.isNotValue(exceptId));
    }
    if (shopId != null) {
      conditions.add(table.shopId.equals(shopId));
    }
    query.where(conditions.reduce((a, b) => a & b));
    query.limit(1);
    return (await query.get()).isNotEmpty;
  }

  Future<Category> insert(CategoriesCompanion companion) =>
      _db.into(_db.categories).insertReturning(companion);

  Future<void> updateName(String id, String name) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> updateActive(String id, bool isActive) async {
    await (_db.update(_db.categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> deleteById(String id) async {
    await (_db.delete(_db.categories)..where((t) => t.id.equals(id))).go();
  }
}
