import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'product_variants.dart';
import 'products.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// ShopProductStock — per-business stock overlay for a shared product
///
/// A product row is a MASTER definition owned by one business (the Cafe, in
/// this deployment). [Products.visibleInShops] then makes that one definition
/// sellable from another business (the Food Truck) without duplicating the
/// product, its variants, its price or its category.
///
/// The definition is shared; the STOCK MUST NOT BE. A Cafe menu item and a
/// Food Truck menu item are the same drink but they are drawn from different
/// shelves, so "30 in the truck" must never come out of the Cafe's 100.
///
/// This table is that second shelf. A row holds the quantity THAT business may
/// sell, for one sellable unit: the product itself when [ShopProductStock
/// .variantId] is NULL, or one of its variants when it is set. Its absence is
/// meaningful — a business with no row for a unit is not selling that unit and
/// must not be able to invent stock for it by selling it anyway. The read rules
/// that consume this live with the sales shelf (see the POS and billing
/// repositories), never in the table.
///
/// A product that a business OWNS keeps using [Products.stockQuantity] as its
/// stock; an overlay row is only needed to give a *foreign* product a stock
/// level. The two never both apply, so there is no ambiguity about which
/// number is authoritative.
///
/// VARIANT SCOPE IS NOT OPTIONAL. The Jiggar menu sells 'SPL Milk Chai'
/// (100ml / 160ml) and 'SPL Milkshakes' (Mango / Vanilla / Strawberry): a
/// product-level overlay could only ever express one number for the whole
/// product, so the truck's 160ml bottles and its 100ml bottles would have to
/// share a single pile — and a 160ml sale would silently eat 100ml stock.
/// Each sellable unit therefore gets its own row.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_shop_product_stock_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_shop_product_stock_product',
  columns: {#shopId, #productId},
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_shop_product_stock_product_level '
  'ON shop_product_stock (shop_id, product_id) WHERE variant_id IS NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX ux_shop_product_stock_variant_level '
  'ON shop_product_stock (shop_id, product_id, variant_id) '
  'WHERE variant_id IS NOT NULL',
)
class ShopProductStock extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// The BUSINESS this quantity belongs to. A Cafe sale and a Food Truck sale
  /// of the same product are two different rows here.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The shared master product whose definition this business reuses. Cascades
  /// so a product deletion can never leave an orphan overlay row pointing at a
  /// product that no longer exists.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// The variant this quantity belongs to, or NULL when the row tracks the
  /// product itself. RESTRICT mirrors [ProductVariants]' own rule that
  /// variants are soft-deactivated, never hard-deleted, so an overlay row can
  /// never lose the variant its number describes.
  ///
  /// [productId] and [variantId] travel together and the two indexes below are
  /// both keyed on the pair, so a row can never claim a variant under the
  /// wrong product as far as a lookup is concerned. The database does NOT
  /// enforce that they agree: because the variant-level index also includes
  /// [productId], a mismatched pair would simply be a *different* key rather
  /// than a duplicate. The DAO therefore rejects the mismatch before the write
  /// — see the variant-belongs-to-product check in the overlay writes.
  TextColumn get variantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// This business's own quantity of the unit. Money-free, so the same
  /// >= 0 guard as [Products.stockQuantity] applies: a negative shelf would let
  /// a sale hand out stock that was never there.
  IntColumn get quantity =>
      integer().customConstraint('NOT NULL DEFAULT 0 CHECK (quantity >= 0)')();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// At most ONE row per business per sellable unit, enforced by the two
  /// partial unique indexes above rather than by `uniqueKeys`: a plain
  /// `UNIQUE (shop_id, product_id, variant_id)` would be useless here because
  /// SQLite treats NULLs as distinct, so it would happily accept any number of
  /// product-level rows for the same business. The uniqueness is what makes the
  /// conditional `UPDATE ... WHERE quantity >= n` deduction safe, and what
  /// makes an overlay read a single-row lookup instead of a SUM.
  ///
  /// The indexes are separate objects rather than part of `uniqueKeys`, so the
  /// v28 -> v29 migration has to create them explicitly — see
  /// `AppMigrations.from28To29`.
}
