import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'product_variants.dart';
import 'products.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// StockMovements — append-only audit trail of every stock quantity change
///
/// Conventions:
/// - One row per stock change: product creation (OPENING), POS checkout
///   (SALE), purchase receiving (PURCHASE) and counter adjustments
///   (ADJUSTMENT_IN / ADJUSTMENT_OUT).
/// - [StockMovements.quantity] is a signed delta: positive = stock added,
///   negative = stock removed. Every row records the absolute
///   [StockMovements.stockBefore] / [StockMovements.stockAfter] so the audit
///   trail is self-contained and verifiable.
/// - [StockMovements.reason] answers *why* for adjustment movements
///   (PURCHASE / DAMAGE / WASTAGE / MISSING / CORRECTION / OTHER); the
///   movement type answers *what* happened. [StockMovements.note] carries
///   optional free-form context.
/// - [StockMovements.referenceType] / [StockMovements.referenceId] are audit
///   references (SALE → sales.id, PURCHASE → purchases.id) with NO database FK
///   by design; sales and purchases are immutable in this app and the
///   reference is a snapshot.
/// - [StockMovements.variantId] identifies the variant a movement belongs to
///   (NULL for movements against the product itself). Variants are never
///   hard-deleted (soft deactivation instead), so the RESTRICT FK is safe and
///   keeps the audit trail bound to its owner.
/// - Movements are never edited or deleted; history begins with Phase 9
///   implementation — no backfill rows are fabricated for existing data.
/// - No operator/user column and no price/cost snapshots: neither exists in
///   the application yet, and inventory valuation is out of scope.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_stock_movements_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_stock_movements_product_created_at',
  columns: {#shopId, #productId, #createdAt},
)
@TableIndex(
  name: 'idx_stock_movements_variant_created_at',
  columns: {#shopId, #variantId, #createdAt},
)
class StockMovements extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this movement.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// The product the movement belongs to. Products are never hard-deleted
  /// (soft deactivation instead); RESTRICT keeps history bound to its owner.
  TextColumn get productId =>
      text().references(Products, #id, onDelete: KeyAction.restrict)();

  /// The variant the movement belongs to; NULL for movements against the
  /// product itself. Variants are never hard-deleted (soft deactivation
  /// instead); RESTRICT keeps history bound to its owner.
  TextColumn get variantId => text().nullable().references(
    ProductVariants,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// What happened to stock: OPENING, SALE, PURCHASE, ADJUSTMENT_IN or
  /// ADJUSTMENT_OUT.
  TextColumn get movementType => text().customConstraint(
    "NOT NULL CHECK (movement_type IN "
    "('OPENING', 'SALE', 'PURCHASE', 'ADJUSTMENT_IN', 'ADJUSTMENT_OUT'))",
  )();

  /// Signed delta applied to stock; never zero.
  IntColumn get quantity =>
      integer().customConstraint('NOT NULL CHECK (quantity <> 0)')();

  /// Stock level before the movement. Must be >= 0.
  IntColumn get stockBefore =>
      integer().customConstraint('NOT NULL CHECK (stock_before >= 0)')();

  /// Stock level after the movement. Must be >= 0.
  IntColumn get stockAfter =>
      integer().customConstraint('NOT NULL CHECK (stock_after >= 0)')();

  /// Why an adjustment happened; NULL unless the movement is an adjustment.
  TextColumn get reason => text().nullable().customConstraint(
    "CHECK (reason IS NULL OR reason IN "
    "('PURCHASE', 'DAMAGE', 'WASTAGE', 'MISSING', 'CORRECTION', 'OTHER'))",
  )();

  /// Optional free-form note; NULL when blank.
  TextColumn get note => text().nullable()();

  /// Kind of referenced record (e.g. 'SALE'); NULL for standalone movements.
  TextColumn get referenceType => text().nullable()();

  /// Id of the referenced record (e.g. sales.id); NULL for standalone
  /// movements. Audit reference only — no database FK.
  TextColumn get referenceId => text().nullable()();

  /// UTC timestamp of the movement.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
