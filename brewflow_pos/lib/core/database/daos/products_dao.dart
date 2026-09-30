import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Products DAO
///
/// All Drift access for the products table lives here. Search and filtering
/// happen in SQL (never in memory); business rules (SKU uniqueness, price and
/// stock validation, safe category deletion) live in the inventory repository.
/// ---------------------------------------------------------------------------

final class ProductsDao {
  ProductsDao(this._db);

  final AppDatabase _db;

  /// Products filtered and sorted in SQL.
  ///
  /// [search] matches product name or SKU (case-insensitive substring).
  /// [active] restricts to active/inactive items when non-null.
  /// [shopId] when provided restricts to products for that shop.
  Future<List<Product>> query({
    String? search,
    String? categoryId,
    bool? active,
    String? shopId,
  }) {
    final query = _db.select(_db.products)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final text = search?.trim();
    if (text != null && text.isNotEmpty) {
      query.where((t) => t.name.contains(text) | t.sku.contains(text));
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (active != null) {
      query.where((t) => t.isActive.equals(active));
    }
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  /// Products filtered and sorted in SQL, scoped to a business shop with
  /// optional shared‑product visibility from the catalog owner.
  ///
  /// When [shopId] and [catalogOwnerShopId] are the same (Cafe mode) the
  /// second clause is a no‑op and the query reduces to “own products only”,
  /// preserving existing Cafe behaviour.
  Future<List<Product>> queryForBusiness({
    String? search,
    String? categoryId,
    bool? active,
    required String shopId,
    required String catalogOwnerShopId,
  }) {
    final query = _db.select(_db.products)
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);

    final text = search?.trim();
    if (text != null && text.isNotEmpty) {
      query.where((t) => t.name.contains(text) | t.sku.contains(text));
    }
    if (categoryId != null) {
      query.where((t) => t.categoryId.equals(categoryId));
    }
    if (active != null) {
      query.where((t) => t.isActive.equals(active));
    }
    // Owned by the active shop, OR shared from the catalog owner when
    // visibleInShops is true. These must be a single OR expression: successive
    // where() calls are combined with AND, which asked for one row to be owned
    // by two different shops at once and matched nothing for the Food Truck.
    query.where(
      (t) =>
          t.shopId.equals(shopId) |
          (t.shopId.equals(catalogOwnerShopId) & t.visibleInShops),
    );

    return query.get();
  }

  /// Whether a product with this SKU already exists (case-insensitive).
  ///
  /// [exceptId] excludes one product so an edit can keep its own SKU.
  /// When [shopId] is provided the check is scoped to that business.
  Future<bool> skuExists(String sku, {String? exceptId, String? shopId}) async {
    final table = _db.products;
    final query = _db.selectOnly(table)..addColumns([table.id]);
    final conditions = <Expression<bool>>[
      table.sku.lower().equals(sku.toLowerCase()),
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

  Future<Product> insert(ProductsCompanion companion) =>
      _db.into(_db.products).insertReturning(companion);

  Future<Product?> byId(String id, {String? shopId}) {
    final query = _db.select(_db.products)..where((t) => t.id.equals(id));
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.getSingleOrNull();
  }

  /// Whether [id] is a row the caller is allowed to mutate.
  ///
  /// The Food Truck can *see* a Cafe master product because the Cafe shared it,
  /// but seeing is not owning: an ID-only deactivate or delete would strip the
  /// Cafe's catalogue. [shopIds] is the explicit allow-set of shops whose rows
  /// may change. Null keeps the historical unscoped behaviour, an empty list
  /// matches nothing, and a legacy null-`shop_id` row stays claimable so an
  /// upgrade does not orphan pre-existing products.
  Future<bool> isOwnedBy(String id, List<String>? shopIds) async {
    if (shopIds == null) return true;
    if (shopIds.isEmpty) return false;
    final row = await byId(id);
    if (row == null) return false;
    final owner = row.shopId;
    return owner == null || shopIds.contains(owner);
  }

  Future<void> update(String id, ProductsCompanion companion) async {
    final updated = companion.copyWith(
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(
      _db.products,
    )..where((t) => t.id.equals(id))).write(updated);
  }

  Future<void> updateActive(String id, bool isActive) async {
    await (_db.update(_db.products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<int> countByCategory(String categoryId, {String? shopId}) async {
    final table = _db.products;
    final query = _db.selectOnly(table)..addColumns([table.id.count()]);
    var condition = table.categoryId.equals(categoryId);
    if (shopId != null) {
      condition = condition & table.shopId.equals(shopId);
    }
    query.where(condition);
    return query.map((row) => row.read(table.id.count())!).getSingle();
  }

  /// Total number of rows that reference this product across variants, sale
  /// lines, purchase lines and stock movements. Non-zero means the product
  /// must be soft-deactivated, never hard-deleted (its audit history stays).
  Future<int> countReferences(String id) async {
    final variants = _db.selectOnly(_db.productVariants)
      ..addColumns([_db.productVariants.id.count()])
      ..where(_db.productVariants.productId.equals(id));
    final saleItems = _db.selectOnly(_db.saleItems)
      ..addColumns([_db.saleItems.id.count()])
      ..where(_db.saleItems.productId.equals(id));
    final purchaseItems = _db.selectOnly(_db.purchaseItems)
      ..addColumns([_db.purchaseItems.id.count()])
      ..where(_db.purchaseItems.productId.equals(id));
    final movements = _db.selectOnly(_db.stockMovements)
      ..addColumns([_db.stockMovements.id.count()])
      ..where(_db.stockMovements.productId.equals(id));
    var total = 0;
    total += await variants
        .map((row) => row.read(_db.productVariants.id.count())!)
        .getSingle();
    total += await saleItems
        .map((row) => row.read(_db.saleItems.id.count())!)
        .getSingle();
    total += await purchaseItems
        .map((row) => row.read(_db.purchaseItems.id.count())!)
        .getSingle();
    total += await movements
        .map((row) => row.read(_db.stockMovements.id.count())!)
        .getSingle();
    return total;
  }

  /// Permanently removes a product row. Only safe to call after confirming
  /// [countReferences] returns zero; otherwise a foreign-key failure is thrown.
  Future<void> deleteById(String id) async {
    await (_db.delete(_db.products)..where((t) => t.id.equals(id))).go();
  }
}
