import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// SaleSequences — transaction-safe receipt number counter
///
/// A single row (id = 'receipt') holds the next receipt sequence value.
/// The counter is consumed inside the same transaction as the sale insert
/// via `UPDATE ... RETURNING`, so receipt numbers are unique and gapless
/// even under concurrent checkouts. The row is seeded by the repository
/// (INSERT OR IGNORE) because migrations cannot seed data.
/// ---------------------------------------------------------------------------

class SaleSequences extends Table {
  /// Fixed row id: 'receipt'.
  TextColumn get id => text()();

  @override
  Set<Column> get primaryKey => {id};

  /// The next sequence value to hand out, seeded at 0 so the first receipt
  /// is 1. Must be >= 0.
  IntColumn get nextValue => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (next_value >= 0)',
  )();
}
