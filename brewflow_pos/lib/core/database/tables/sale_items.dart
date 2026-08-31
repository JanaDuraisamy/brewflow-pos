import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'product_variants.dart';
import 'products.dart';
import 'sales.dart';

/// ---------------------------------------------------------------------------
/// SaleItems — line items of a completed sale
///
/// The product name, SKU, unit price and line total are snapshotted at sale
/// time so historical receipts never change when products are later edited
/// or deactivated. Deleting a product (or its sale) is rejected by the
/// RESTRICT foreign keys to protect history. Variant lines snapshot the
/// variant name the same way; variants are soft-deactivated, never deleted,
/// so their RESTRICT FK is safe.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_sale_items_sale_id', columns: {#saleId})
class SaleItems extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning sale. Deleting a sale with items is rejected (RESTRICT).
  TextColumn get saleId =>
      text().references(Sales, #id, onDelete: KeyAction.restrict)();

  /// Product sold. Deleting a product with sale history is rejected.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Variant sold; NULL for non-variant lines. RESTRICT protects history.
  TextColumn get variantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Product name at the time of the sale (snapshot).
  TextColumn get productName => text()();

  /// Variant name at the time of the sale (snapshot); NULL when the line is
  /// not a variant line.
  TextColumn get variantName => text().nullable()();

  /// Product SKU at the time of the sale (snapshot); NULL when absent.
  TextColumn get sku => text().nullable()();

  /// Unit selling price in paise at sale time. Must be >= 0.
  IntColumn get unitPricePaise =>
      integer().customConstraint('NOT NULL CHECK (unit_price_paise >= 0)')();

  /// Quantity sold. Must be > 0.
  IntColumn get quantity =>
      integer().customConstraint('NOT NULL CHECK (quantity > 0)')();

  /// unitPricePaise * quantity in paise. Must be >= 0.
  IntColumn get lineTotalPaise =>
      integer().customConstraint('NOT NULL CHECK (line_total_paise >= 0)')();
}
