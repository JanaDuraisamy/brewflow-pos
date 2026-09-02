import 'package:drift/drift.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// SaleSequences — transaction-safe receipt number counter
///
/// A single row per shop (id = 'receipt', `shop_id` = `shopId`) holds the next
/// receipt sequence value. The counter is consumed inside the same transaction
/// as the sale insert via `UPDATE ... RETURNING`, so receipt numbers are unique
/// and gapless per shop even under concurrent checkouts.
/// ---------------------------------------------------------------------------

class SaleSequences extends Table {
  /// Fixed row id: 'receipt'.
  TextColumn get id => text()();

  /// Business/shop that owns this sequence.
  TextColumn get shopId =>
      text().references(Shops, #id, onDelete: KeyAction.cascade)();

  @override
  Set<Column> get primaryKey => {id, shopId};

  /// The next sequence value to hand out, seeded at 0 so the first receipt
  /// is 1. Must be >= 0.
  IntColumn get nextValue => integer().customConstraint(
    'NOT NULL DEFAULT 0 CHECK (next_value >= 0)',
  )();
}
