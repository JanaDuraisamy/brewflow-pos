/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchases Repository Contract
///
/// The single boundary between purchase/receiving state and the local Drift
/// database. Failures are always safe-to-display [PurchasesFailure] values;
/// database details are never exposed to callers.
///
/// Scope: purchase (receiving) records only — the atomic receiving
/// transaction, snapshot line items and history reads.
/// ---------------------------------------------------------------------------
library;

import 'purchases_models.dart';

/// Base for all purchases failures. Every subtype carries a user-safe message.
sealed class PurchasesFailure implements Exception {
  const PurchasesFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Attempted to receive a purchase with no lines.
final class EmptyPurchaseFailure extends PurchasesFailure {
  const EmptyPurchaseFailure([
    super.message = 'Add at least one item to receive.',
  ]);
}

/// A line quantity outside the allowed range (below 1).
final class InvalidPurchaseQuantityFailure extends PurchasesFailure {
  const InvalidPurchaseQuantityFailure([
    super.message = 'Quantity must be at least 1.',
  ]);
}

/// A line unit cost below zero (costs are never negative).
final class InvalidPurchaseCostFailure extends PurchasesFailure {
  const InvalidPurchaseCostFailure([
    super.message = 'Unit cost cannot be negative.',
  ]);
}

/// The same product appears on more than one line.
final class DuplicateProductLineFailure extends PurchasesFailure {
  const DuplicateProductLineFailure([
    super.message = 'Each product may appear only once in a purchase.',
  ]);
}

/// A line references a product that does not exist.
final class UnknownProductFailure extends PurchasesFailure {
  const UnknownProductFailure(
    this.productId, [
    super.message = 'A product in this purchase was not found.',
  ]);

  final String productId;
}

/// The product is deactivated and cannot receive stock.
final class InactiveProductFailure extends PurchasesFailure {
  InactiveProductFailure(this.productName, [String? message])
    : super(message ?? '$productName is deactivated and cannot receive stock.');

  final String productName;
}

/// The purchase referenced a supplier that no longer exists.
final class UnknownSupplierFailure extends PurchasesFailure {
  const UnknownSupplierFailure([super.message = 'Supplier not found.']);
}

/// The selected supplier is deactivated and cannot receive stock.
final class InactiveSupplierFailure extends PurchasesFailure {
  const InactiveSupplierFailure([
    super.message =
        'This supplier is deactivated. Re-activate them to receive stock.',
  ]);
}

final class UnexpectedPurchasesFailure extends PurchasesFailure {
  const UnexpectedPurchasesFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first purchase record persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class PurchaseRepository {
  /// Atomically receives a purchase: supplier/product validation, stock
  /// increases, the purchase header, snapshot line items and PURCHASE stock
  /// movements are committed in one transaction.
  ///
  /// [supplierId] optionally links the purchase to a supplier profile
  /// (walk-in purchases pass null); a non-null supplier is re-validated
  /// inside the transaction (must exist and be active).
  ///
  /// Each [PurchaseLine] must reference an existing, active product with a
  /// positive quantity and a non-negative unit cost; the same product may
  /// appear only once. Product names and SKUs are snapshotted at receiving
  /// time, and the caller-supplied unit cost is stored verbatim — the
  /// product's own cost price is never modified.
  ///
  /// Throws [PurchasesFailure] for every recoverable condition
  /// ([EmptyPurchaseFailure], [InvalidPurchaseQuantityFailure],
  /// [InvalidPurchaseCostFailure], [DuplicateProductLineFailure],
  /// [UnknownProductFailure], [InactiveProductFailure],
  /// [UnknownSupplierFailure], [InactiveSupplierFailure],
  /// [UnexpectedPurchasesFailure]). On failure the database is left
  /// untouched (full rollback, including the purchase number).
  Future<Purchase> receivePurchase({
    required List<PurchaseLine> lines,
    String? supplierId,
    String? notes,
  });

  /// All purchases, newest first.
  Future<List<Purchase>> purchases();

  Future<Purchase?> purchaseById(String id);

  /// Snapshot lines of one purchase, in insertion order.
  Future<List<PurchaseItem>> purchaseItems(String purchaseId);

  /// Voids a received purchase: reverses the stock each line added, then
  /// removes the purchase header, its line items and its purchase stock
  /// movements in a single transaction. Throws [PurchasesFailure] when the
  /// purchase is missing.
  Future<void> voidPurchase(String id);
}
