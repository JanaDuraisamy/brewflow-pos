import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'product_variants.dart';
import 'products.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Product recipes — shared-stock / raw-material consumption mapping
///
/// One row maps a sellable product (or one of its variants) to a stock-source
/// ingredient (a product, or one of its variants) with the quantity consumed
/// per unit sold. Example: Plain Maggi, Cheese Maggi, Egg Maggi and Veg Maggi
/// each map to 1 × Maggi Packet; a sale of any of them deducts the shared
/// Maggi Packet stock, never the menu product's own stock.
///
/// Rules:
/// - A menu line WITH recipe rows deducts ONLY its ingredients (aggregated
///   per ingredient across all lines, one conditional atomic deduction each).
///   Its own `stock_quantity` is never touched for that sale.
/// - Products WITHOUT recipe rows behave exactly as before (own/variant
///   stock deduction). No existing flow changes.
/// - `variant_id` NULL on a row means "every variant of this product".
/// - Ingredient products are ordinary products (purchased/restocked through
///   the existing purchase flow, alerting through the existing low-stock
///   rules, synced through the existing PRODUCT entity). Marking one
///   [Products.isIngredient] hides it from the sale shelf.
/// - Both ends CASCADE: deleting a menu product drops its mapping; deleting
///   an ingredient drops mappings that consume it (remaining menu products
///   then sell from their own stock per the rules above).
/// ---------------------------------------------------------------------------

@TableIndex(
  name: 'idx_product_recipes_product',
  columns: {#shopId, #productId, #variantId},
)
@TableIndex(name: 'idx_product_recipes_updated_at', columns: {#updatedAt})
class ProductRecipes extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => const Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning shop; null only for legacy/unsynced rows.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The sellable product this mapping belongs to.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// One variant of [productId], or NULL for every variant of the product.
  TextColumn get variantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// The stock-source ingredient product consumed per sale.
  TextColumn get ingredientProductId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// One variant of the ingredient, or NULL for the product-level stock.
  TextColumn get ingredientVariantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// Units of the ingredient consumed per ONE unit sold. Must be >= 1.
  IntColumn get quantity =>
      integer().customConstraint('NOT NULL CHECK (quantity >= 1)')();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives incremental sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
