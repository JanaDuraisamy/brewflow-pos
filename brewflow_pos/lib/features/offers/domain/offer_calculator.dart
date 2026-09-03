import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Offer Calculator
///
/// Pure domain logic for calculating offer discounts. No side effects,
/// no persistence, no UI. Takes a cart line and the list of active offers
/// for the current business and returns the discount to apply.
///
/// Rules:
/// - Only active, within-date offers apply.
/// - Business isolation: offers are pre-filtered by shopId.
/// - Deterministic priority: Percentage > Combo > Buy X Get Y.
/// - No double application of the same offer to the same line.
/// - Never creates negative totals.
/// - Currency stays integer paise.
/// ---------------------------------------------------------------------------

/// Result of calculating an offer for a cart line.
final class OfferCalculation {
  const OfferCalculation({
    required this.offerId,
    required this.offerName,
    required this.offerType,
    required this.discountPaise,
    required this.appliedQuantity,
  });

  final String offerId;
  final String offerName;
  final OfferType offerType;
  final int discountPaise; // Total discount for this line
  final int appliedQuantity; // How many units the offer applied to
}

/// Calculates offer discounts for a single cart line.
///
/// Returns a list of calculations (one per applicable offer). The cart
/// controller will pick the best one based on priority rules.
List<OfferCalculation> calculateLineOffers({
  required CartLineContext line,
  required List<Offer> activeOffers,
}) {
  final results = <OfferCalculation>[];

  for (final offer in activeOffers) {
    if (!offer.isCurrentlyActive) continue;

    // Combo offers span multiple cart lines, so they are evaluated at cart
    // level by [calculateComboLineOffers], not here.
    if (offer.type == OfferType.combo) continue;

    final calc = _calculateForOffer(line: line, offer: offer);
    if (calc != null) {
      // Stamp the real offer identity: downstream (sale_items, receipts,
      // sync) relies on these being the actual offer, never empty.
      results.add(
        OfferCalculation(
          offerId: offer.id,
          offerName: offer.name,
          offerType: calc.offerType,
          discountPaise: calc.discountPaise,
          appliedQuantity: calc.appliedQuantity,
        ),
      );
    }
  }

  // Sort by priority: Percentage > Combo > Buy X Get Y
  results.sort(
    (a, b) =>
        _offerPriority(b.offerType).compareTo(_offerPriority(a.offerType)),
  );

  return results;
}

/// Selects the best offer calculation for a line based on priority.
///
/// Only one offer applies per line (highest priority). Returns null if no offer applies.
OfferCalculation? selectBestOffer(List<OfferCalculation> calculations) {
  if (calculations.isEmpty) return null;
  return calculations.first;
}

int _offerPriority(OfferType type) => switch (type) {
  OfferType.percentage => 3,
  OfferType.combo => 2,
  OfferType.buyXGetY => 1,
};

OfferCalculation? _calculateForOffer({
  required CartLineContext line,
  required Offer offer,
}) {
  final config = offer.configMap();

  return switch (offer.type) {
    OfferType.percentage => _calculatePercentage(line, config),
    // Combo is cart-level only — see [calculateComboLineOffers].
    OfferType.combo => null,
    OfferType.buyXGetY => _calculateBuyXGetY(line, config),
  };
}

OfferCalculation? _calculatePercentage(
  CartLineContext line,
  Map<String, dynamic> config,
) {
  final percent = config['percent'] as int?;
  final productIds =
      (config['productIds'] as List?)?.cast<String>() ?? const <String>[];

  if (percent == null || percent <= 0 || percent > 100) return null;

  // Empty productIds means applies to all products
  final appliesToAll = productIds.isEmpty;
  final appliesToProduct =
      appliesToAll ||
      productIds.contains(line.productId) ||
      (line.variantId != null && productIds.contains(line.variantId));

  if (!appliesToProduct) return null;

  final lineTotal = line.chargedLineTotalPaise;
  if (lineTotal == null) return null;

  final discount = (lineTotal * percent / 100).round();
  final clampedDiscount = discount.clamp(0, lineTotal);

  return OfferCalculation(
    offerId: '', // Filled by caller
    offerName: '', // Filled by caller
    offerType: OfferType.percentage,
    discountPaise: clampedDiscount,
    appliedQuantity: line.quantity,
  );
}

