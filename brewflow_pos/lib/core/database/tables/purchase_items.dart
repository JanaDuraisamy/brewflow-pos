import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'product_variants.dart';
import 'products.dart';
import 'purchases.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// PurchaseItems — line items of a completed purchase
///
/// The product name, SKU, unit cost and line total are snapshotted at
/// receiving time so historical purchase records never change when products
/// are later edited or deactivated — a purchase's cost history is immutable
/// even if [Products.costPricePaise] is later updated. Deleting a product (or
/// its purchase) is rejected by the RESTRICT foreign keys to protect history.
/// Variant lines snapshot the variant name the same way; variants are
/// soft-deactivated, never deleted, so their RESTRICT FK is safe.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_purchase_items_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_purchase_items_purchase_id',
  columns: {#shopId, #purchaseId},
)
class PurchaseItems extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this purchase item.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning purchase. Deleting a purchase with items is rejected (RESTRICT).
  TextColumn get purchaseId =>
      text().references(Purchases, #id, onDelete: KeyAction.restrict)();

  /// Product received. Deleting a product with purchase history is rejected.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Variant received; NULL for non-variant lines. RESTRICT protects history.
  TextColumn get variantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Product name at the time of the purchase (snapshot).
  TextColumn get productName => text()();

  /// Variant name at the time of the purchase (snapshot); NULL when the line
  /// is not a variant line.
  TextColumn get variantName => text().nullable()();

  /// Product SKU at the time of the purchase (snapshot); NULL when absent.
  TextColumn get sku => text().nullable()();

  /// Unit cost price in paise at purchase time. Must be >= 0.
  IntColumn get unitCostPaise =>
      integer().customConstraint('NOT NULL CHECK (unit_cost_paise >= 0)')();

  /// Quantity received. Must be > 0.
  IntColumn get quantity =>
      integer().customConstraint('NOT NULL CHECK (quantity > 0)')();

  /// unitCostPaise * quantity in paise. Must be >= 0.
  IntColumn get lineTotalPaise =>
      integer().customConstraint('NOT NULL CHECK (line_total_paise >= 0)')();
}
