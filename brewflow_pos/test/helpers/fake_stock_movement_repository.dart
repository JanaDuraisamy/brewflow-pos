library;

import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';

/// In-memory [StockMovementRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI: the
/// signed delta math, derived before/after values, insufficient-stock and
/// missing-product rejection, zero-delta rejection, adjustment-allowed-on
/// inactive products, newest-first ordering, and product/variant stock
/// isolation. Seed product stock through [productStock] (and variant stock
/// through [variantStock]) before calling [adjustStock].
final class FakeStockMovementRepository implements StockMovementRepository {
  /// Current stock per product id, mirroring `products.stock_quantity`.
  final Map<String, int> productStock = {};

  /// Current stock per variant id, mirroring `product_variants.stock_quantity`.
  final Map<String, int> variantStock = {};

  /// Movements recorded, filtered per product on read.
  final List<StockMovement> storedMovements = [];

  /// When set, every load throws this error instead of running.
  Object? loadError;

  /// When set, [adjustStock] throws this error before touching state.
  Object? adjustError;

  /// When set, [recordOpening] throws this error before touching state.
  Object? openingError;

  int _sequence = 0;

  @override
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  }) async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    final matches =
        storedMovements
            .where((m) => m.productId == productId && m.variantId == variantId)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return matches;
  }

  @override
  Future<StockMovement> adjustStock({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    final error = adjustError;
    if (error != null) {
      throw error;
    }
    if (delta == 0) {
      throw const InvalidAdjustmentQuantityFailure();
    }
    final current = variantId == null
        ? productStock[productId]
        : variantStock[variantId];
    if (current == null) {
      throw const ProductNotFoundFailure();
    }
    final stockAfter = current + delta;
    if (stockAfter < 0) {
      throw const AdjustmentInsufficientStockFailure();
    }

    final trimmedNote = note?.trim();
    final normalizedNote = trimmedNote == null || trimmedNote.isEmpty
        ? null
        : trimmedNote;

    final now = DateTime.now().toUtc();
    final movement = StockMovement(
      id: 'movement-${++_sequence}',
      productId: productId,
      variantId: variantId,
      movementType: delta > 0
          ? StockMovementType.adjustmentIn
          : StockMovementType.adjustmentOut,
      quantity: delta,
      stockBefore: current,
      stockAfter: stockAfter,
      reason: reason,
      note: normalizedNote,
      referenceType: null,
      referenceId: null,
      createdAt: now,
      updatedAt: now,
    );
    if (variantId == null) {
      productStock[productId] = stockAfter;
    } else {
      variantStock[variantId] = stockAfter;
    }
    storedMovements.add(movement);
    return movement;
  }

  @override
  Future<StockMovement> recordOpening({
    required String productId,
    required int quantity,
    String? note,
  }) async {
    final error = openingError;
    if (error != null) {
      throw error;
    }
    if (quantity <= 0) {
      throw const InvalidOpeningQuantityFailure();
    }
    final current = productStock[productId];
    if (current == null) {
      throw const ProductNotFoundFailure();
    }
    final alreadyOpened = storedMovements.any(
      (m) =>
          m.productId == productId &&
          m.movementType == StockMovementType.opening,
    );
    if (alreadyOpened) {
      throw const DuplicateOpeningFailure();
    }

    final trimmedNote = note?.trim();
    final normalizedNote = trimmedNote == null || trimmedNote.isEmpty
        ? null
        : trimmedNote;

    final now = DateTime.now().toUtc();
    final stockAfter = current + quantity;
    final movement = StockMovement(
      id: 'movement-${++_sequence}',
      productId: productId,
      movementType: StockMovementType.opening,
      quantity: quantity,
      stockBefore: current,
      stockAfter: stockAfter,
      reason: null,
      note: normalizedNote,
      referenceType: null,
      referenceId: null,
      createdAt: now,
      updatedAt: now,
    );
    productStock[productId] = stockAfter;
    storedMovements.add(movement);
    return movement;
  }
}
