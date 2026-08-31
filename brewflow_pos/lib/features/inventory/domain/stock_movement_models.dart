library;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movement Domain Models
///
/// Immutable business models for the inventory stock-movement audit trail.
/// Persistence details (Drift rows) never leak past the repository boundary.
///
/// Quantities are integer units (never paise). [StockMovement.quantity] stays
/// a signed delta exactly as stored: positive = stock added, negative = stock
/// removed. The domain never converts it to an absolute magnitude.
/// ---------------------------------------------------------------------------

/// What happened to stock. Mirrors the CHECK-constrained `movement_type` column.
enum StockMovementType {
  opening('OPENING'),
  sale('SALE'),
  purchase('PURCHASE'),
  adjustmentIn('ADJUSTMENT_IN'),
  adjustmentOut('ADJUSTMENT_OUT');

  const StockMovementType(this.dbValue);

  /// Stable storage value for CHECK constraints and history.
  final String dbValue;

  /// Parses a stored value; returns `null` for anything unexpected so the
  /// repository can fail safely instead of leaking a raw exception.
  static StockMovementType? fromDbValue(String value) => switch (value) {
    'OPENING' => StockMovementType.opening,
    'SALE' => StockMovementType.sale,
    'PURCHASE' => StockMovementType.purchase,
    'ADJUSTMENT_IN' => StockMovementType.adjustmentIn,
    'ADJUSTMENT_OUT' => StockMovementType.adjustmentOut,
    _ => null,
  };
}

/// Why an adjustment happened. Mirrors the CHECK-constrained `reason` column.
///
/// Reasons are orthogonal to [StockMovementType]: the type records *what*
/// changed the stock, the reason records *why*.
enum StockAdjustmentReason {
  purchase('PURCHASE'),
  damage('DAMAGE'),
  wastage('WASTAGE'),
  missing('MISSING'),
  correction('CORRECTION'),
  other('OTHER');

  const StockAdjustmentReason(this.dbValue);

  /// Stable storage value for CHECK constraints and history.
  final String dbValue;

  /// Parses a stored value; returns `null` for anything unexpected so the
  /// repository can fail safely instead of leaking a raw exception.
  static StockAdjustmentReason? fromDbValue(String value) => switch (value) {
    'PURCHASE' => StockAdjustmentReason.purchase,
    'DAMAGE' => StockAdjustmentReason.damage,
    'WASTAGE' => StockAdjustmentReason.wastage,
    'MISSING' => StockAdjustmentReason.missing,
    'CORRECTION' => StockAdjustmentReason.correction,
    'OTHER' => StockAdjustmentReason.other,
    _ => null,
  };
}

/// Short display label for a movement type.
String stockMovementTypeLabel(StockMovementType type) => switch (type) {
  StockMovementType.opening => 'Opening stock',
  StockMovementType.sale => 'Sale',
  StockMovementType.purchase => 'Purchase',
  StockMovementType.adjustmentIn => 'Adjustment in',
  StockMovementType.adjustmentOut => 'Adjustment out',
};

/// Short display label for an adjustment reason.
String stockAdjustmentReasonLabel(StockAdjustmentReason reason) =>
    switch (reason) {
      StockAdjustmentReason.purchase => 'Purchase',
      StockAdjustmentReason.damage => 'Damage',
      StockAdjustmentReason.wastage => 'Wastage',
      StockAdjustmentReason.missing => 'Missing',
      StockAdjustmentReason.correction => 'Correction',
      StockAdjustmentReason.other => 'Other',
    };

/// One append-only record of a stock quantity change for a single stock
/// entity: a product, or one of its variants.
final class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    this.variantId,
    required this.movementType,
    required this.quantity,
    required this.stockBefore,
    required this.stockAfter,
    this.reason,
    this.note,
    this.referenceType,
    this.referenceId,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Local UUID v4 identifier.
  final String id;

  /// Owning product.
  final String productId;

  /// Owning variant; null for movements against the product itself.
  final String? variantId;

  /// What changed the stock (OPENING / SALE / PURCHASE / ADJUSTMENT_IN /
  /// ADJUSTMENT_OUT).
  final StockMovementType movementType;

  /// Signed delta applied to stock; never zero.
  ///
  /// Positive for stock added (OPENING, PURCHASE, ADJUSTMENT_IN); negative
  /// for stock removed (SALE, ADJUSTMENT_OUT). The domain model preserves the
  /// sign exactly as stored.
  final int quantity;

  /// Stock level before the movement (>= 0).
  final int stockBefore;

  /// Stock level after the movement (>= 0).
  final int stockAfter;

  /// Why an adjustment happened; null for SALE / PURCHASE / OPENING movements.
  final StockAdjustmentReason? reason;

  /// Optional free-form note; null when blank.
  final String? note;

  /// Kind of referenced record (e.g. 'SALE'); null for standalone movements.
  final String? referenceType;

  /// Id of the referenced record; null for standalone movements.
  final String? referenceId;

  /// UTC creation timestamp.
  final DateTime createdAt;

  /// UTC last-change timestamp.
  final DateTime updatedAt;
}
