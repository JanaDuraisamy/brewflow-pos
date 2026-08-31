library;

import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Stock Movement Repository
///
/// Implements [StockMovementRepository] on the local Drift database.
///
/// [adjustStock] runs inside one transaction: the stock entity (product or
/// variant) is read to confirm existence, then a database-level conditional
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
  DriftStockMovementRepository(db.AppDatabase database)
    : _database = database,
      _movements = StockMovementsDao(database);

  static const String tag = 'StockMovement';

  final db.AppDatabase _database;
  final StockMovementsDao _movements;

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
      return await _database.transaction(() async {
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
            note: Value(normalizedNote),
            referenceType: const Value(null),
            referenceId: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return _movementFromRow(row);
      });
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
      return await _database.transaction(() async {
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
            note: Value(normalizedNote),
            referenceType: const Value(null),
            referenceId: const Value(null),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        return _movementFromRow(row);
      });
    } on StockMovementFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to record opening stock', error, stackTrace);
    }
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
