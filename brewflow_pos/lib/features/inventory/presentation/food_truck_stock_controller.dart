/// ---------------------------------------------------------------------------
/// BrewFlow POS — Food Truck Stock Controller
///
/// Owns the per-business shelf overlay for products the Cafe shares with the
/// Food Truck. Every method takes an explicit [shopId] and never infers one:
/// the whole point of `shop_product_stock` is that the answer depends on which
/// business is asking.
///
/// The repository is injected (it is built from the app-scoped
/// `appDatabaseProvider`), so this controller never opens a second connection
/// and can be faked wholesale in tests.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/shop_product_stock_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads and writes the Food Truck shelf overlay for one sellable unit.
final class FoodTruckStockController {
  const FoodTruckStockController(this._repository);

  final ShopProductStockRepository _repository;

  /// The effective stock for one unit in [shopId].
  ///
  /// Throws [ShelfNotCarriedFailure] is never raised here — a product the truck
  /// does not carry reads back as [StockSource.notCarried] with quantity 0, so
  /// the UI can offer to put it on the shelf rather than reporting an error.
  Future<EffectiveStock> load({
    required String shopId,
    required String productId,
    String? variantId,
  }) {
    return _repository.effectiveStock(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
    );
  }

  /// Effective stock for a product and all of its variants in [shopId].
  Future<List<EffectiveStock>> loadVariants({
    required String shopId,
    required String productId,
  }) {
    return _repository.effectiveStockForVariants(
      shopId: shopId,
      productId: productId,
    );
  }

  /// Sets the shelf to an absolute [quantity], creating the overlay row when
  /// the product is not carried yet.
  Future<EffectiveStock> upsertShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int quantity,
  }) async {
    final stock = await _repository.upsertShelf(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
      quantity: quantity,
    );
    // The truck's overlay shelf is the single most confusing surface in the
    // app: an empty truck looks identical whether it was never stocked, was
    // cleared, or lost its shop identity. `source` distinguishes "the truck
    // carries this from its own row" (owned) from "shared in from the Cafe"
    // (overlay) from "not carried at all" (notCarried).
    AppTrace.event('stock.shelf', {
      'action': 'upsert',
      'shopRef': AppTrace.userRef(shopId),
      'productRef': AppTrace.userRef(productId),
      'variant': variantId != null,
      'quantity': quantity,
      'source': stock.source.name,
    });
    return stock;
  }

  /// Corrects an existing shelf by [delta]. Refuses to conjure a shelf: a
  /// product the truck does not carry throws [ShelfNotCarriedFailure].
  Future<EffectiveStock> adjustShelf({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
  }) async {
    final stock = await _repository.adjustShelf(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
      delta: delta,
    );
    AppTrace.event('stock.shelf', {
      'action': 'adjust',
      'shopRef': AppTrace.userRef(shopId),
      'productRef': AppTrace.userRef(productId),
      'delta': delta,
    });
    return stock;
  }

  /// Stops carrying one unit, removing its shelf row.
  Future<void> removeShelf({
    required String shopId,
    required String productId,
    String? variantId,
  }) async {
    await _repository.removeShelf(
      shopId: shopId,
      productId: productId,
      variantId: variantId,
    );
    AppTrace.event('stock.shelf', {
      'action': 'remove',
      'shopRef': AppTrace.userRef(shopId),
      'productRef': AppTrace.userRef(productId),
      'variant': variantId != null,
    });
  }

  /// Stops carrying a shared product entirely, at both levels.
  Future<void> removeShelvesForProduct({
    required String shopId,
    required String productId,
  }) async {
    await _repository.removeShelvesForProduct(
      shopId: shopId,
      productId: productId,
    );
    AppTrace.event('stock.shelf', {
      'action': 'remove_product',
      'shopRef': AppTrace.userRef(shopId),
      'productRef': AppTrace.userRef(productId),
    });
  }
}

/// Invalidates every inventory surface that caches shelf numbers.
///
/// A shelf change moves the Food Truck's own quantity, so the product list and
/// the dashboard's low-stock tile become stale. The Cafe's numbers are
/// untouched, which is exactly why this is a scoped invalidation rather than a
/// full reload.
void invalidateShelfReaders(WidgetRef ref) {
  ref.invalidate(productsProvider);
  ref.invalidate(dashboardControllerProvider);
}
