import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'sales.dart';

/// ---------------------------------------------------------------------------
/// Sale payments — one row per payment leg of a split sale
///
/// A sale paid with both Cash and UPI records one row per method. The
/// `sales.payment_method` column stays for backward compatibility (single
/// payment sales); split sales leave it NULL and store the legs here.
/// ---------------------------------------------------------------------------
@TableIndex(name: 'idx_sale_payments_sale', columns: {#saleId})
class SalePayments extends Table {
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  TextColumn get saleId => text().references(Sales, #id)();

  TextColumn get paymentMethod => text().customConstraint(
    "NOT NULL CHECK (payment_method IN ('CASH', 'UPI'))",
  )();

  IntColumn get amountPaise =>
      integer().customConstraint('NOT NULL CHECK (amount_paise > 0)')();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
