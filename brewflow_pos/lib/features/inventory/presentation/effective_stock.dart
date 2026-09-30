import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/shop_product_stock_repository.dart';

/// ---------------------------------------------------------------------------
/// Effective stock projection
///
/// A product row is a MASTER definition owned by one business (the Cafe). The
/// Food Truck reuses that definition — same name, price, variants, category —
/// but must sell from its own shelf. This file is the single place that turns
/// "a list of products the Food Truck can see" into "the list with the Food
/// Truck's own numbers on it".
///
/// It is a projection, not a second inventory. Nothing here writes; it reads
/// [ShopProductStockRepository] and rewrites the in-memory [Product] values the
/// rest of the app already knows how to render, filter and sell. That is
/// deliberate: every existing screen, cart cap, low-stock rule and colour
/// already reads `product.stockQuantity`, so replacing the number at the source
/// gets all of them right without a parallel code path that could drift.
///
/// The rule, once:
///
///  * A product the active business OWNS keeps its own `stock_quantity`.
///    Nothing here changes the Cafe's numbers, ever.
///  * A product owned by ANOTHER business takes its number from that
///    business's `shop_product_stock` row.
///  * No overlay row means NOT SELLABLE, so the number is 0 — never the
///    owner's. Falling back to the owner's number is the exact bug this
///    projection exists to prevent, and rendering it as 0 makes the refusal
///    visible instead of accidental.
/// ---------------------------------------------------------------------------

/// Rewrites [products] so each carries the stock of [shopId].
///
/// Products whose `shopId` equals [shopId] are returned untouched, which is
/// what keeps the Cafe path byte-for-byte identical. A null [shopId] (no
/// persisted Food Truck, or the combined read-only view) returns [products]
/// unchanged: with no business to attribute the numbers to, the honest answer
/// is to leave the master's own figures rather than invent an overlay.
Future<List<Product>> applyEffectiveStock({
  required List<Product> products,
  required ShopProductStockRepository repository,
  required String? shopId,
}) async {
  if (shopId == null || products.isEmpty) return products;

  final projected = <Product>[];
  var changed = false;
  for (final product in products) {
    // The business owns it: its own row IS the shelf. This is the Cafe case and
    // it is a pass-through, not a copy.
    if (product.shopId == shopId) {
      projected.add(product);
      continue;
    }
    final next = await _projectProduct(
      product: product,
      repository: repository,
      shopId: shopId,
    );
    if (!identical(next, product)) changed = true;
    projected.add(next);
  }
  return changed ? projected : products;
}

/// Projects one product and its variants onto [shopId]'s shelf.
///
/// Fails CLOSED. If the overlay cannot be read, the product is shown as zero
/// rather than with the owner's quantity: a read failure is not evidence that
/// the shelf holds stock, and showing the owner's number here would put the
/// Cafe's inventory on the truck's screen — the exact confusion this projection
/// exists to remove. Zero is recoverable (the shelf editor fixes it) and always
/// safe, because the sale path independently refuses a missing shelf.
Future<Product> _projectProduct({
  required Product product,
  required ShopProductStockRepository repository,
  required String shopId,
}) async {
  try {
    if (product.variants.isEmpty) {
      final effective = await repository.effectiveStock(
        shopId: shopId,
        productId: product.id,
      );
      if (effective.quantity == product.stockQuantity) return product;
      return product.copyWith(stockQuantity: effective.quantity);
    }

    // Variants own the stock, so each sellable unit is projected on its own
    // row. A product-level number is then the sum, matching how the Cafe
    // derives it from its variant rows.
    var total = 0;
    var anyChanged = false;
    final variants = <ProductVariant>[];
    for (final variant in product.variants) {
      final effective = await repository.effectiveStock(
        shopId: shopId,
        productId: product.id,
        variantId: variant.id,
      );
      total += effective.quantity;
      if (effective.quantity == variant.stockQuantity) {
        variants.add(variant);
      } else {
        anyChanged = true;
        variants.add(variant.copyWith(stockQuantity: effective.quantity));
      }
    }
    if (!anyChanged && total == product.stockQuantity) return product;
    return product.copyWith(stockQuantity: total, variants: variants);
  } catch (error, stackTrace) {
    AppLog.warning(
      'Effective stock projection failed; showing the product as unavailable',
      tag: 'Inventory',
      error: error,
      stackTrace: stackTrace,
    );
    return product.copyWith(stockQuantity: 0);
  }
}
