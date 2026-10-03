import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'products.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// ProductVariants — sellable size/option rows of a product
///
/// A variant is its own stock-bearing entity: it carries its own SKU, prices,
/// stock, low-stock policy, membership pricing and soft-delete flag, and every
/// stock movement for a variant identifies the variant (and its parent
/// product) so the audit trail stays exact.
///
/// Conventions:
/// - Money is stored as INTEGER minor units (paise), exactly like [Products].
/// - A variant is part of its product's *definition*, not its history: it is
///   hard-deleted by the product's CASCADE, never soft-deactivated. No
///   historical row can block that, because every historical variant
///   reference is a plain FK-free column (schema v31) carrying a name
///   snapshot of its own.
/// - [ProductVariants.isActive] still exists for hiding a variant from sale
///   without deleting it.
/// - [ProductVariants.stockQuantity] is the authoritative stock for a variant;
///   when a product has variants, the parent [Products.stockQuantity] is a
///   derived mirror maintained by the repository.
/// - low-stock policy and membership pricing mirror the product-level
///   semantics; a variant's effective threshold falls back to its parent
///   product's policy, then to the global default.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_product_variants_shop', columns: {#shopId})
@TableIndex(name: 'idx_product_variants_product_id', columns: {#productId})
@TableIndex(name: 'idx_product_variants_sku', columns: {#sku})
@TableIndex(
  name: 'idx_product_variants_updated_at',
  columns: {#shopId, #updatedAt},
)
class ProductVariants extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this product variant.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning product. CASCADE so deleting a product takes its variants with it:
  /// a variant is part of the product's *definition*, not of its history, so a
  /// true product delete must not leave an orphan variant row behind. Every
  /// historical reference to a variant (sale_items, purchase_items,
  /// stock_movements) is a plain, FK-free column, so nothing blocks the cascade
  /// and no historical row is touched — the variantName snapshot on each line is
  /// what receipts and reports read.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.cascade)();

  /// Variant display name, e.g. '250 ml'.
  TextColumn get name => text()();

  /// Variant stock keeping unit / code. Unique when present, scoped per shop.
  TextColumn get sku => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, sku},
  ];

  /// Selling price in paise. Must be >= 0.
  IntColumn get sellingPricePaise =>
      integer().customConstraint('NOT NULL CHECK (selling_price_paise >= 0)')();

  /// Cost price in paise; NULL when unknown. Must be >= 0 when present.
  IntColumn get costPricePaise => integer().nullable().customConstraint(
    'CHECK (cost_price_paise IS NULL OR cost_price_paise >= 0)',
  )();

  /// Current variant stock quantity. Must be >= 0.
  IntColumn get stockQuantity => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0)',
  )();

  /// How low-stock is decided for this variant:
  /// USE_DEFAULT = fall back to the parent product's policy (and then the
  /// global threshold), CUSTOM = use [ProductVariants.lowStockThreshold],
  /// OFF = never flagged as low stock.
  TextColumn get lowStockMode => text().customConstraint(
    "NOT NULL DEFAULT 'USE_DEFAULT' CHECK "
    "(low_stock_mode IN ('USE_DEFAULT', 'CUSTOM', 'OFF'))",
  )();

  /// Per-variant low-stock threshold; only meaningful when
  /// [ProductVariants.lowStockMode] is CUSTOM. Must be >= 0 when present.
  IntColumn get lowStockThreshold => integer().nullable().customConstraint(
    'CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0)',
  )();

  /// Whether a member pricing tier exists for this variant.
  BoolColumn get membershipEnabled => boolean().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (membership_enabled IN (0, 1))',
  )();

  /// Member-tier selling price in paise; required when
  /// [ProductVariants.membershipEnabled] is true.
  IntColumn get memberPricePaise => integer().nullable().customConstraint(
    'CHECK (member_price_paise IS NULL OR member_price_paise >= 0)',
  )();

  /// Soft switch to hide a variant from the POS without deleting it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
