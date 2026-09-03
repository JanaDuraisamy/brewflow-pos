import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Billing Domain Models
///
/// Pure value objects for the POS workflow. Money is always integer paise;
/// [Cart] is immutable and every mutation returns a new cart. Business rules
/// (stock caps, payment presence) are enforced by the cart controller and the
/// billing repository, never here.
/// ---------------------------------------------------------------------------

/// Quantity ceiling applied to cart lines of products whose stock unit is
/// NONE (made-to-order / untracked). Such items carry no real inventory, so
/// no artificial opening quantity is ever stored for them; this cap exists
/// purely so an in-memory [CartLine.maxQuantity] can never block a sale.
/// It never reaches the database and never appears as stock anywhere.
const int untrackedStockCap = 1000000;

/// Tracks an applied offer on a cart line.
final class AppliedOffer {
  const AppliedOffer({
    required this.offerId,
    required this.offerName,
    required this.offerType,
    required this.discountPaise,
    required this.appliedQuantity,
  });

  final String offerId;
  final String offerName;
  final OfferType offerType;
  final int discountPaise;
  final int appliedQuantity;
}

/// Accepted in-person payment methods. No gateway is involved; the enum
/// simply labels what the counter accepted. Not applicable to NOT_PAID
/// (credit) sales, which record no payment method.
enum PaymentMethod {
  cash,
  upi,
  bank;

  /// Database-storage value, kept stable for CHECK constraints and history.
  String get dbValue => switch (this) {
    PaymentMethod.cash => 'CASH',
    PaymentMethod.upi => 'UPI',
    PaymentMethod.bank => 'BANK',
  };

  static PaymentMethod? fromDbValue(String value) => switch (value) {
    'CASH' => PaymentMethod.cash,
    'UPI' => PaymentMethod.upi,
    'BANK' => PaymentMethod.bank,
    _ => null,
  };
}

/// Collection status chosen at the counter: [paid] money moved immediately
/// (CASH / UPI / BANK); [notPaid] records the sale as a credit bill whose
/// total becomes customer debt in the customer ledger.
enum PaymentStatus {
  paid,
  notPaid;

  /// Database-storage value, kept stable for CHECK constraints and history.
  String get dbValue => switch (this) {
    PaymentStatus.paid => 'PAID',
    PaymentStatus.notPaid => 'NOT_PAID',
  };

  static PaymentStatus? fromDbValue(String value) => switch (value) {
    'PAID' => PaymentStatus.paid,
    'NOT_PAID' => PaymentStatus.notPaid,
    _ => null,
  };

  /// User-facing label for the counter and history.
  String get label => switch (this) {
    PaymentStatus.paid => 'Paid',
    PaymentStatus.notPaid => 'Not paid',
  };
}

/// One product line in the cart.
///
/// [maxQuantity] is the stock observed when the line was added; quantity can
/// never exceed it and never drop below 1 ([Cart] mutations enforce this).
/// Name/SKU/price are snapshots of what the counter showed, so the charged
/// amount always matches what the customer saw.
///
/// A line identifies its stock entity through [keyId]: the variant id when
/// [variantId] is set, otherwise the product id. Variant lines snapshot the
/// variant name and the member price of the exact variant shown.
final class CartLine {
  const CartLine({
    required this.productId,
    required this.productName,
    required this.unitPricePaise,
    required this.quantity,
    required this.maxQuantity,
    this.sku,
    this.variantId,
    this.variantName,
    this.memberPricePaise,
    this.appliedOffer,
  }) : assert(quantity > 0, 'CartLine quantity must be positive'),
       assert(maxQuantity >= quantity, 'maxQuantity must cover quantity');

  final String productId;
  final String productName;
  final String? sku;

  /// Variant sold; null for plain product lines.
  final String? variantId;

  /// Variant name snapshot; null for plain product lines.
  final String? variantName;

  /// Member-tier price snapshot of the exact variant/product shown; null when
  /// the item has no membership tier. The charged price is [unitPricePaise]
  /// unless the cart has member pricing enabled and this is non-null.
  final int? memberPricePaise;

