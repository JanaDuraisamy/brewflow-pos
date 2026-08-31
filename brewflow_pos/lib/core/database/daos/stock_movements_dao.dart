library;

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movements DAO
///
/// All Drift access for the stock_movements table lives here. Query/row logic
/// only; the adjustment transaction and business rules (delta validation,
/// conditional stock update, failure mapping) live in the stock-movement
/// repository. Filtering and ordering happen in SQL, never in memory.
/// ---------------------------------------------------------------------------

final class StockMovementsDao {
  StockMovementsDao(this._db);

  final AppDatabase _db;

  /// Movements for one stock entity, newest first by [createdAt].
  ///
  /// [variantId] null returns the product's own movements (variant_id IS
  /// NULL); a [variantId] returns that variant's movements. The two are
  /// never mixed — each stock entity's history is isolated.
  Future<List<StockMovement>> movementsFor(
    String productId, {
    String? variantId,
  }) {
    final query = _db.select(_db.stockMovements)
      ..where(
        (t) =>
            t.productId.equals(productId) &
            (variantId == null
                ? t.variantId.isNull()
                : t.variantId.equals(variantId)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]);
    return query.get();
  }

  /// Whether an OPENING movement already exists for the stock entity (there
  /// may be at most one, mirroring creation).
  Future<bool> hasOpening(String productId, {String? variantId}) {
    final query = _db.select(_db.stockMovements)
      ..where(
        (t) =>
            t.productId.equals(productId) &
            t.movementType.equals('OPENING') &
            (variantId == null
                ? t.variantId.isNull()
                : t.variantId.equals(variantId)),
      )
      ..limit(1);
    return query.get().then((rows) => rows.isNotEmpty);
  }

  /// Inserts one movement and returns the persisted row (including the
  /// generated id).
  Future<StockMovement> insert(StockMovementsCompanion companion) {
    return _db.into(_db.stockMovements).insertReturning(companion);
  }

  /// Inserts many movements in a single batch (used by checkout integration).
  Future<void> insertAll(List<StockMovementsCompanion> companions) {
    return _db.batch((batch) {
      batch.insertAll(_db.stockMovements, companions);
    });
  }
}
