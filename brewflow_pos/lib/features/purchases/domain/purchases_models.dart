/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchases Domain Models
///
/// Immutable business models for the supplier and purchase/receiving module.
/// Persistence details (Drift rows) never leak past the repository boundary.
///
/// Money is integer paise (never doubles); snapshots follow the sale-item
/// convention so historical purchase records are immune to later product
/// edits.
/// ---------------------------------------------------------------------------
library;

final class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.address,
    this.notes,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Optional phone number; unique when present (case-insensitive).
  final String? phone;

  /// Optional email address; not unique.
  final String? email;

  /// Optional billing/delivery address.
  final String? address;

  /// Optional free-form note.
  final String? notes;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  static const _unset = Object();

  Supplier copyWith({
    String? name,
    Object? phone = _unset,
    Object? email = _unset,
    Object? address = _unset,
    Object? notes = _unset,
    bool? isActive,
    DateTime? updatedAt,
  }) => Supplier(
    id: id,
    name: name ?? this.name,
    phone: identical(phone, _unset) ? this.phone : phone as String?,
    email: identical(email, _unset) ? this.email : email as String?,
    address: identical(address, _unset) ? this.address : address as String?,
    notes: identical(notes, _unset) ? this.notes : notes as String?,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// One completed purchase (receiving) header.
final class Purchase {
  const Purchase({
    required this.id,
    this.supplierId,
    required this.purchaseNumber,
    required this.subtotalPaise,
    required this.totalPaise,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Owning supplier for supplier-linked purchases; null for walk-ins.
  final String? supplierId;

  /// Human-readable reference, e.g. 'PUR-000012'.
  final String purchaseNumber;

  /// Sum of line totals in paise, before any adjustments.
  final int subtotalPaise;

  /// Amount recorded in paise (equals the subtotal for now).
  final int totalPaise;

  /// Optional free-form note.
  final String? notes;

  /// UTC receiving timestamp; doubles as the purchase date.
  final DateTime createdAt;

  /// UTC last-change timestamp.
  final DateTime updatedAt;
}

/// One line item of a completed purchase.
final class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.purchaseId,
    required this.productId,
    required this.productName,
    this.sku,
    required this.unitCostPaise,
    required this.quantity,
    required this.lineTotalPaise,
    this.variantId,
    this.variantName,
  });

  final String id;
  final String purchaseId;
  final String productId;

  /// Product name at receiving time (snapshot).
  final String productName;

  /// Product SKU at receiving time (snapshot); null when absent.
  final String? sku;

  /// Variant received; null for plain product lines. Snapshot reference only
  /// — variants are soft-deactivated, never deleted.
  final String? variantId;

  /// Variant name at receiving time (snapshot); null for plain lines.
  final String? variantName;

  /// Unit cost price in paise at receiving time.
  final int unitCostPaise;

  /// Quantity received; always > 0.
  final int quantity;

  /// unitCostPaise * quantity in paise.
  final int lineTotalPaise;
}

/// One input line of a purchase being received.
///
/// The product name, SKU and cost are captured by the repository at receiving
/// time from the database and the caller-supplied [unitCostPaise]; the
/// resulting purchase history stays immutable even if the product is later
/// edited.
final class PurchaseLine {
  const PurchaseLine({
    required this.productId,
    required this.quantity,
    required this.unitCostPaise,
    this.variantId,
  });

  /// Product to receive stock into.
  final String productId;

  /// Variant to receive stock into; null when receiving into the product
  /// itself.
  final String? variantId;

  /// Quantity received; must be > 0.
  final int quantity;

  /// Unit cost price in paise at receiving time; must be >= 0. This value is
  /// snapshotted into the purchase item; the product's own cost price is
  /// never modified or re-read.
  final int unitCostPaise;
}
