/// ---------------------------------------------------------------------------
/// Shop Product Stock — the per-business stock overlay for shared products
///
/// A product row is a MASTER definition owned by one business (the Cafe).
/// `products.visible_in_shops` makes that one definition sellable from another
/// business (the Food Truck) without duplicating the product, its variants, its
/// price or its category.
///
/// The definition is shared; the STOCK MUST NOT BE. "30 in the truck" must
/// never come out of the Cafe's 100. This layer is the rule that decides which
/// of the two shelves a business actually sells from.
///
/// It is deliberately a small, separate layer rather than an extension of the
/// existing inventory stock code. The Cafe path (`products.stock_quantity` /
/// `product_variants.stock_quantity`) is existing, working, audited behaviour
/// and must not be rewritten to accommodate a second business. What is new here
/// is only the *routing decision*, and it is small enough to read in one place.
///
/// The Drift implementation of [ShopProductStockRepository] lives in
/// `lib/features/inventory/data/drift_shop_product_stock_repository.dart`.
/// ---------------------------------------------------------------------------
library;

/// Where a business's effective stock for one sellable unit comes from.
enum StockSource {
  /// The business owns the product, so the authoritative number is the product
  /// row's own `stock_quantity` (or the variant's).
  owned,

  /// The product is shared in from another business, so the number is the
  /// overlay row in `shop_product_stock`.
  overlay,

  /// The product is shared in but this business has no overlay row for it.
  ///
  /// NOT SELLABLE. Not "free", not "unlimited", not "fall back to the owner's
  /// stock" — zero, and refused at the till. The distinction matters: falling
  /// back to the owner's number is exactly the bug this table was added to
  /// prevent, and representing it as `0` makes the refusal explicit rather
  /// than accidental.
  notCarried,
}

/// One sellable unit's effective stock in one business.
final class EffectiveStock {
  const EffectiveStock({
    required this.productId,
    required this.shopId,
    required this.variantId,
    required this.quantity,
    required this.source,
  });

  final String productId;

  /// The business this number belongs to. Carried on the value so a stock
  /// figure can never be read out of context and attributed to the wrong shop.
  final String shopId;

  /// Null for the product-level unit; set for a variant.
  final String? variantId;

  /// Never negative. Zero when [source] is [StockSource.notCarried].
  final int quantity;

  final StockSource source;

  /// Whether this business may sell the unit at all.
  ///
  /// A quantity of zero is a legitimate "in stock but none left" state and is
  /// still sellable in the sense of being carried; a missing shelf is not. The
  /// till distinguishes the two so it can refuse the second with a clear
  /// message instead of a generic out-of-stock one.
  bool get isSellable => source != StockSource.notCarried;

  @override
  String toString() =>
      'EffectiveStock($productId/$variantId shop=$shopId qty=$quantity '
      'source=${source.name})';
}

/// Base for all shop-stock failures. Every subtype carries a user-safe message.
sealed class ShopStockFailure implements Exception {
  const ShopStockFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The variant does not belong to the product it was paired with.
final class VariantProductMismatchFailure extends ShopStockFailure {
  const VariantProductMismatchFailure()
    : super('This variant does not belong to that product.');
}

/// The variant does not exist.
final class UnknownVariantFailure extends ShopStockFailure {
  const UnknownVariantFailure()
    : super('That product option no longer exists.');
}

/// The product does not exist.
final class UnknownProductFailure extends ShopStockFailure {
  const UnknownProductFailure() : super('That product no longer exists.');
}

/// An overlay quantity was negative.
final class NegativeShelfStockFailure extends ShopStockFailure {
  const NegativeShelfStockFailure()
    : super('Stock quantity cannot be negative.');
}

/// A deduction was larger than the business actually has on that shelf.
final class InsufficientShelfStockFailure extends ShopStockFailure {
  const InsufficientShelfStockFailure()
    : super('Not enough stock in this business.');
}

/// The business does not carry that unit, so there is no shelf to change.
final class ShelfNotCarriedFailure extends ShopStockFailure {
  const ShelfNotCarriedFailure()
    : super('This item is not stocked in this business.');
}

/// Something the caller should not have done — an owned product must never be
/// given an overlay row, because the owner's own stock is the shelf.
final class OwnedProductOverlayFailure extends ShopStockFailure {
  const OwnedProductOverlayFailure()
    : super('This business owns the product, so its own stock is used.');
}

final class UnexpectedShopStockFailure extends ShopStockFailure {
  const UnexpectedShopStockFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first contract for reading and writing per-business stock overlays.
///
/// Every method takes an explicit [shopId]. There is deliberately no "current
/// shop" default: the whole point of the table is that the answer depends on
/// which business is asking, and inferring it is how the Cafe's stock ends up
/// sold from the truck.
abstract interface class ShopProductStockRepository {
  /// The effective stock for one unit in one business, applying the ownership
  /// rules. Never negative, never inferred from another business.
  Future<EffectiveStock> effectiveStock({
    required String shopId,
    required String productId,
    String? variantId,
  });

  /// Effective stock for a product and all of its variants in one business.
  ///
  /// Returned in the product's own variant order (empty list when it has no
  /// variants) so a caller can zip them against its definitions without
  /// re-querying.
  Future<List<EffectiveStock>> effectiveStockForVariants({
    required String shopId,
    required String productId,
  });

  /// Sets a shared product's shelf in one business, creating the overlay row if
  /// it does not exist. Rejects a mismatched product/variant pair and a
  /// negative quantity, writing nothing in either case.
  Future<EffectiveStock> upsertShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int quantity,
  });

  /// Adds [delta] to an existing shelf, creating nothing.
  ///
  /// Throws [ShelfNotCarriedFailure] when the business has no row — an
  /// adjustment is a correction to a shelf that exists, not a way to conjure
  /// one.
  Future<EffectiveStock> adjustShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  });

  /// Takes [delta] off an existing shelf, refusing to go below zero.
  ///
  /// Throws [InsufficientShelfStockFailure] when the shelf is short and
  /// [ShelfNotCarriedFailure] when there is no shelf at all — the two are
  /// different mistakes and deserve different messages.
  Future<EffectiveStock> deductShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  });

  /// Puts [delta] back onto an existing shelf (a voided sale).
  Future<EffectiveStock> restoreShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  });

  /// Stops carrying one unit, removing its shelf row.
  Future<void> removeShelf({
    required String shopId,
    required String productId,
    String? variantId,
  });

  /// Stops carrying a shared product entirely, at both levels.
  Future<void> removeShelvesForProduct({
    required String shopId,
    required String productId,
  });
}
