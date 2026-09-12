library;

import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/network/online_guard.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/features/inventory/data/stock_adjustment_cloud_gateway.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Stock Movement Repository
///
/// Implements [StockMovementRepository] on the local Drift database.
///
/// Online (production): [adjustStock] and [recordOpening] are
/// cloud-authoritative. The write requires connectivity (rejecting with
/// "Internet connection required"), runs through the `adjust_stock_atomic`
/// Supabase RPC, and the returned `stock_before`/`stock_after` (plus the server
/// movement) are mirrored into local Drift so the phone stays consistent
/// between pulls. NO outbox entry is ever created — the RPC is the write.
///
/// Offline-first fallback (no cloud gateway, tests): both operations run
/// inside one local transaction — the stock entity (product or variant) is
/// read to confirm existence, then a database-level conditional
/// `UPDATE products SET stock_quantity = stock_quantity + ? ...
///  WHERE id = ? AND stock_quantity + ? >= 0 RETURNING stock_quantity`
/// (mirrored against `product_variants` for variant adjustments) applies the
/// change. The returned stock is the value the row actually committed to, so
/// [StockMovement.stockAfter] (and the derived [StockMovement.stockBefore])
/// can never disagree with reality — there is no read-then-write race. If the
/// guard rejects the update (0 rows), the whole transaction is discarded: the
/// stock is unchanged and no movement is written.
///
/// [recordOpening] runs the same way inside one transaction (existence,
/// at-most-one-OPENING guard, then the stock update and the movement insert)
/// so a rejected opening never leaves partial writes.
///
/// All failures are translated into safe [StockMovementFailure] values
/// (details logged via [AppLog], never shown).
/// ---------------------------------------------------------------------------

final class DriftStockMovementRepository implements StockMovementRepository {
  DriftStockMovementRepository(
    db.AppDatabase database, {
    ConnectivityService? connectivityService,
    StockAdjustmentCloudGateway? cloudGateway,
  }) : _database = database,
       _movements = StockMovementsDao(database),
       _connectivity = connectivityService,
       _cloud = cloudGateway;

  static const String tag = 'StockMovement';

  final db.AppDatabase _database;
  final StockMovementsDao _movements;
  final ConnectivityService? _connectivity;
  final StockAdjustmentCloudGateway? _cloud;

  Future<void> _requireOnline() async {
    final connectivity = _connectivity;
    if (connectivity != null) {
      await OnlineGuard(connectivity).requireOnline();
    }
  }

