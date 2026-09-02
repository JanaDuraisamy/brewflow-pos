import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Variants DAO
///
/// All Drift access for the product_variants table lives here. Query/row
/// logic only; the create/update transactions and business rules (SKU
/// uniqueness, stock and price validation, soft-deactivate-missing) live in
/// the inventory repository. Filtering and ordering happen in SQL.
/// ---------------------------------------------------------------------------

final class ProductVariantsDao {
  ProductVariantsDao(this._db);

  final AppDatabase _db;

  /// All variants of one product, oldest first (stable creation order).
  Future<List<ProductVariant>> forProduct(String productId, {String? shopId}) {
    final query = _db.select(_db.productVariants)
      ..where((t) => t.productId.equals(productId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (shopId != null) {
      query.where((t) => t.shopId.equals(shopId));
    }
    return query.get();
  }

  /// All variants grouped by product id, oldest first within each product.
  Future<Map<String, List<ProductVariant>>> allByProduct({
    String? shopId,
  }) async {
    final base = _db.select(_db.productVariants)
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]);
    if (shopId != null) {
      base.where((t) => t.shopId.equals(shopId));
    }
    final rows = await base.get();
    final byProduct = <String, List<ProductVariant>>{};
    for (final row in rows) {
      byProduct.putIfAbsent(row.productId, () => []).add(row);
    }
    return byProduct;
  }

  /// Whether a variant with this SKU already exists (case-insensitive).
  ///
  /// [exceptId] excludes one variant so an edit can keep its own SKU.
  /// When [shopId] is provided the check is scoped to that business.
  Future<bool> skuExists(String sku, {String? exceptId, String? shopId}) async {
    final table = _db.productVariants;
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

  Future<ProductVariant> insert(ProductVariantsCompanion companion) =>
      _db.into(_db.productVariants).insertReturning(companion);

  Future<void> update(String id, ProductVariantsCompanion companion) async {
    final updated = companion.copyWith(
      updatedAt: Value(DateTime.now().toUtc()),
    );
    await (_db.update(
      _db.productVariants,
    )..where((t) => t.id.equals(id))).write(updated);
  }

  /// Soft-deactivates every variant of [productId] whose id is not in
  /// [keepIds]. Never deletes rows — variant history is immutable.
  Future<void> deactivateMissing(String productId, Set<String> keepIds) async {
    final table = _db.productVariants;
    await (_db.update(table)..where(
          (t) =>
              t.productId.equals(productId) &
              t.id.isNotIn(keepIds) &
              t.isActive.equals(true),
        ))
        .write(
          ProductVariantsCompanion(
            isActive: const Value(false),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }
}
