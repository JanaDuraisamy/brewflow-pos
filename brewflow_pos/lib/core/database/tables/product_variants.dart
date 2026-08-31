import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'products.dart';

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
/// - Variants are never hard-deleted: they are soft-deactivated through
///   [ProductVariants.isActive] to protect order and movement history
///   (parent products follow the same rule, so RESTRICT is safe).
/// - [ProductVariants.stockQuantity] is the authoritative stock for a variant;
///   when a product has variants, the parent [Products.stockQuantity] is a
///   derived mirror maintained by the repository.
/// - low-stock policy and membership pricing mirror the product-level
///   semantics; a variant's effective threshold falls back to its parent
///   product's policy, then to the global default.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_product_variants_product_id', columns: {#productId})
@TableIndex(name: 'idx_product_variants_sku', columns: {#sku})
@TableIndex(name: 'idx_product_variants_updated_at', columns: {#updatedAt})
class ProductVariants extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Owning product. Products are never hard-deleted (soft deactivation
  /// instead); RESTRICT keeps variant history bound to its owner.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.restrict)();

  /// Variant display name, e.g. '250 ml'.
  TextColumn get name => text()();

  /// Variant stock keeping unit / code. Unique when present.
  TextColumn get sku => text().nullable().unique()();

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
