/// ---------------------------------------------------------------------------
/// BrewFlow POS — Inventory Repository Contract
///
/// The single boundary between inventory state/UI and the local Drift
/// database. Failures are always safe-to-display [InventoryFailure] values;
/// database details are never exposed to callers.
/// ---------------------------------------------------------------------------
library;

import 'inventory_models.dart';

enum ProductStatusFilter { all, active, inactive }

/// Base for all inventory failures. Every subtype carries a user-safe message.
sealed class InventoryFailure implements Exception {
  const InventoryFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DuplicateCategoryNameFailure extends InventoryFailure {
  const DuplicateCategoryNameFailure()
    : super('A category with this name already exists.');
}

final class CategoryInUseFailure extends InventoryFailure {
  const CategoryInUseFailure()
    : super('This category is used by products and cannot be deleted.');
}

final class DuplicateSkuFailure extends InventoryFailure {
  const DuplicateSkuFailure()
    : super('A product with this SKU already exists.');
}

final class DuplicateVariantSkuFailure extends InventoryFailure {
  const DuplicateVariantSkuFailure()
    : super('A variant with this SKU already exists.');
}

final class VariantNameRequiredFailure extends InventoryFailure {
  const VariantNameRequiredFailure() : super('Every variant needs a name.');
}

final class MissingMemberPriceFailure extends InventoryFailure {
  const MissingMemberPriceFailure()
    : super('Set a member price when membership pricing is enabled.');
}

final class NegativeStockFailure extends InventoryFailure {
  const NegativeStockFailure() : super('Stock quantity cannot be negative.');
}

final class NegativePriceFailure extends InventoryFailure {
  const NegativePriceFailure() : super('Prices cannot be negative.');
}

final class UnexpectedInventoryFailure extends InventoryFailure {
  const UnexpectedInventoryFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first inventory persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class InventoryRepository {
  Future<List<Category>> categories();

  /// Every returned product carries its variants (empty list for products
  /// without variants) and a stock quantity that is the sum of variant stock
  /// when variants exist.
  Future<List<Product>> products({
    String? search,
    String? categoryId,
    ProductStatusFilter status,
  });

  /// Whether a product with this SKU exists (case-insensitive).
  Future<bool> skuExists(String sku, {String? exceptId});

  Future<Category> createCategory(String name, {String? shopId});

  Future<void> updateCategoryName(String id, String name);

  Future<void> setCategoryActive(String id, bool isActive);

  /// Deletes a category; throws [CategoryInUseFailure] when products
  /// reference it.
  Future<void> deleteCategory(String id);

  /// Creates a product atomically with its opening stock and any variants.
  ///
  /// When [stockQuantity] is positive, the product row and exactly one OPENING
  /// movement (quantity = [stockQuantity], stockBefore = 0, stockAfter =
  /// [stockQuantity]) are written in a single transaction, so the product can
  /// never exist without its opening audit movement. A zero [stockQuantity]
  /// creates the product without any movement; a negative value is rejected
  /// with [NegativeStockFailure] before anything is written.
  ///
  /// [variants] create the product's variant rows; every variant with a
  /// positive opening [ProductVariantInput.stockQuantity] gets its own OPENING
  /// movement (product-level stock is derived from the variants and not
  /// passed alongside them). Every variant must have a name and a valid
  /// member price when membership pricing is enabled.
  Future<Product> createProduct({
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    List<ProductVariantInput> variants = const [],
    String? shopId,
  });

  /// Updates a product's editable fields. [stockQuantity] (and variant stock)
  /// is never changed here — stock changes only through movements, so an
  /// edit can never silently alter inventory.
  ///
  /// [variants] is the full desired variant set: existing variants keep their
  /// stock and id, new inputs are created (with their opening OPENING
  /// movements), and variants absent from the list are soft-deactivated —
  /// never deleted, so history stays intact. Variant stock is never edited.
  Future<void> updateProduct({
    required String id,
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    List<ProductVariantInput> variants = const [],
    String? shopId,
  });

  Future<void> setProductActive(String id, bool isActive);

  /// Removes a product. When the product is unreferenced (no variants, sale
  /// lines, purchase lines or stock movements) it is hard-deleted and its sync
  /// tombstone is pushed so other devices learn it; when history exists,
  /// deletion degrades to a safe soft deactivation and
  /// [ProductDeleteResult.deactivated] is returned.
  Future<ProductDeleteResult> deleteProduct(String id);
}

/// Outcome of a [InventoryRepository.deleteProduct] call.
enum ProductDeleteResult { deleted, deactivated }
