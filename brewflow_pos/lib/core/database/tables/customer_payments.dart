import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'customers.dart';
import 'sales.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// CustomerPayments — one row per recorded payment on a customer's bill
///
/// Phase 8 ledger conventions:
/// - Every payment the app records is allocated to exactly one sale
///   ([CustomerPayments.saleId]); the column stays nullable so future
///   advance/whole-balance payments need no migration. The repository
///   rejects unallocated payments today.
/// - Money is stored as INTEGER minor units (paise); the DB CHECK only
///   rejects negative amounts ([amountPaise] >= 0) because SQLite cannot
///   express "> 0" in a column CHECK that must also accept zero — the
///   repository enforces amountPaise > 0.
/// - Payments are append-only money records: no isActive, no hard delete,
///   no editing. Reversal is a future compensating entry ([reversed] +
///   [reversedAt]); every due/paid sum filters `reversed = 0` from day one.
/// - No payment reference/counter, no persisted sale payment status, no
///   balance column — sale payment status stays derived.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_customer_payments_shop', columns: {#shopId})
@TableIndex(
  name: 'idx_customer_payments_customer_id',
  columns: {#shopId, #customerId},
)
@TableIndex(name: 'idx_customer_payments_sale_id', columns: {#saleId})
@TableIndex(name: 'idx_customer_payments_paid_at', columns: {#shopId, #paidAt})
class CustomerPayments extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this customer payment.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning customer. Deleting a customer with payments is rejected.
  TextColumn get customerId =>
      text().references(Customers, #id, onDelete: KeyAction.restrict)();

  /// Sale the payment is allocated to; NULL is reserved for future
  /// advance/whole-balance payments (the repository requires allocation).
  TextColumn get saleId =>
      text().nullable().references(Sales, #id, onDelete: KeyAction.restrict)();

  /// Amount paid in paise. Must be >= 0; the repository requires > 0.
  IntColumn get amountPaise =>
      integer().customConstraint('NOT NULL CHECK (amount_paise >= 0)')();

  /// Payment method captured at the counter: CASH, UPI or BANK.
  TextColumn get paymentMethod => text().customConstraint(
    "NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK'))",
  )();

  /// Optional free-form note; NULL when blank.
  TextColumn get note => text().nullable()();

  /// Exact UTC instant the money moved (the business timestamp; no
  /// back-dating in Phase 8).
  DateTimeColumn get paidAt => dateTime()();

  /// Compensating-entry flag; FALSE for every Phase 8 payment.
  BoolColumn get reversed => boolean().withDefault(const Constant(false))();

  /// When [reversed] flips true; NULL otherwise.
  DateTimeColumn get reversedAt => dateTime().nullable()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
