import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shop Product Stock DAO
///
/// All Drift access for the `shop_product_stock` overlay table lives here.
/// Query/row logic only; the effective-stock rules (which shelf a business
/// actually sells from), the variant-ownership check and failure mapping live
/// in the shop-product-stock repository.
///
/// Every method here takes an EXPLICIT, REQUIRED [shopId]. There is no
/// optional/unscoped variant on purpose. This table is per business by
/// definition, and the one bug this class exists to make impossible is reading
/// the Cafe's shelf while selling from the truck. A nullable shopId is exactly
/// the kind of convenience that turns into a cross-business stock leak, so the
/// signature makes the caller name the business on every call.
///
/// The two partial unique indexes from v29
/// (`ux_shop_product_stock_product_level`, `ux_shop_product_stock_variant_level`)
/// are what make a single-row lookup correct and the conditional
/// `UPDATE ... WHERE quantity >= n` deduction race-safe. They are enforced by
/// the database, but they are NOT the variant-ownership check: a unique index
/// can only reject an exact duplicate key, never a row that pairs a variant
/// with the wrong product. That validation lives in the repository.
/// ---------------------------------------------------------------------------

final class ShopProductStockDao {
  ShopProductStockDao(this._db);

  final AppDatabase _db;

  /// The overlay row for one sellable unit in one business, or null when that
  /// business has no shelf for it.
  ///
  /// [variantId] null targets the product-level shelf (`variant_id IS NULL`);
  /// a [variantId] targets that variant's shelf. The two levels are never mixed
  /// — a product-level row must not satisfy a variant-level lookup or the
  /// truck's 160ml shelf would be satisfied by the product's own count.
  ///
  /// A null result is meaningful, not an error: it means the business is NOT
  /// selling that unit. See the repository's effective-stock rules.
  Future<ShopProductStockData?> find({
    required String shopId,
    required String productId,
    String? variantId,
  }) {
    return (_db.select(_db.shopProductStock)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.productId.equals(productId) &
              (variantId == null
                  ? t.variantId.isNull()
                  : t.variantId.equals(variantId)),
        ))
        .getSingleOrNull();
  }

  /// Every overlay row for one business, newest shelf first.
  ///
  /// Used to render a whole business's foreign catalogue. Scoped to [shopId]
  /// for the same reason as [find]: the Cafe's shelves must never appear in a
  /// Food Truck stock list.
  Future<List<ShopProductStockData>> listForShop(String shopId) {
    return (_db.select(_db.shopProductStock)
          ..where((t) => t.shopId.equals(shopId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.productId),
            (t) => OrderingTerm.asc(t.variantId),
          ]))
        .get();
  }

  /// Every VARIANT-level overlay row one business holds for one product.
  ///
  /// This is the shop-scoped read that [listForProduct] is not. Computing what
  /// a business may sell must never go through a cross-business query and then
  /// filter in memory: that pattern is correct by construction only as long as
  /// the filter is remembered, and a forgotten filter hands the Cafe's number to
  /// the truck. The `shop_id` is therefore part of the SQL, not the Dart.
  ///
  /// Product-level rows are excluded: they never satisfy a variant shelf.
  Future<List<ShopProductStockData>> listVariantsForProduct({
    required String shopId,
    required String productId,
  }) {
    return (_db.select(_db.shopProductStock)
          ..where(
            (t) =>
                t.shopId.equals(shopId) &
                t.productId.equals(productId) &
                t.variantId.isNotNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.variantId)]))
        .get();
  }

  /// Every overlay row for one product across all businesses.
  ///
  /// ONLY for owner-facing views (e.g. "the truck is carrying 12"), never for
  /// computing what a business may sell. That is always [find] or
  /// [listVariantsForProduct] with an explicit shop. No call from
  /// `ShopProductStockRepository` uses this.
  Future<List<ShopProductStockData>> listForProduct(String productId) {
    return (_db.select(_db.shopProductStock)
          ..where((t) => t.productId.equals(productId))
          ..orderBy([(t) => OrderingTerm.asc(t.shopId)]))
        .get();
  }

  /// Whether the owning shop of [productId] is [shopId].
  ///
  /// The ownership test that decides which of the two shelves applies. Kept here
  /// as a single-column read so the decision is made in SQL against the current
  /// row rather than from a stale in-memory copy.
  Future<bool> isOwnedByShop({
    required String productId,
    required String shopId,
  }) async {
    final table = _db.products;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.shopId])
              ..where(table.id.equals(productId)))
            .getSingleOrNull();
    return row?.read(table.shopId) == shopId;
  }

  /// The parent product of [variantId], or null when the variant does not
  /// exist.
  ///
  /// This is the variant-ownership check. It must be consulted before ANY
  /// variant-level overlay write, because the v29 unique index keys on
  /// `(shop_id, product_id, variant_id)` and therefore cannot reject a row that
  /// pairs a real variant with the WRONG product — that is simply a different
  /// key. Without this read, `p-chai` could end up with a shelf that actually
  /// describes `pv-chai-100` of some other product, and every later deduction
  /// would move the wrong number.
  Future<String?> productIdOfVariant(String variantId) async {
    final table = _db.productVariants;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.productId])
              ..where(table.id.equals(variantId)))
            .getSingleOrNull();
    return row?.read(table.productId);
  }

  /// Creates the overlay row for one sellable unit in one business.
  ///
  /// Returns the persisted row. The caller is responsible for having validated
  /// ownership and the product/variant pairing first; this method only writes.
  Future<ShopProductStockData> insert(ShopProductStockCompanion companion) {
    return _db.into(_db.shopProductStock).insertReturning(companion);
  }

  /// Sets the quantity of an existing overlay row, returning the number of rows
  /// actually written.
  ///
  /// Zero means the row does not exist for this business/unit. Callers use that
  /// to decide between [upsert] and reporting a missing shelf — they must not
  /// silently create one, or a "correct the Cafe's number" bug would turn into
  /// a phantom Food Truck shelf.
  Future<int> updateQuantity({
    required String shopId,
    required String productId,
    String? variantId,
    required int quantity,
  }) {
    return (_db.update(_db.shopProductStock)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.productId.equals(productId) &
              (variantId == null
                  ? t.variantId.isNull()
                  : t.variantId.equals(variantId)),
        ))
        .write(
          ShopProductStockCompanion(
            quantity: Value(quantity),
            updatedAt: Value(DateTime.now().toUtc()),
          ),
        );
  }

  /// Conditionally deducts [delta] from an existing overlay row, but only while
  /// enough stock remains.
  ///
  /// The `quantity >= delta` guard is what makes this safe under concurrency:
  /// two simultaneous sales of the last unit cannot both pass it, so the second
  /// one writes zero rows instead of driving the shelf negative. The caller
  /// treats a zero return as insufficient stock.
  ///
  /// Returns the quantity AFTER the deduction, or null when nothing was written
  /// (no such shelf, or insufficient stock).
  ///
  /// The v29 `CHECK (quantity >= 0)` is the last line of defence rather than
  /// the mechanism: a plain "read then write" would pass the check and still
  /// lose a unit to a race.
  Future<int?> deductQuantity({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    final table = _db.shopProductStock;
    final updated =
        await (_db.update(table)..where(
              (t) =>
                  t.shopId.equals(shopId) &
                  t.productId.equals(productId) &
                  (variantId == null
                      ? t.variantId.isNull()
                      : t.variantId.equals(variantId)) &
                  t.quantity.isBiggerOrEqualValue(delta),
            ))
            .write(
              // `custom` rather than the typed constructor: the deduction is a
              // SQL expression (`quantity - ?`), and a plain companion field can
              // only carry a literal value.
              ShopProductStockCompanion.custom(
                quantity: table.quantity - Variable<int>(delta),
                updatedAt: Variable(DateTime.now().toUtc()),
              ),
            );
    if (updated == 0) return null;

    final row = await find(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
    );
    return row?.quantity;
  }

  /// Restores [delta] to an existing overlay row, returning the quantity after.
  ///
  /// Used to put a unit back (a voided sale). Restores only an existing shelf:
  /// if the row is gone there is nothing to restore onto, and creating one here
  /// would resurrect a deleted shelf with a made-up number. Returns null in
  /// that case so the caller can decide.
  Future<int?> restoreQuantity({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    final table = _db.shopProductStock;
    final updated =
        await (_db.update(table)..where(
              (t) =>
                  t.shopId.equals(shopId) &
                  t.productId.equals(productId) &
                  (variantId == null
                      ? t.variantId.isNull()
                      : t.variantId.equals(variantId)),
            ))
            .write(
              ShopProductStockCompanion.custom(
                quantity: table.quantity + Variable<int>(delta),
                updatedAt: Variable(DateTime.now().toUtc()),
              ),
            );
    if (updated == 0) return null;

    final row = await find(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
    );
    return row?.quantity;
  }

  /// Removes the overlay row for one sellable unit in one business.
  ///
  /// Returns the number of rows removed (0 or 1 — the v29 partial unique
  /// indexes guarantee at most one). "Not sellable" is represented by the
  /// ABSENCE of a row, so deleting one is how a business stops carrying a
  /// shared product. Any stock movement history lives in `stock_movements` and
  /// is untouched.
  Future<int> deleteShelf({
    required String shopId,
    required String productId,
    String? variantId,
  }) {
    return (_db.delete(_db.shopProductStock)..where(
          (t) =>
              t.shopId.equals(shopId) &
              t.productId.equals(productId) &
              (variantId == null
                  ? t.variantId.isNull()
                  : t.variantId.equals(variantId)),
        ))
        .go();
  }

  /// Removes every overlay row a business holds for one product, at both
  /// levels.
  ///
  /// Used when the owner unpublishes a product from that business: leaving
  /// variant-level rows behind would keep the variants sellable through a
  /// product the business can no longer see.
  Future<int> deleteShelvesForProduct({
    required String shopId,
    required String productId,
  }) {
    return (_db.delete(_db.shopProductStock)..where(
          (t) => t.shopId.equals(shopId) & t.productId.equals(productId),
        ))
        .go();
  }
}
