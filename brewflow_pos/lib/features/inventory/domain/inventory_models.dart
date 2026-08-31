/// ---------------------------------------------------------------------------
/// BrewFlow POS — Inventory Domain Models
///
/// Immutable business models used by controllers and UI. Persistence details
/// (Drift rows) never leak past the repository boundary.
/// ---------------------------------------------------------------------------
library;

final class Category {
  const Category({
    required this.id,
    required this.name,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Category copyWith({String? name, bool? isActive, DateTime? updatedAt}) =>
      Category(
        id: id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// The unit a product's stock is counted in. Mirrors the CHECK-constrained
/// `stock_unit` column.
enum StockUnit {
  count('COUNT', 'Pieces'),
  ml('ML', 'ml'),
  gram('GRAM', 'g'),
  kg('KG', 'kg'),
  none('NONE', 'No tracking');

  const StockUnit(this.dbValue, this.label);

  /// Stable storage value for CHECK constraints and history.
  final String dbValue;

  /// Short display label, e.g. 'ml' or 'Pieces'.
  final String label;

  /// Parses a stored value; returns [StockUnit.count] for anything unexpected
  /// so the repository can fail safely instead of leaking a raw exception.
  static StockUnit fromDbValue(String value) => switch (value) {
    'COUNT' => StockUnit.count,
    'ML' => StockUnit.ml,
    'GRAM' => StockUnit.gram,
    'KG' => StockUnit.kg,
    'NONE' => StockUnit.none,
    _ => StockUnit.count,
  };
}

/// How low-stock is decided for a product (or variant). Mirrors the
/// CHECK-constrained `low_stock_mode` column.
enum LowStockMode {
  useDefault('USE_DEFAULT'),
  custom('CUSTOM'),
  off('OFF');

  const LowStockMode(this.dbValue);

  /// Stable storage value for CHECK constraints and history.
  final String dbValue;

  /// Parses a stored value; returns [LowStockMode.useDefault] for anything
  /// unexpected so the repository can fail safely instead of leaking a raw
  /// exception.
  static LowStockMode fromDbValue(String value) => switch (value) {
    'USE_DEFAULT' => LowStockMode.useDefault,
    'CUSTOM' => LowStockMode.custom,
    'OFF' => LowStockMode.off,
    _ => LowStockMode.useDefault,
  };
}

/// Effective low-stock threshold for [product] under the global
/// [globalThreshold]; `null` means the product is excluded from low-stock
/// alerts (its mode is OFF).
///
/// Chain: USE_DEFAULT → the global threshold, CUSTOM → the product's own
/// threshold, OFF → excluded.
int? effectiveLowStockThreshold(Product product, int globalThreshold) =>
    switch (product.lowStockMode) {
      LowStockMode.useDefault => globalThreshold,
      LowStockMode.custom => product.lowStockThreshold,
      LowStockMode.off => null,
    };

/// Effective low-stock threshold for [variant] of [product] under the global
/// [globalThreshold]; `null` means the variant is excluded from low-stock
/// alerts.
///
/// Chain: the variant's own mode first (CUSTOM → its threshold, OFF →
/// excluded), and USE_DEFAULT falls back to the parent product's policy and
/// then to the global threshold.
int? effectiveVariantLowStockThreshold(
  ProductVariant variant,
  Product product,
  int globalThreshold,
) => switch (variant.lowStockMode) {
  LowStockMode.useDefault => effectiveLowStockThreshold(
    product,
    globalThreshold,
  ),
  LowStockMode.custom => variant.lowStockThreshold,
  LowStockMode.off => null,
};

/// Whether [stock] counts as low against [threshold]. `null` threshold means
/// low-stock tracking is disabled for the item; a positive stock at or below
/// the threshold counts as low (mirroring the dashboard semantics), and an
/// empty stock is out-of-stock rather than low.
bool isLowStock({required int stock, required int? threshold}) =>
    threshold != null && stock > 0 && stock <= threshold;

final class Product {
  const Product({
    required this.id,
    required this.categoryId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    this.imagePath,
    this.stockUnit = StockUnit.count,
    this.lowStockMode = LowStockMode.useDefault,
    this.lowStockThreshold,
    this.membershipEnabled = false,
    this.memberPricePaise,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.variants = const [],
  });

  final String id;
  final String categoryId;
  final String name;
  final String? sku;

  /// Selling price stored as exact integer minor units (paise).
  final int sellingPricePaise;

  /// Cost price in paise; null when unknown.
  final int? costPricePaise;

  /// Current stock snapshot; never negative.
  ///
  /// For products with variants this is the sum of the variant stock (the
  /// variant rows are the source of truth); without variants it is the
  /// product's own recorded stock.
  final int stockQuantity;

  /// Local path (relative to the app documents directory) of the product
  /// image; null when no image is set.
  final String? imagePath;

  /// Unit the stock is counted in.
  final StockUnit stockUnit;

  /// Low-stock policy: USE_DEFAULT / CUSTOM / OFF.
  final LowStockMode lowStockMode;

  /// Per-product low-stock threshold; only meaningful when
  /// [lowStockMode] is [LowStockMode.custom].
  final int? lowStockThreshold;

  /// Whether a member pricing tier exists.
  final bool membershipEnabled;

  /// Member-tier selling price in paise; required when
  /// [membershipEnabled] is true.
  final int? memberPricePaise;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Sellable variants, in creation order. Empty for products without
  /// variants; when non-empty the variants own the stock.
  final List<ProductVariant> variants;

  /// Whether this product is sold through variants (it has at least one
  /// active or inactive variant).
  bool get hasVariants => variants.isNotEmpty;

  /// Sentinel distinguishing "not provided" from an explicit null so
  /// [copyWith] can clear nullable fields (e.g. [imagePath] on removal).
  static const _unset = Object();

  Product copyWith({
    String? categoryId,
    String? name,
    String? sku,
    int? sellingPricePaise,
    int? costPricePaise,
    int? stockQuantity,
    Object? imagePath = _unset,
    StockUnit? stockUnit,
    LowStockMode? lowStockMode,
    int? lowStockThreshold,
    bool? membershipEnabled,
    int? memberPricePaise,
    bool? isActive,
    DateTime? updatedAt,
    List<ProductVariant>? variants,
  }) => Product(
    id: id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    sku: sku ?? this.sku,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    costPricePaise: costPricePaise ?? this.costPricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    imagePath: identical(imagePath, _unset)
        ? this.imagePath
        : imagePath as String?,
    stockUnit: stockUnit ?? this.stockUnit,
    lowStockMode: lowStockMode ?? this.lowStockMode,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    membershipEnabled: membershipEnabled ?? this.membershipEnabled,
    memberPricePaise: memberPricePaise ?? this.memberPricePaise,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    variants: variants ?? this.variants,
  );
}

/// One sellable variant of a product — its own stock, SKU, prices, low-stock
/// policy, membership tier and soft-delete flag.
final class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    this.lowStockMode = LowStockMode.useDefault,
    this.lowStockThreshold,
    this.membershipEnabled = false,
    this.memberPricePaise,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String productId;
  final String name;

  /// Variant stock keeping unit / code; null when absent.
  final String? sku;

  /// Selling price in paise; never negative.
  final int sellingPricePaise;

  /// Cost price in paise; null when unknown.
  final int? costPricePaise;

  /// Current variant stock; never negative. The authoritative stock for a
  /// variant — its movements reference it directly.
  final int stockQuantity;

  /// Low-stock policy; USE_DEFAULT falls back to the parent product.
  final LowStockMode lowStockMode;

  /// Per-variant low-stock threshold; only meaningful when
  /// [lowStockMode] is [LowStockMode.custom].
  final int? lowStockThreshold;

  /// Whether a member pricing tier exists for this variant.
  final bool membershipEnabled;

  /// Member-tier selling price in paise; required when
  /// [membershipEnabled] is true.
  final int? memberPricePaise;

  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ProductVariant copyWith({
    String? name,
    String? sku,
    int? sellingPricePaise,
    int? costPricePaise,
    int? stockQuantity,
    LowStockMode? lowStockMode,
    int? lowStockThreshold,
    bool? membershipEnabled,
    int? memberPricePaise,
    bool? isActive,
    DateTime? updatedAt,
  }) => ProductVariant(
    id: id,
    productId: productId,
    name: name ?? this.name,
    sku: sku ?? this.sku,
    sellingPricePaise: sellingPricePaise ?? this.sellingPricePaise,
    costPricePaise: costPricePaise ?? this.costPricePaise,
    stockQuantity: stockQuantity ?? this.stockQuantity,
    lowStockMode: lowStockMode ?? this.lowStockMode,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    membershipEnabled: membershipEnabled ?? this.membershipEnabled,
    memberPricePaise: memberPricePaise ?? this.memberPricePaise,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// A variant to create with a product (or as a new variant of an existing
/// product). Stock is only applied at creation — edits never touch stock.
final class ProductVariantInput {
  const ProductVariantInput({
    this.id,
    required this.name,
    this.sku,
    required this.sellingPricePaise,
    this.costPricePaise,
    required this.stockQuantity,
    this.lowStockMode = LowStockMode.useDefault,
    this.lowStockThreshold,
    this.membershipEnabled = false,
    this.memberPricePaise,
    this.isActive = true,
  });

  /// Id of an existing variant this input updates (name, SKU, prices and
  /// policy are replaced; stock is never touched); null creates a new
  /// variant with [stockQuantity] as its opening stock.
  final String? id;

  final String name;
  final String? sku;
  final int sellingPricePaise;
  final int? costPricePaise;

  /// Opening stock for a newly created variant ([id] null); must be >= 0.
  /// Ignored when updating an existing variant.
  final int stockQuantity;
  final LowStockMode lowStockMode;
  final int? lowStockThreshold;
  final bool membershipEnabled;
  final int? memberPricePaise;
  final bool isActive;
}