  final int unitPricePaise;
  final int quantity;
  final int maxQuantity;

  /// Applied offer on this line; null when no offer applies.
  final AppliedOffer? appliedOffer;

  /// Identity of the stock entity this line deducts from: the variant when
  /// the line sells a variant, otherwise the product.
  String get keyId => variantId ?? productId;

  /// Guarded equivalent of unitPricePaise * quantity; the controller and
  /// repository reject any line that would exceed [Money.maxPaise].
  int get lineTotalPaise => Money.multiplyPaise(unitPricePaise, quantity)!;

  /// The price this line is charged at when the cart has member pricing
  /// enabled: the member snapshot when the item has one, otherwise the
  /// regular price. Member snapshots always exist when the item's product or
  /// variant is membership-enabled, so a charged price never silently falls
  /// back for a member item.
  int chargedUnitPricePaise(bool memberPricing) =>
      memberPricing ? (memberPricePaise ?? unitPricePaise) : unitPricePaise;

  /// Guarded equivalent of [chargedUnitPricePaise] × quantity; null when the
  /// line would exceed [Money.maxPaise].
  int? chargedLineTotalPaise(bool memberPricing) =>
      Money.multiplyPaise(chargedUnitPricePaise(memberPricing), quantity);

  /// Line total after member pricing but before offer discount.
  int? chargedLineTotalBeforeOffer(bool memberPricing) =>
      chargedLineTotalPaise(memberPricing);

  /// Line total after member pricing AND offer discount.
  int? chargedLineTotalAfterOffer(bool memberPricing) {
    final beforeOffer = chargedLineTotalBeforeOffer(memberPricing);
    if (beforeOffer == null) return null;
    final discount = appliedOffer?.discountPaise ?? 0;
    return (beforeOffer - discount).clamp(0, beforeOffer);
  }

  CartLine copyWith({
    int? quantity,
    int? unitPricePaise,
    AppliedOffer? appliedOffer,
  }) => CartLine(
    productId: productId,
    productName: productName,
    sku: sku,
    variantId: variantId,
    variantName: variantName,
    memberPricePaise: memberPricePaise,
    unitPricePaise: unitPricePaise ?? this.unitPricePaise,
    quantity: quantity ?? this.quantity,
    maxQuantity: maxQuantity,
    appliedOffer: appliedOffer ?? this.appliedOffer,
  );

  CartLine clearOffer() => copyWith(appliedOffer: null);
}

/// Immutable cart: a list of unique stock-entity lines (variant or product)
/// plus the optional customer the sale is being made for (null = walk-in) and
/// the optional member-pricing switch.
final class Cart {
  const Cart._(
    this._lines, {
    this.selectedCustomerId,
    this.memberPricing = false,
  });

  static const Cart empty = Cart._([]);

  /// Builds a cart from an exact line snapshot (a resumed held bill). The
  /// caller is responsible for any confirmation the UI requires when the
  /// current cart is not empty.
  factory Cart.fromLines(
    List<CartLine> lines, {
    String? selectedCustomerId,
    bool memberPricing = false,
  }) => Cart._(
    List.unmodifiable(lines),
    selectedCustomerId: selectedCustomerId,
    memberPricing: memberPricing,
  );

  final List<CartLine> _lines;

  /// Customer linked to this sale; null for walk-in sales. Survives every
  /// line mutation and resets to null with [clear] (new sale).
  final String? selectedCustomerId;

  /// Whether member pricing applies to this cart. When enabled, every line
  /// with a [CartLine.memberPricePaise] snapshot is charged at the member
  /// price at checkout. Resets with [clear].
  final bool memberPricing;

  List<CartLine> get lines => List.unmodifiable(_lines);

  bool get isEmpty => _lines.isEmpty;

  bool get isNotEmpty => _lines.isNotEmpty;

