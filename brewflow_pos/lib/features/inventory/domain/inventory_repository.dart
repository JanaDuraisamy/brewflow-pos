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

/// A mutation named a row the active business does not own.
///
/// The dangerous case this exists for is a Cafe master product that the Cafe
/// has shared into the Food Truck: it is visible in the truck, so an ID-only
/// deactivate or delete would happily remove the Cafe's catalogue entry from
/// under the Cafe. Scope is passed explicitly and the row must belong to one of
/// those shops, so a truck action can only ever touch the truck's own rows.
final class ForeignShopRowFailure extends InventoryFailure {
  const ForeignShopRowFailure()
    : super(
        'This item belongs to another business and cannot be changed here.',
      );
}

final class UnexpectedInventoryFailure extends InventoryFailure {
  const UnexpectedInventoryFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first inventory persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class InventoryRepository {
  Future<List<Category>> categories({List<String>? shopIds});

  /// Categories reachable from the business [shopId] may sell: its own, plus the
  /// catalog owner's that hold a product shared into it.
  ///
  /// A category the business has no visible product for is not returned, so the
  /// filter list never reveals a catalogue the business cannot use.
  Future<List<Category>> categoriesForBusiness({
    required String shopId,
    required String catalogOwnerShopId,
  });

  /// Every returned product carries its variants (empty list for products
  /// without variants) and a stock quantity that is the sum of variant stock
  /// when variants exist.
  Future<List<Product>> products({
    String? search,
    String? categoryId,
    ProductStatusFilter status,
    List<String>? shopIds,
  });

  /// Returns products for the given [shopId] with optional shared‑product
  /// visibility from the catalog owner ([catalogOwnerShopId]).
  ///
  /// When [shopId] equals [catalogOwnerShopId] (Cafe mode) the method
  /// behaves like [products] — only the shop's own active products are
  /// returned. When they differ (Food Truck mode) the result includes the
  /// shop's own products plus any products the catalog owner has marked
  /// [visibleInShops] = true.
  ///
  /// [categoryId] filters the same way it does in [products], applied AFTER
  /// the visibility scope so a category can never widen which products a
  /// business is allowed to see.
  Future<List<Product>> productsForBusiness({
    required String shopId,
    required String catalogOwnerShopId,
    String? search,
    String? categoryId,
    ProductStatusFilter status = ProductStatusFilter.all,
  });

  /// Whether a product with this SKU exists (case-insensitive).
  Future<bool> skuExists(String sku, {String? exceptId});

  Future<Category> createCategory(String name, {String? shopId});

  /// [shopIds] scopes the mutation to rows the active business owns; a row
  /// belonging to another business throws [ForeignShopRowFailure]. Null keeps
  /// the historical unscoped behaviour for callers with no business context.
  Future<void> updateCategoryName(
    String id,
    String name, {
    List<String>? shopIds,
  });

  /// [shopIds] scopes the mutation as in [updateCategoryName].
  Future<void> setCategoryActive(
    String id,
    bool isActive, {
    List<String>? shopIds,
  });

  /// Deletes a category; throws [CategoryInUseFailure] when products
  /// reference it, and [ForeignShopRowFailure] for a category owned by another
  /// business when [shopIds] is given.
  Future<void> deleteCategory(String id, {List<String>? shopIds});

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
    bool visibleInShops = false,
  });

  /// Updates a product's editable fields. [stockQuantity] (and variant stock)
  /// is never changed here — stock changes only through movements, so an
  /// edit can never silently alter inventory.
  ///
  /// [variants] is the full desired variant set: existing variants keep their
  /// stock and id, new inputs are created (with their opening OPENING
  /// movements), and variants absent from the list are soft-deactivated —
  /// never deleted, so history stays intact. Variant stock is never edited.
  ///
  /// [shopIds] scopes the mutation to rows the active business owns and throws
  /// [ForeignShopRowFailure] otherwise. Without it an edit reaches far more than
  /// one row — the product's own fields, its variant set and their opening
  /// movements — so an ID-only call could rewrite a Cafe master the truck was
  /// merely shared.
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
    List<String>? shopIds,
    bool visibleInShops = false,
  });

  /// Activates or deactivates a product.
  ///
  /// [shopIds] scopes the mutation to rows the active business owns and throws
  /// [ForeignShopRowFailure] otherwise. This is what stops a Food Truck user
  /// deactivating a Cafe master product the Cafe merely shared.
  Future<void> setProductActive(
    String id,
    bool isActive, {
    List<String>? shopIds,
  });

  /// Really removes a product — the catalogue row is deleted, never hidden.
  ///
  /// History is deliberately not a reason to refuse. Schema v31 dropped the
  /// historical foreign keys, so a product with sale lines, purchase lines and
  /// stock movements is still deletable: those rows keep their own
  /// name/SKU/price snapshots and simply retain the product id as a plain
  /// column. Variants and this business's stock overlay are product
  /// *definition*, not history, and are removed with it through their CASCADE
  /// keys — no orphan variant or active stock is ever left behind.
  ///
  /// The sync tombstone is pushed so other devices learn the deletion and a
  /// stale row cannot resurrect the product.
  ///
  /// [shopIds] scopes the mutation as in [setProductActive], so a shared Cafe
  /// product can never be deleted from the Food Truck.
  Future<ProductDeleteResult> deleteProduct(String id, {List<String>? shopIds});
}

/// Outcome of a [InventoryRepository.deleteProduct] call.
///
/// Always [ProductDeleteResult.deleted]: there is no longer a deactivation
/// fallback. Kept as an explicit result so callers read as intent rather than
/// having to assume, and so the UI can drop the "deactivated" branch.
enum ProductDeleteResult { deleted }