  @override
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  }) async {
    try {
      final rows = await _movements.movementsFor(
        productId,
        variantId: variantId,
      );
      return [for (final row in rows) _movementFromRow(row)];
    } on StockMovementFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load stock movements', error, stackTrace);
    }
  }

  @override
  Future<StockMovement> adjustStock({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    if (delta == 0) {
      throw const InvalidAdjustmentQuantityFailure();
    }
    final normalizedNote = _optionalText(note);
    try {
      if (_connectivity != null) {
        try {
          await _requireOnline();
        } on OfflineException catch (e) {
          throw UnexpectedStockMovementFailure(e.message);
        }
      }
      if (_cloud != null) {
        return await _adjustStockViaCloud(
          productId: productId,
          variantId: variantId,
          delta: delta,
          reason: reason,
          note: normalizedNote,
        );
      }
      return await _adjustStockLocally(
        productId: productId,
        variantId: variantId,
        delta: delta,
        reason: reason,
        note: normalizedNote,
      );
    } on StockMovementFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to adjust stock', error, stackTrace);
    }
  }

  @override
  Future<StockMovement> recordOpening({
    required String productId,
    required int quantity,
    String? note,
  }) async {
    if (quantity <= 0) {
      throw const InvalidOpeningQuantityFailure();
    }
    final normalizedNote = _optionalText(note);
    try {
      if (_connectivity != null) {
        try {
          await _requireOnline();
        } on OfflineException catch (e) {
          throw UnexpectedStockMovementFailure(e.message);
        }
      }
      if (_cloud != null) {
        return await _recordOpeningViaCloud(
          productId: productId,
          quantity: quantity,
          note: normalizedNote,
        );
      }
      return await _recordOpeningLocally(
        productId: productId,
        quantity: quantity,
        note: normalizedNote,
      );
    } on StockMovementFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record opening stock', error, stackTrace);
    }
  }

  // ---------------------------------------------------------------------------
  // Cloud-authoritative path (online-only)
  // ---------------------------------------------------------------------------

  Future<StockMovement> _adjustStockViaCloud({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) async {
    await _ensureStockEntity(productId, variantId);
    final resolvedShopId = await resolveWritableShopId(_database);
    final result = await _callAdjustmentRpc(
      shopId: resolvedShopId,
      productId: productId,
      variantId: variantId,
      delta: delta,
      reason: reason.dbValue,
      note: note,
    );
    return _mirrorMovement(
      result: result,
      productId: productId,
      variantId: variantId,
      quantity: delta,
      reason: reason.dbValue,
      note: note,
      movementType: delta > 0
          ? StockMovementType.adjustmentIn
          : StockMovementType.adjustmentOut,
    );
  }

  Future<StockMovement> _recordOpeningViaCloud({
    required String productId,
    required int quantity,
    String? note,
  }) async {
    if (await _movements.hasOpening(productId)) {
      throw const DuplicateOpeningFailure();
    }
    await _ensureStockEntity(productId, null);
    final resolvedShopId = await resolveWritableShopId(_database);
    final result = await _callAdjustmentRpc(
      shopId: resolvedShopId,
      productId: productId,
      variantId: null,
      delta: quantity,
      reason: 'OPENING',
      note: note,
    );
    return _mirrorMovement(
      result: result,
      productId: productId,
      variantId: null,
      quantity: quantity,
      reason: null,
      note: note,
      movementType: StockMovementType.opening,
    );
  }

  Future<Map<String, dynamic>> _callAdjustmentRpc({
    required String shopId,
    required String productId,
    String? variantId,
    required int delta,
    required String reason,
    String? note,
  }) async {
    try {
      return await _cloud!.adjustStockAtomic(
        shopId: shopId,
        productId: productId,
        variantId: variantId,
        delta: delta,
        reason: reason,
        note: note,
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('INSUFFICIENT_STOCK')) {
        throw const AdjustmentInsufficientStockFailure();
      }
      if (msg.contains('PRODUCT_NOT_FOUND') ||
          msg.contains('INACTIVE_PRODUCT')) {
        throw const ProductNotFoundFailure();
      }
      if (msg.contains('FORBIDDEN')) {
        throw const UnexpectedStockMovementFailure(
          'Access denied for this shop.',
        );
      }
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('Network is unreachable')) {
        throw const UnexpectedStockMovementFailure(
          'Internet connection required. Please check your connection and try again.',
        );
      }
      rethrow;
    }
  }

  /// Mirrors the server-committed movement locally: sets the entity's stock to
  /// the authoritative [result] value and inserts the movement row with the
  /// server id/timestamps. Runs atomically so stock and history never diverge.
  Future<StockMovement> _mirrorMovement({
    required Map<String, dynamic> result,
    required String productId,
    String? variantId,
    required int quantity,
    required String? reason,
    required String? note,
    required StockMovementType movementType,
  }) async {
    final movementId = result['id'] as String;
    final stockBefore = result['stock_before'] as int;
    final stockAfter = result['stock_after'] as int;
    final createdAt = result['created_at'] != null
        ? DateTime.parse(result['created_at'] as String).toUtc()
        : DateTime.now().toUtc();
    final now = DateTime.now().toUtc();
    final row = await _database.transaction(() async {
      if (variantId == null) {
        await (_database.update(
          _database.products,
        )..where((t) => t.id.equals(productId))).write(
          db.ProductsCompanion(
            stockQuantity: Value(stockAfter),
            updatedAt: Value(now),
          ),
        );
      } else {
        await (_database.update(
          _database.productVariants,
        )..where((t) => t.id.equals(variantId))).write(
          db.ProductVariantsCompanion(
            stockQuantity: Value(stockAfter),
            updatedAt: Value(now),
          ),
        );
      }
      return _movements.insert(
        db.StockMovementsCompanion.insert(
          id: Value(movementId),
          productId: productId,
          variantId: Value(variantId),
          movementType: movementType.dbValue,
          quantity: quantity,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: Value(reason),
          note: Value(note),
          referenceType: const Value(null),
          referenceId: const Value(null),
          createdAt: Value(createdAt),
          updatedAt: Value(now),
        ),
      );
    });
    return _movementFromRow(row);
  }

  /// Preserves the local existence validation: adjustments target an entity
  /// that must exist locally before any cloud write is attempted.
  Future<void> _ensureStockEntity(String productId, String? variantId) async {
    if (variantId == null) {
      final product = await (_database.select(
        _database.products,
      )..where((t) => t.id.equals(productId))).getSingleOrNull();
      if (product == null) {
        throw const ProductNotFoundFailure();
      }
    } else {
      final variant = await (_database.select(
        _database.productVariants,
      )..where((t) => t.id.equals(variantId))).getSingleOrNull();
      if (variant == null) {
        throw const ProductNotFoundFailure();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Offline-first fallback path (no cloud gateway; tests/legacy)
  // ---------------------------------------------------------------------------

  Future<StockMovement> _adjustStockLocally({
    required String productId,
    String? variantId,
    required int delta,
    required StockAdjustmentReason reason,
    String? note,
  }) {
    return _database.transaction(() async {
      final now = DateTime.now().toUtc();

      final String updateSql;
      final List<Variable> updateVariables;
      if (variantId == null) {
        final product = await (_database.select(
          _database.products,
        )..where((t) => t.id.equals(productId))).getSingleOrNull();
        if (product == null) {
          throw const ProductNotFoundFailure();
        }
        updateSql =
            'UPDATE products SET stock_quantity = stock_quantity + ?, '
            'updated_at = ? WHERE id = ? AND stock_quantity + ? >= 0 '
            'RETURNING stock_quantity';
        updateVariables = [
          Variable.withInt(delta),
          Variable.withDateTime(now),
          Variable.withString(productId),
          Variable.withInt(delta),
        ];
      } else {
        final variant = await (_database.select(
          _database.productVariants,
        )..where((t) => t.id.equals(variantId))).getSingleOrNull();
        if (variant == null) {
          throw const ProductNotFoundFailure();
        }
        updateSql =
            'UPDATE product_variants SET stock_quantity = '
            'stock_quantity + ?, updated_at = ? WHERE id = ? AND '
            'stock_quantity + ? >= 0 RETURNING stock_quantity';
        updateVariables = [
          Variable.withInt(delta),
          Variable.withDateTime(now),
          Variable.withString(variantId),
          Variable.withInt(delta),
        ];
      }

      final updated = await _database
          .customSelect(updateSql, variables: updateVariables)
          .getSingleOrNull();
      if (updated == null) {
        throw const AdjustmentInsufficientStockFailure();
      }

      final stockAfter = updated.read<int>('stock_quantity');
      final stockBefore = stockAfter - delta;
      final movementType = delta > 0
          ? StockMovementType.adjustmentIn
          : StockMovementType.adjustmentOut;

      final row = await _movements.insert(
        db.StockMovementsCompanion.insert(
          productId: productId,
          variantId: Value(variantId),
          movementType: movementType.dbValue,
          quantity: delta,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: Value(reason.dbValue),
          note: Value(note),
          referenceType: const Value(null),
          referenceId: const Value(null),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return _movementFromRow(row);
    });
  }

  Future<StockMovement> _recordOpeningLocally({
    required String productId,
    required int quantity,
    String? note,
  }) {
    return _database.transaction(() async {
      final product = await (_database.select(
        _database.products,
      )..where((t) => t.id.equals(productId))).getSingleOrNull();
      if (product == null) {
        throw const ProductNotFoundFailure();
      }

      final alreadyOpened = await _movements.hasOpening(productId);
      if (alreadyOpened) {
        throw const DuplicateOpeningFailure();
      }

      final now = DateTime.now().toUtc();
      final updated = await _database
          .customSelect(
            'UPDATE products '
            'SET stock_quantity = stock_quantity + ?, updated_at = ? '
            'WHERE id = ? '
            'RETURNING stock_quantity',
            variables: [
              Variable.withInt(quantity),
              Variable.withDateTime(now),
              Variable.withString(productId),
            ],
          )
          .getSingleOrNull();
      if (updated == null) {
        throw const UnexpectedStockMovementFailure();
      }

      final stockAfter = updated.read<int>('stock_quantity');
      final stockBefore = stockAfter - quantity;

      final row = await _movements.insert(
        db.StockMovementsCompanion.insert(
          productId: productId,
          variantId: const Value(null),
          movementType: StockMovementType.opening.dbValue,
          quantity: quantity,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          reason: const Value(null),
          note: Value(note),
          referenceType: const Value(null),
          referenceId: const Value(null),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return _movementFromRow(row);
    });
  }

  StockMovement _movementFromRow(db.StockMovement row) {
    final movementType = StockMovementType.fromDbValue(row.movementType);
    if (movementType == null) {
      throw const UnexpectedStockMovementFailure();
    }
    final reason = row.reason == null
        ? null
        : StockAdjustmentReason.fromDbValue(row.reason!);
    if (row.reason != null && reason == null) {
      throw const UnexpectedStockMovementFailure();
    }
    return StockMovement(
      id: row.id,
      productId: row.productId,
      variantId: row.variantId,
      movementType: movementType,
      quantity: row.quantity,
      stockBefore: row.stockBefore,
      stockAfter: row.stockAfter,
      reason: reason,
      note: row.note,
      referenceType: row.referenceType,
      referenceId: row.referenceId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }

  String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  StockMovementFailure _unexpected(
    String message,
    Object error,
    StackTrace stackTrace,
  ) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    return const UnexpectedStockMovementFailure();
  }
}