  CartLine? lineFor(String keyId) {
    for (final line in _lines) {
      if (line.keyId == keyId) return line;
    }
    return null;
  }

  int quantityOf(String keyId) => lineFor(keyId)?.quantity ?? 0;

  /// Total pieces across all lines.
  int get itemCount => _lines.fold(0, (sum, line) => sum + line.quantity);

  /// Safe sum of line totals (base prices); null when the cart exceeds [Money.maxPaise].
  int? get subtotalPaise => Money.sumPaise(_lines.map((l) => l.lineTotalPaise));

  /// Total offer discount across all lines in paise.
  int get totalOfferDiscountPaise => _lines.fold(
    0,
    (sum, line) => sum + (line.appliedOffer?.discountPaise ?? 0),
  );

  /// Safe sum of the charged line totals after member pricing but BEFORE offers.
  int? get chargedTotalBeforeOffersPaise => Money.sumPaise(
    _lines.map((l) => l.chargedLineTotalPaise(memberPricing)!),
  );

  /// Safe sum of the charged line totals after member pricing AND offers.
  int? get chargedTotalAfterOffersPaise {
    final beforeOffers = chargedTotalBeforeOffersPaise;
    if (beforeOffers == null) return null;
    return (beforeOffers - totalOfferDiscountPaise).clamp(0, beforeOffers);
  }

  /// Final total the customer pays (after member pricing and offers).
  int? get totalPaise => chargedTotalAfterOffersPaise;

  /// Safe sum of the charged line totals ([CartLine.chargedLineTotalPaise]
  /// with [memberPricing]); null when the cart exceeds [Money.maxPaise].
  /// DEPRECATED: Use [chargedTotalBeforeOffersPaise] or [chargedTotalAfterOffersPaise].
  @Deprecated(
    'Use chargedTotalBeforeOffersPaise or chargedTotalAfterOffersPaise',
  )
  int? get chargedTotalPaise => chargedTotalBeforeOffersPaise;

  /// Lines with [CartLine.unitPricePaise] resolved to the charged price
  /// (member price where the cart has member pricing enabled and the line has
  /// a member snapshot). Checkout charges exactly these prices.
  List<CartLine> get resolvedLines => [
    for (final line in _lines)
      line.copyWith(unitPricePaise: line.chargedUnitPricePaise(memberPricing)),
  ];

  Cart withAdded(CartLine line) => Cart._(
    [..._lines, line],
    selectedCustomerId: selectedCustomerId,
    memberPricing: memberPricing,
  );

  Cart withLineQuantity(String keyId, int quantity) {
    final index = _lines.indexWhere((l) => l.keyId == keyId);
    if (index == -1) return this;
    final copy = [..._lines];
    copy[index] = copy[index].copyWith(quantity: quantity);
    return Cart._(
      copy,
      selectedCustomerId: selectedCustomerId,
      memberPricing: memberPricing,
    );
  }

  Cart without(String keyId) => Cart._(
    _lines.where((l) => l.keyId != keyId).toList(),
    selectedCustomerId: selectedCustomerId,
    memberPricing: memberPricing,
  );

  /// Links the sale to [customerId]; null switches back to a walk-in sale.
  Cart withCustomer(String? customerId) => Cart._(
    _lines,
    selectedCustomerId: customerId,
    memberPricing: memberPricing,
  );

  /// Enables or disables member pricing for this cart.
  Cart withMemberPricing(bool enabled) => Cart._(
    _lines,
    selectedCustomerId: selectedCustomerId,
    memberPricing: enabled,
  );

  Cart clear() => Cart.empty;
}

/// A bill parked at the counter (Hold Bill).
///
/// A pure in-memory snapshot of the cart plus the payment choices made when
/// the counter held it. HOLDING IS NOT A SALE: nothing is written to the
/// database — no Sale row, no stock movement, no stock deduction, no receipt
/// number consumed and no debt recorded. Held bills are transient POS state:
/// they start empty on app restart and are cleared on logout, so one
/// cashier's held bills never leak into the next session. Holding never
/// reserves stock; checkout after resume re-validates against the live
/// repository and fails safely when stock has changed.
final class HeldBill {
  const HeldBill({
    required this.id,
    required this.lines,
    required this.memberPricing,
    required this.paymentStatus,
    required this.heldAt,
    this.selectedCustomerId,
    this.paymentMethod,
  });