/// Cart-level combo evaluation.
///
/// A combo offer sells a fixed set of products for one fixed
/// [ComboOfferConfig.comboPricePaise]. It applies only when EVERY listed
/// product is present in the cart (matched by product id or variant id).
/// A product id listed N times requires N units across the matching lines.
///
/// The discount is `comboLinesTotal - comboPrice`, clamped to
/// `[0, comboLinesTotal]` so a combo priced at or above the shelf total
/// simply yields no discount instead of inflating the bill. It is split
/// across the combo lines proportionally in integer paise (floor each
/// share, largest remainder to the first combo line), so the per-line
/// shares always sum to exactly the combo discount.
///
/// Returns, per cart-line index, the combo calculations applying to that
/// line. Callers merge these with [calculateLineOffers] results and pick
/// via [selectBestOffer], preserving the documented priority
/// (Percentage > Combo > Buy X Get Y).
Map<int, List<OfferCalculation>> calculateComboLineOffers({
  required List<CartLineContext> lines,
  required List<Offer> comboOffers,
}) {
  final result = <int, List<OfferCalculation>>{};

  bool matches(CartLineContext line, String id) =>
      line.productId == id || (line.variantId != null && line.variantId == id);

  for (final offer in comboOffers) {
    if (offer.type != OfferType.combo || !offer.isCurrentlyActive) continue;
    final config = offer.configMap();
    final productIds =
        (config['productIds'] as List?)?.cast<String>() ?? const <String>[];
    final comboPricePaise = config['comboPricePaise'] as int?;
    if (productIds.isEmpty) continue;
    if (comboPricePaise == null || comboPricePaise < 0) continue;

    // Requirement: every listed product present in the required quantity.
    final required = <String, int>{};
    for (final id in productIds) {
      required[id] = (required[id] ?? 0) + 1;
    }
    final available = <String, int>{};
    for (final line in lines) {
      available[line.productId] =
          (available[line.productId] ?? 0) + line.quantity;
      if (line.variantId != null) {
        available[line.variantId!] =
            (available[line.variantId!] ?? 0) + line.quantity;
      }
    }
    var complete = true;
    for (final entry in required.entries) {
      if ((available[entry.key] ?? 0) < entry.value) {
        complete = false;
        break;
      }
    }
    if (!complete) continue;

    // Discount base: every line participating in the combo.
    final matched = <int>[];
    for (var i = 0; i < lines.length; i++) {
      if (productIds.any((id) => matches(lines[i], id))) {
        matched.add(i);
      }
    }
    if (matched.isEmpty) continue;

    final totals = <int>[];
    for (final i in matched) {
      final lineTotal = lines[i].chargedLineTotalPaise;
      if (lineTotal == null) {
        // Money overflow guard tripped — cannot price this combo safely.
        totals.clear();
        break;
      }
      totals.add(lineTotal);
    }
    if (totals.isEmpty) continue;

    final comboTotal = Money.sumPaise(totals);
    if (comboTotal == null) continue;
    final discount = (comboTotal - comboPricePaise).clamp(0, comboTotal);
    if (discount <= 0) continue;

    // Proportional integer-paise split; remainder to the first combo line.
    var assigned = 0;
    for (var k = 0; k < matched.length; k++) {
      final share = k == 0
          ? discount - _floorShares(discount, totals, comboTotal)
          : discount * totals[k] ~/ comboTotal;
      assigned += share;
      result
          .putIfAbsent(matched[k], () => [])
          .add(
            OfferCalculation(
              offerId: offer.id,
              offerName: offer.name,
              offerType: OfferType.combo,
              discountPaise: share,
              appliedQuantity: lines[matched[k]].quantity,
            ),
          );
    }
    assert(assigned == discount, 'Combo shares must sum to the combo discount');
  }
  return result;
}

/// Sum of the floored proportional shares for every line after the first.
int _floorShares(int discount, List<int> totals, int comboTotal) {
  var sum = 0;
  for (var k = 1; k < totals.length; k++) {
    sum += discount * totals[k] ~/ comboTotal;
  }
  return sum;
}

OfferCalculation? _calculateBuyXGetY(
  CartLineContext line,
  Map<String, dynamic> config,
) {
  final productId = config['productId'] as String?;
  final buyQty = config['buyQty'] as int?;
  final getQty = config['getQty'] as int?;

  if (productId == null || buyQty == null || getQty == null) return null;
  if (buyQty <= 0 || getQty <= 0) return null;

  // Check if this line matches the offer product
  final matches =
      line.productId == productId ||
      (line.variantId != null && line.variantId == productId);
  if (!matches) return null;

  // For every (buyQty + getQty) items, getQty are free
  final groupSize = buyQty + getQty;
  final fullGroups = line.quantity ~/ groupSize;
  final freeQuantity = fullGroups * getQty;

  if (freeQuantity <= 0) return null;

  final unitPrice = line.chargedUnitPricePaise;
  final discount = unitPrice * freeQuantity;

  return OfferCalculation(
    offerId: '',
    offerName: '',
    offerType: OfferType.buyXGetY,
    discountPaise: discount,
    appliedQuantity: freeQuantity,
  );
}

/// Context for a cart line needed for offer calculation.
final class CartLineContext {
  const CartLineContext({
    required this.productId,
    required this.variantId,
    required this.quantity,
    required this.unitPricePaise,
    required this.memberPricePaise,
    required this.memberPricing,
  });

  final String productId;
  final String? variantId;
  final int quantity;
  final int unitPricePaise;
  final int? memberPricePaise;
  final bool memberPricing;

  int get chargedUnitPricePaise =>
      memberPricing ? (memberPricePaise ?? unitPricePaise) : unitPricePaise;

  int? get chargedLineTotalPaise =>
      Money.multiplyPaise(chargedUnitPricePaise, quantity);
}
