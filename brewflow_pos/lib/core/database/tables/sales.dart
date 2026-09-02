import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'customers.dart';
import 'sale_sequences.dart';
import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Sales — one row per completed POS transaction
///
/// - Money is stored as INTEGER minor units (paise), see [Products].
/// - [Sales.receiptNumber] is the human-readable, customer-facing reference
///   (e.g. 'BF-000042') produced by the receipt counter in [SaleSequences].
/// - [Sales.paymentMethod] is one of CASH / UPI / BANK (no gateway involved)
///   and is NULL for NOT_PAID (credit) sales — no fake method is recorded for
///   an unpaid bill. The CHECK only guards non-NULL values; SQLite lets NULL
///   pass CHECK constraints.
/// - [Sales.paymentStatus] is PAID or NOT_PAID; every existing sale is PAID
///   by default. A NOT_PAID sale is still a completed sale (revenue, stock
///   and profit count normally) — the status only describes collection.
/// - [Sales.customerId] is NULL for walk-in sales; customer-linked sales
///   reference a real profile (the point of contact for dues/purchase
///   history). Customers are never hard-deleted, and the RESTRICT FK is the
///   backstop that keeps billed history linked to its owner. NOT_PAID sales
///   REQUIRE a customer: the unpaid total is the customer's ledger debt.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_sales_shop', columns: {#shopId})
@TableIndex(name: 'idx_sales_created_at', columns: {#shopId, #createdAt})
@TableIndex(name: 'idx_sales_customer_id', columns: {#shopId, #customerId})
class Sales extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this sale.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning customer for customer-linked sales; NULL for walk-ins. Deleting a
  /// customer with sales history is rejected (RESTRICT).
  TextColumn get customerId => text().nullable().references(
    Customers,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Human-readable receipt reference; unique per shop.
  TextColumn get receiptNumber => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, receiptNumber},
  ];

  /// Sum of line totals in paise, before any adjustments. Must be >= 0.
  IntColumn get subtotalPaise =>
      integer().customConstraint('NOT NULL CHECK (subtotal_paise >= 0)')();

  /// Amount charged in paise. Equals the subtotal (no discounts/taxes yet).
  IntColumn get totalPaise =>
      integer().customConstraint('NOT NULL CHECK (total_paise >= 0)')();

  /// Payment method captured at the counter: CASH, UPI or BANK. NULL for
  /// NOT_PAID (credit) sales, where no money moved at the counter.
  TextColumn get paymentMethod => text().nullable().customConstraint(
    "CHECK (payment_method IN ('CASH', 'UPI', 'BANK'))",
  )();

  /// Collection status of the sale: PAID or NOT_PAID (credit sale whose
  /// total becomes customer debt). Defaults to PAID so existing rows (and
  /// future inserts that omit it) are treated as settled.
  TextColumn get paymentStatus => text().customConstraint(
    "NOT NULL DEFAULT 'PAID' CHECK (payment_status IN ('PAID', 'NOT_PAID'))",
  )();

  /// UTC timestamp of the sale.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// Whether this sale has been voided. A voided sale is never hard-deleted;
  /// the row is kept for audit purposes, stock is restored and payments
  /// reversed.
  BoolColumn get voided => boolean().withDefault(const Constant(false))();

  /// When the sale was voided; NULL when still active.
  DateTimeColumn get voidedAt => dateTime().nullable()();
}
