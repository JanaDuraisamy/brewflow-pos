import 'dart:convert';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Offers Domain Models
///
/// Business-scoped promotions. Each offer belongs to exactly one shop/
/// business (Cafe or Food Truck) via `shopId`. Owner Phone creates/edits,
/// tablets receive only their business's offers via sync.
///
/// Design is extensible: new types add a case to [OfferType] and a config
/// shape. Existing type configs are JSON-serialized in [Offer.configJson].
/// ---------------------------------------------------------------------------

export 'offer_calculator.dart';

enum OfferType {
  percentage('PERCENTAGE'),
  quantityTier('QUANTITY_TIER'),
  combo('COMBO'),
  buyXGetY('BUY_X_GET_Y');

  const OfferType(this.wire);
  final String wire;

  static OfferType fromWire(String v) => OfferType.values.firstWhere(
    (e) => e.wire == v,
    orElse: () => throw ArgumentError('Unknown OfferType: $v'),
  );
}

/// Percentage: 10% off on applicable products
final class PercentageOfferConfig {
  const PercentageOfferConfig({
    required this.percent,
    this.productIds = const [],
  });
  final int percent; // 1..100
  final List<String> productIds; // empty = all

  Map<String, dynamic> toJson() => {
    'percent': percent,
    'productIds': productIds,
  };
  factory PercentageOfferConfig.fromJson(Map<String, dynamic> j) =>
      PercentageOfferConfig(
        percent: j['percent'] as int,
        productIds: (j['productIds'] as List?)?.cast<String>() ?? const [],
      );
}

/// Combo: fixed price for a set of products
final class ComboOfferConfig {
  const ComboOfferConfig({
    required this.productIds,
    required this.comboPricePaise,
  });
  final List<String> productIds;
  final int comboPricePaise;

  Map<String, dynamic> toJson() => {
    'productIds': productIds,
    'comboPricePaise': comboPricePaise,
  };
  factory ComboOfferConfig.fromJson(Map<String, dynamic> j) => ComboOfferConfig(
    productIds: (j['productIds'] as List).cast<String>(),
    comboPricePaise: j['comboPricePaise'] as int,
  );
}

/// Buy X Get Y Free: e.g. Buy 2 Get 1 Free on a product
final class BuyXGetYOfferConfig {
  const BuyXGetYOfferConfig({
    required this.productId,
    required this.buyQty,
    required this.getQty,
  });
  final String productId;
  final int buyQty;
  final int getQty;

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'buyQty': buyQty,
    'getQty': getQty,
  };
  factory BuyXGetYOfferConfig.fromJson(Map<String, dynamic> j) =>
      BuyXGetYOfferConfig(
        productId: j['productId'] as String,
        buyQty: j['buyQty'] as int,
        getQty: j['getQty'] as int,
      );
}

/// One "buy X quantity for ₹Y" step: [pricePaise] is the TOTAL price for
/// [quantity] units, not a per-unit price.
///
/// Example (1 Kulfi = ₹45, 2 = ₹85, 3 = ₹120) is the tier list
/// `[(1, 4500), (2, 8500), (3, 12000)]`.
final class QuantityTier {
  const QuantityTier({required this.quantity, required this.pricePaise});

  /// Units covered by this step (>= 1).
  final int quantity;

  /// Total price in integer paise for [quantity] units (>= 0).
  final int pricePaise;

  Map<String, dynamic> toJson() => {
    'quantity': quantity,
    'pricePaise': pricePaise,
  };

  factory QuantityTier.fromJson(Map<String, dynamic> j) => QuantityTier(
    quantity: j['quantity'] as int,
    pricePaise: j['pricePaise'] as int,
  );
}

/// Quantity tiers: buy [QuantityTier.quantity] units for a fixed
/// [QuantityTier.pricePaise].
///
/// This is NOT Buy X Get Y — nothing is free here, the whole group is simply
/// priced at a bundle rate. The best (largest) tier that fits the line
/// quantity is applied, and leftover units fall through to the next smaller
/// tier (or the shelf price) so a quantity above the top tier still prices
/// sensibly.
final class QuantityTierOfferConfig {
  const QuantityTierOfferConfig({
    required this.productIds,
    required this.tiers,
  });

  /// Products this offer applies to; empty means all products (same
  /// convention as [PercentageOfferConfig.productIds]).
  final List<String> productIds;

  /// Price steps. Semantics are order-independent, but the owner UI and
  /// [fromJson] normalize them to ascending quantity.
  final List<QuantityTier> tiers;

  Map<String, dynamic> toJson() => {
    'productIds': productIds,
    'tiers': tiers.map((t) => t.toJson()).toList(),
  };

  factory QuantityTierOfferConfig.fromJson(Map<String, dynamic> j) =>
      QuantityTierOfferConfig(
        productIds: (j['productIds'] as List?)?.cast<String>() ?? const [],
        tiers: ((j['tiers'] as List?) ?? const [])
            .map((e) => QuantityTier.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

final class Offer {
  const Offer({
    required this.id,
    required this.shopId,
    required this.name,
    required this.type,
    required this.configJson,
    required this.isActive,
    this.startAt,
    this.endAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String shopId;
  final String name;
  final OfferType type;
  final String configJson; // JSON string
  final bool isActive;
  final DateTime? startAt;
  final DateTime? endAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> configMap() {
    try {
      return jsonDecode(configJson) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  bool get isCurrentlyActive {
    if (!isActive) return false;
    final now = DateTime.now().toUtc();
    if (startAt != null && now.isBefore(startAt!)) return false;
    if (endAt != null && now.isAfter(endAt!)) return false;
    return true;
  }
}
