import 'inventory_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock alerts (notification center domain)
///
/// Pure derivation over the SAME stock rules as the dashboard and inventory
/// filters: [isLowStock], [effectiveLowStockThreshold] and
/// [effectiveVariantLowStockThreshold]. No second calculation engine.
///
/// One alert per stock entity per shop:
///   - a product without variants → one alert for the product,
///   - a product with variants → one alert per active variant.
///
/// [key] (`shop|product|variant`) is the dedup identity used by the UI and
/// the Android notifier so the same entity can never produce two rows.
/// ---------------------------------------------------------------------------

enum StockAlertKind { lowStock, outOfStock }

final class StockAlert {
  const StockAlert({
    required this.key,
    required this.kind,
    required this.shopId,
    required this.productId,
    this.variantId,
    required this.productName,
    this.variantName,
    required this.stock,
    this.threshold,
  });

  /// Dedup identity: shop + product + variant (`-` when product-level).
  final String key;
  final StockAlertKind kind;

  /// Owning/selling shop this alert belongs to. For a Food Truck projection
  /// this is the truck's shop (the shelf being sold from), not the catalogue
  /// owner's.
  final String? shopId;
  final String productId;
  final String? variantId;
  final String productName;
  final String? variantName;
  final int stock;
  final int? threshold;

  String get title => switch (kind) {
    StockAlertKind.outOfStock => 'OUT OF STOCK',
    StockAlertKind.lowStock => 'LOW STOCK',
  };

  String get displayName =>
      variantName == null ? productName : '$productName · $variantName';
}

/// Builds the alert list for [products] under [globalThreshold].
///
/// Rules mirror the dashboard exactly: active entities only, `StockUnit.none`
/// (untracked) never alerts, `LowStockMode.off` excluded, out-of-stock is
/// `stock <= 0` (not low), low is [isLowStock]. [shopOverride] attributes
/// every alert to one selling shop (the Food Truck projection case); null
/// keeps each product's own [Product.shopId].
List<StockAlert> buildStockAlerts(
  List<Product> products,
  int globalThreshold, {
  String? shopOverride,
}) {
  final byKey = <String, StockAlert>{};
  for (final product in products) {
    if (!product.isActive) continue;
    if (product.stockUnit == StockUnit.none) continue;
    final shopId = shopOverride ?? product.shopId;
    if (product.variants.isNotEmpty) {
      for (final variant in product.variants) {
        if (!variant.isActive) continue;
        final threshold = effectiveVariantLowStockThreshold(
          variant,
          product,
          globalThreshold,
        );
        final key = '${shopId ?? '-'}|${product.id}|${variant.id}';
        if (variant.stockQuantity <= 0) {
          // Out-of-stock beats threshold policy: a zero shelf is always an
          // alert unless the entity opted OFF (threshold null covers OFF).
          if (threshold == null) continue;
          byKey[key] = StockAlert(
            key: key,
            kind: StockAlertKind.outOfStock,
            shopId: shopId,
            productId: product.id,
            variantId: variant.id,
            productName: product.name,
            variantName: variant.name,
            stock: variant.stockQuantity,
            threshold: threshold,
          );
        } else if (isLowStock(
          stock: variant.stockQuantity,
          threshold: threshold,
        )) {
          byKey[key] = StockAlert(
            key: key,
            kind: StockAlertKind.lowStock,
            shopId: shopId,
            productId: product.id,
            variantId: variant.id,
            productName: product.name,
            variantName: variant.name,
            stock: variant.stockQuantity,
            threshold: threshold,
          );
        }
      }
    } else {
      final threshold = effectiveLowStockThreshold(product, globalThreshold);
      final key = '${shopId ?? '-'}|${product.id}|-';
      if (product.stockQuantity <= 0) {
        if (threshold == null) continue;
        byKey[key] = StockAlert(
          key: key,
          kind: StockAlertKind.outOfStock,
          shopId: shopId,
          productId: product.id,
          productName: product.name,
          stock: product.stockQuantity,
          threshold: threshold,
        );
      } else if (isLowStock(
        stock: product.stockQuantity,
        threshold: threshold,
      )) {
        byKey[key] = StockAlert(
          key: key,
          kind: StockAlertKind.lowStock,
          shopId: shopId,
          productId: product.id,
          productName: product.name,
          stock: product.stockQuantity,
          threshold: threshold,
        );
      }
    }
  }
  final alerts = byKey.values.toList()
    ..sort((a, b) {
      // Out-of-stock first, then low; alphabetical within a severity.
      final severity = a.kind.index.compareTo(b.kind.index);
      if (severity != 0) return -severity;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
  return alerts;
}
