library;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movement Repository Contract
///
/// The single boundary between stock-movement state/UI and the local Drift
/// database. Failures are always safe-to-display [StockMovementFailure] values;
/// database details are never exposed to callers.
///
/// Scope (Steps 2–5): the adjustment/history foundation plus the OPENING
/// stock operation. The SALE movement writer belongs to a later Phase 9
/// billing integration step.
/// ---------------------------------------------------------------------------

import 'stock_movement_models.dart';

/// Base for all stock-movement failures. Every subtype carries a user-safe
/// message.
sealed class StockMovementFailure implements Exception {
  const StockMovementFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

final class ProductNotFoundFailure extends StockMovementFailure {
  const ProductNotFoundFailure() : super('Product not found.');
}

final class InvalidAdjustmentQuantityFailure extends StockMovementFailure {
  const InvalidAdjustmentQuantityFailure()
    : super('Enter a quantity greater than zero.');
}

final class AdjustmentInsufficientStockFailure extends StockMovementFailure {
  const AdjustmentInsufficientStockFailure()
    : super('Not enough stock for this reduction.');
}

final class InvalidOpeningQuantityFailure extends StockMovementFailure {
  const InvalidOpeningQuantityFailure()
    : super('Enter an opening quantity greater than zero.');
}

final class DuplicateOpeningFailure extends StockMovementFailure {
  const DuplicateOpeningFailure()
    : super('Opening stock has already been recorded for this product.');
}

final class UnexpectedStockMovementFailure extends StockMovementFailure {
  const UnexpectedStockMovementFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}

/// Local-first stock movement persistence contract. Implementations must be
/// offline-capable (Drift) and never require network access.
abstract interface class StockMovementRepository {
  /// All movements for one stock entity, newest first.
  ///
  /// With [variantId] null this returns the product's own movements only
  /// (movements against its variants are excluded — each stock entity's
  /// history is isolated). Pass a [variantId] to read that variant's
  /// history. Includes every movement type and is not filtered by the
  /// entity's active state — history must stay readable after deactivation.
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  });

  /// Records an inventory adjustment for a stock entity (a product, or one
  /// of its variants when [variantId] is given) and returns the written
  /// movement.
  ///
  /// [delta] is a signed change: positive adds stock (ADJUSTMENT_IN), negative
  /// removes stock (ADJUSTMENT_OUT). [delta] must not be zero. The operation
  /// runs inside a single transaction guarded at the database level so it can
  /// never drive stock below zero or race with other adjustments. Adjustments
  /// are allowed on inactive products (bookkeeping, not a sale).
  Future<StockMovement> adjustStock({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  });

  /// Records the initial stock baseline for a product and returns the written
  /// OPENING movement.
  ///
  /// [quantity] is the positive opening amount in units. Exactly one OPENING
  /// movement may exist per product (it mirrors product creation): a second
  /// call for the same product throws [DuplicateOpeningFailure] and changes
  /// nothing. The operation runs inside a single transaction so the stock
  /// update and the movement insert succeed or fail together. Opening is
  /// additive like every other movement (`stockAfter = stockBefore +
  /// [quantity]`); later changes use [adjustStock].
  Future<StockMovement> recordOpening({
    required String productId,
    required int quantity,
    String? note,
  });
}
