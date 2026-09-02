import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'categories.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Products — POS sellable items
///
/// Conventions:
/// - Money is stored as INTEGER minor units (paise) to stay exact:
///   `sellingPricePaise = 14950` means `₹149.50`. Never use floating point
///   for money in this codebase.
/// - [Products.stockQuantity] is the local stock snapshot; the sync engine
///   will reconcile it with the server later.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_products_shop', columns: {#shopId})
@TableIndex(name: 'idx_products_category_id', columns: {#categoryId})
@TableIndex(name: 'idx_products_name', columns: {#name})
@TableIndex(name: 'idx_products_updated_at', columns: {#shopId, #updatedAt})
class Products extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this product.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning category. Deleting a category with products is rejected
  /// (RESTRICT) to protect order and inventory history.
  TextColumn get categoryId =>
      text().references(Categories, #id, onDelete: KeyAction.restrict)();

  /// Product display name.
  TextColumn get name => text()();

  /// Stock keeping unit / product code. Unique when present, scoped per shop.
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

  /// Current stock quantity. Must be >= 0. For products with variants, this
  /// mirrors the sum of variant stock and is derived by the repository — the
  /// variant rows are the source of truth.
  IntColumn get stockQuantity => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0)',
  )();

  /// The unit this product's stock is counted in.
  /// COUNT = plain units, ML / GRAM / KG = measured goods, NONE = no stock
  /// tracking (e.g. services, made-to-order).
  TextColumn get stockUnit => text().customConstraint(
    "NOT NULL DEFAULT 'COUNT' CHECK "
    "(stock_unit IN ('COUNT', 'ML', 'GRAM', 'KG', 'NONE'))",
  )();

  /// How low-stock is decided for this product:
  /// USE_DEFAULT = use the global threshold, CUSTOM = use
  /// [Products.lowStockThreshold], OFF = never flagged as low stock.
  TextColumn get lowStockMode => text().customConstraint(
    "NOT NULL DEFAULT 'USE_DEFAULT' CHECK "
    "(low_stock_mode IN ('USE_DEFAULT', 'CUSTOM', 'OFF'))",
  )();

  /// Per-product low-stock threshold; only meaningful when
  /// [Products.lowStockMode] is CUSTOM. Must be >= 0 when present.
  IntColumn get lowStockThreshold => integer().nullable().customConstraint(
    'CHECK (low_stock_threshold IS NULL OR low_stock_threshold >= 0)',
  )();

  /// Whether a member pricing tier exists for this product. Must be >= 0 when
  /// enabled (enforced at the repository layer).
  BoolColumn get membershipEnabled => boolean().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (membership_enabled IN (0, 1))',
  )();

  /// Member-tier selling price in paise; required when
  /// [Products.membershipEnabled] is true. Must be >= 0 when present.
  IntColumn get memberPricePaise => integer().nullable().customConstraint(
    'CHECK (member_price_paise IS NULL OR member_price_paise >= 0)',
  )();

  /// Local path (relative to the app documents directory) of the product
  /// image; NULL when no image is set. Stored locally so images keep working
  /// offline.
  TextColumn get imagePath => text().nullable()();

  /// Soft switch to hide a product from the POS without deleting it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
