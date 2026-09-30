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

  /// Categories reachable from the active business.
  ///
  /// Two sources, and the difference matters:
  ///
  ///  * Categories the business OWNS are always listed, even when currently
  ///    empty, so a freshly created category is immediately selectable.
  ///  * Categories belonging to the catalog owner are listed ONLY when a
  ///    product the business may actually see sits in them. Deriving this from
  ///    the product table rather than from the category's own `shop_id` is what
  ///    stops a hidden product from leaking the shape of the Cafe's catalogue:
  ///    an unshared product's category must not appear as an empty filter on the
  ///    truck's screen.
  ///
  /// The visibility rule mirrors `ProductsDao.queryForBusiness` exactly — own
  /// rows, plus the owner's rows when `visibleInShops` is set — so the filter
  /// list and the product list can never disagree.
  Future<List<Category>> queryForBusiness({
    required String shopId,
    required String catalogOwnerShopId,
  }) async {
    final products = _db.products;
    final sharedCategoryIds =
        await (_db.selectOnly(products)
              ..addColumns([products.categoryId])
              ..where(
                products.shopId.equals(catalogOwnerShopId) &
                    products.visibleInShops &
                    products.categoryId.isNotNull(),
              ))
            .get();
    // Deduped here rather than in SQL: the row count here is bounded by the
    // shared catalogue, and a plain Set keeps the query portable across
    // SQLite versions whose DISTINCT support in subqueries varies.
    final reachable = sharedCategoryIds
        .map((row) => row.read(products.categoryId))
        .whereType<String>()
        .toSet();

    final categories = await getAll();
    return categories
        .where(
          (category) =>
              category.shopId == shopId ||
              (category.shopId == catalogOwnerShopId &&
                  reachable.contains(category.id)),
        )
        .toList();
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

  /// Whether [id] is a row the caller is allowed to mutate.
  ///
  /// Null means "no business context" and every row qualifies, matching the
  /// unscoped callers. A non-empty list is an explicit allow-set: a row owned by
  /// another shop must not be touched through an ID-only call. A legacy row with
  /// a null `shop_id` predates multi-shop and stays claimable, otherwise an
  /// upgrade would orphan the user's existing categories.
  Future<bool> isOwnedBy(String id, List<String>? shopIds) async {
    if (shopIds == null) return true;
    if (shopIds.isEmpty) return false;
    final row = await getById(id);
    if (row == null) return false;
    final owner = row.shopId;
    return owner == null || shopIds.contains(owner);
  }

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
