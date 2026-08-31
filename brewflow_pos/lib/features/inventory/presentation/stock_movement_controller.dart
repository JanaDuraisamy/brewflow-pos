import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movement State (Riverpod)
///
/// The integration layer between business operations and the
/// [StockMovementRepository] persistence boundary (Step 2).
///
/// Composition:
/// - [stockMovementRepositoryProvider] → Drift-backed repository (override in
///                                        tests with a fake).
/// - [productMovementsProvider]        → movement history for one product
///                                       (product-level movements only).
/// - [variantMovementsProvider]        → movement history for one variant.
///
/// Mutations go through [ProductMovementsController.adjustStock] /
/// [VariantMovementsController.adjustStock] and the recordOpening methods,
/// which delegate to the repository and then refresh this entity's history,
/// the product list, the POS shelf and the dashboard. Every failure is
/// translated into a safe [StockMovementFailure] (details logged, never
/// shown).
///
/// The SALE movement is written by the billing repository inside the checkout
/// transaction (this controller never records sales); the checkout flow
/// invalidates these providers so history refreshes after a sale.
/// ---------------------------------------------------------------------------

/// Owns the single stock-movement repository for the application scope.
final stockMovementRepositoryProvider = Provider<StockMovementRepository>((
  ref,
) {
  return DriftStockMovementRepository(ref.watch(appDatabaseProvider));
});

/// Movement history for one product, newest first; product-level movements
/// only (variant movements live under [variantMovementsProvider]). Rebuilds
/// after [ProductMovementsController.adjustStock].
final productMovementsProvider =
    AsyncNotifierProvider.family<
      ProductMovementsController,
      List<StockMovement>,
      String
    >(ProductMovementsController.new);

final class ProductMovementsController
    extends AsyncNotifier<List<StockMovement>> {
  /// The product whose history this controller holds; injected by the family
  /// provider (Riverpod 3 passes the family argument to the constructor).
  ProductMovementsController(this.productId);

  final String productId;

  static const String tag = 'StockMovement';

  @override
  Future<List<StockMovement>> build() async {
    final repository = ref.watch(stockMovementRepositoryProvider);
    try {
      return await repository.movementsFor(productId);
    } on StockMovementFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load stock movements',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedStockMovementFailure();
    }
  }

  /// Records an inventory adjustment for this product and returns the written
  /// movement.
  ///
  /// [delta] is a signed change: positive adds stock (ADJUSTMENT_IN), negative
  /// removes stock (ADJUSTMENT_OUT); zero is rejected by the repository. The
  /// product's history, the product list, the POS shelf and the dashboard are
  /// refreshed on success. [StockMovementFailure]s pass through untouched;
  /// anything unexpected is logged and rethrown as
  /// [UnexpectedStockMovementFailure].
  Future<StockMovement> adjustStock({
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    requirePermission(ref, Permission.stockAdjustment);
    final movement = await _adjustAndRefresh(
      ref,
      productId: productId,
      delta: delta,
      reason: reason,
      note: note,
    );
    ref.invalidateSelf();
    return movement;
  }

  /// Records the initial stock baseline for this product and returns the
  /// written OPENING movement.
  ///
  /// [quantity] is the positive opening amount in units; a product may have
  /// only one opening (a second attempt throws [DuplicateOpeningFailure]). The
  /// product's history, the product list, the POS shelf and the dashboard are
  /// refreshed on success. [StockMovementFailure]s pass through untouched;
  /// anything unexpected is logged and rethrown as
  /// [UnexpectedStockMovementFailure].
  Future<StockMovement> recordOpening({
    required int quantity,
    String? note,
  }) async {
    requirePermission(ref, Permission.stockAdjustment);
    final movement = await _recordOpeningAndRefresh(
      ref,
      productId: productId,
      quantity: quantity,
      note: note,
    );
    ref.invalidateSelf();
    return movement;
  }
}

/// Movement history for one variant, newest first; rebuilds after
/// [VariantMovementsController.adjustStock].
final variantMovementsProvider =
    AsyncNotifierProvider.family<
      VariantMovementsController,
      List<StockMovement>,
      ({String productId, String variantId})
    >(VariantMovementsController.new);