  /// Session-unique hold identifier (e.g. `hold-1`); rendered as `#1` in the
  /// held-bills sheet.
  final String id;

  /// Exact cart lines at hold time (product/variant snapshots, quantities).
  final List<CartLine> lines;

  /// Customer linked when the bill was held; null = walk-in.
  final String? selectedCustomerId;

  /// Member-pricing switch state at hold time.
  final bool memberPricing;

  /// Collection choice at hold time: paid or not paid (credit).
  final PaymentStatus paymentStatus;

  /// Payment method chosen at hold time; null for NOT_PAID holds.
  final PaymentMethod? paymentMethod;

  /// Exact UTC instant the bill was held.
  final DateTime heldAt;

  /// Total pieces across all lines.
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  /// Charged total with the bill's member-pricing state; null above the safe
  /// ceiling (unreachable in practice — checkout would have rejected it).
  int? get totalPaise {
    final beforeOffers = Money.sumPaise(
      lines.map((l) => l.chargedLineTotalPaise(memberPricing)!),
    );
    if (beforeOffers == null) return null;
    final discount = lines.fold(
      0,
      (sum, line) => sum + (line.appliedOffer?.discountPaise ?? 0),
    );
    return (beforeOffers - discount).clamp(0, beforeOffers);
  }

  /// Restores the cart to exactly what the counter had when the bill was held.
  Cart toCart() => Cart.fromLines(
    lines,
    selectedCustomerId: selectedCustomerId,
    memberPricing: memberPricing,
  );
}

/// A completed sale header.
final class Sale {
  const Sale({
    required this.id,
    required this.receiptNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    required this.offerDiscountPaise,
    required this.paymentStatus,
    required this.createdAt,
    required this.updatedAt,
    this.paymentMethod,
    this.customerId,
    this.voided = false,
    this.voidedAt,
  });

  final String id;
  final String receiptNumber;
  final int subtotalPaise;
  final int totalPaise;
  final int offerDiscountPaise;

  /// Collection status chosen at the counter: paid or not paid (credit).
  final PaymentStatus paymentStatus;

  /// Method the counter accepted; null for NOT_PAID (credit) sales.
  final PaymentMethod? paymentMethod;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Owning customer for customer-linked sales; null for walk-ins.
  final String? customerId;

  /// Whether this sale has been voided. Voided sales are never hard-deleted;
  /// stock and payments are reversed in the same transaction.
  final bool voided;

  /// UTC instant the sale was voided; null when the sale is active.
  final DateTime? voidedAt;
}

/// One persisted line of a completed sale (snapshot values).
final class SaleItem {
  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.unitPricePaise,
    required this.quantity,
    required this.lineTotalPaise,
    required this.offerDiscountPaise,
    this.sku,
    this.variantId,
    this.variantName,
    this.appliedOfferId,
    this.appliedOfferName,
    this.appliedOfferType,
  });

  final String id;
  final String saleId;
  final String productId;
  final String productName;
  final String? sku;

  /// Variant sold; null for plain product lines. Snapshot reference only —
  /// variants are soft-deactivated, never deleted.
  final String? variantId;

  /// Variant name at the time of the sale (snapshot); null for plain lines.
  final String? variantName;

  final int unitPricePaise;
  final int quantity;
  final int lineTotalPaise;
  final int offerDiscountPaise;

  /// Offer applied to this line; null if no offer.
  final String? appliedOfferId;
  final String? appliedOfferName;
  final OfferType? appliedOfferType;
}

/// Result of a successfully completed checkout.
final class CompletedSale {
  const CompletedSale({required this.sale, required this.items});

  final Sale sale;
  final List<SaleItem> items;
}
