import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// PurchaseSequences — transaction-safe purchase number counter
///
/// A single row (id = 'purchase') holds the next purchase sequence value.
/// The counter is consumed inside the same transaction as the purchase insert
/// via `UPDATE ... RETURNING`, so purchase numbers are unique and gapless
/// even under concurrent receiving. The row is seeded by the repository
/// (INSERT OR IGNORE) because migrations cannot seed data.
///
/// Mirrors [SaleSequences]; the purchase counter is intentionally separate
/// so purchase and receipt numbers never share a sequence.
/// ---------------------------------------------------------------------------

class PurchaseSequences extends Table {
  /// Fixed row id: 'purchase'.
  TextColumn get id => text()();

  @override
  Set<Column> get primaryKey => {id};

  /// The next sequence value to hand out, seeded at 0 so the first purchase
  /// is 1. Must be >= 0.
  IntColumn get nextValue => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (next_value >= 0)',
  )();
}