final class VariantMovementsController
    extends AsyncNotifier<List<StockMovement>> {
  /// The stock entity whose history this controller holds; injected by the
  /// family provider (Riverpod 3 passes the family argument to the
  /// constructor).
  VariantMovementsController(this.arg);

  final ({String productId, String variantId}) arg;

  String get productId => arg.productId;

  String get variantId => arg.variantId;

  static const String tag = 'StockMovement';

  @override
  Future<List<StockMovement>> build() async {
    final repository = ref.watch(stockMovementRepositoryProvider);
    try {
      return await repository.movementsFor(productId, variantId: variantId);
    } on StockMovementFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load stock movements',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedStockMovementFailure();
    }
  }

  /// Records an inventory adjustment for this variant and returns the written
  /// movement.
  ///
  /// [delta] is a signed change: positive adds stock (ADJUSTMENT_IN), negative
  /// removes stock (ADJUSTMENT_OUT); zero is rejected by the repository. The
  /// variant's history, the product list, the POS shelf and the dashboard are
  /// refreshed on success. [StockMovementFailure]s pass through untouched;
  /// anything unexpected is logged and rethrown as
  /// [UnexpectedStockMovementFailure].
  Future<StockMovement> adjustStock({
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    requirePermission(ref, Permission.stockAdjustment);
    final movement = await _adjustAndRefresh(
      ref,
      productId: productId,
      variantId: variantId,
      delta: delta,
      reason: reason,
      note: note,
    );
    ref.invalidateSelf();
    return movement;
  }
}

/// Shared adjustment pipeline: run the repository call, then refresh the
/// affected state. [StockMovementFailure]s pass through untouched; anything
/// unexpected is logged and rethrown as [UnexpectedStockMovementFailure].
Future<StockMovement> _adjustAndRefresh(
  Ref ref, {
  required String productId,
  String? variantId,
  required int delta,
  required StockAdjustmentReason reason,
  String? note,
}) async {
  try {
    final movement = await ref
        .read(stockMovementRepositoryProvider)
        .adjustStock(
          productId: productId,
          variantId: variantId,
          delta: delta,
          reason: reason,
          note: note,
        );
    _refreshAfterMutation(ref);
    return movement;
  } on StockMovementFailure {
    rethrow;
  } catch (error, stackTrace) {
    AppLog.error(
      'Failed to adjust stock',
      tag: 'StockMovement',
      error: error,
      stackTrace: stackTrace,
    );
    throw const UnexpectedStockMovementFailure();
  }
}

/// Shared opening pipeline: run the repository call, then refresh the
/// affected state. [StockMovementFailure]s pass through untouched; anything
/// unexpected is logged and rethrown as [UnexpectedStockMovementFailure].
Future<StockMovement> _recordOpeningAndRefresh(
  Ref ref, {
  required String productId,
  required int quantity,
  String? note,
}) async {
  try {
    final movement = await ref
        .read(stockMovementRepositoryProvider)
        .recordOpening(productId: productId, quantity: quantity, note: note);
    _refreshAfterMutation(ref);
    return movement;
  } on StockMovementFailure {
    rethrow;
  } catch (error, stackTrace) {
    AppLog.error(
      'Failed to record opening stock',
      tag: 'StockMovement',
      error: error,
      stackTrace: stackTrace,
    );
    throw const UnexpectedStockMovementFailure();
  }
}

/// Invalidates every provider that reflects stock levels: this entity's
/// history is refreshed by the calling controller's own invalidation of its
/// provider, so here we refresh the shared surfaces (product list, POS shelf,
/// dashboard, reports).
void _refreshAfterMutation(Ref ref) {
  ref.invalidate(productsProvider);
  ref.invalidate(posProductsProvider);
  ref.invalidate(dashboardControllerProvider);
  ref.invalidate(reportsControllerProvider);
}

/// Maps any thrown object to a user-safe message.
///
/// [StockMovementFailure]s already carry display-ready text; anything else
/// falls back to a generic message (with [fallback] when provided).
String stockMovementErrorMessage(Object error, {String? fallback}) {
  if (error is StockMovementFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
