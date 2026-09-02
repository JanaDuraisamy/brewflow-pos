import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Expenses — one row per recorded business expense
///
/// Conventions:
/// - Money is stored as INTEGER minor units (paise), see [Products].
/// - [Expenses.category] is a stable, predefined category value (SUPPLIES,
///   UTILITIES, RENT, SALARIES, MAINTENANCE, MARKETING, TRANSPORT, MISC);
///   the driving enum lives in the expenses domain.
/// - [Expenses.paymentMethod] is one of CASH / UPI / BANK (no gateway
///   involved), mirroring [Sales].
/// - [Expenses.expenseDate] is the business date of the expense, stored as a
///   UTC instant at local midnight of the chosen day so existing UTC
///   storage/display conventions hold unchanged.
/// - Expenses are deactivated, never hard-deleted, so future modules
///   (reports, audit) can keep referencing them safely — the same soft
///   semantics as products, categories and customers.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_expenses_shop', columns: {#shopId})
@TableIndex(name: 'idx_expenses_expense_date', columns: {#shopId, #expenseDate})
@TableIndex(name: 'idx_expenses_category', columns: {#shopId, #category})
@TableIndex(name: 'idx_expenses_updated_at', columns: {#shopId, #updatedAt})
class Expenses extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this expense.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Expense display name.
  TextColumn get name => text()();

  /// Amount spent in paise. Must be >= 0; the expense form requires > 0.
  IntColumn get amountPaise =>
      integer().customConstraint('NOT NULL CHECK (amount_paise >= 0)')();

  /// Predefined expense category (stable DB value, see the domain enum).
  TextColumn get category => text().customConstraint(
    "NOT NULL CHECK (category IN ('SUPPLIES', 'UTILITIES', 'RENT', "
    "'SALARIES', 'MAINTENANCE', 'MARKETING', 'TRANSPORT', 'MISC'))",
  )();

  /// Payment method captured at the counter: CASH, UPI or BANK.
  TextColumn get paymentMethod => text().customConstraint(
    "NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK'))",
  )();

  /// Payment status: PAID or NOT_PAID (stable DB value, see the expenses
  /// domain enum). NOT_PAID expenses still count in history and totals and
  /// become shop payable. Existing records default to PAID.
  TextColumn get paymentStatus => text().customConstraint(
    "NOT NULL DEFAULT 'PAID' CHECK "
    "(payment_status IN ('PAID', 'NOT_PAID'))",
  )();

  /// Business date of the expense; UTC instant at local midnight of the
  /// user-selected local day.
  DateTimeColumn get expenseDate => dateTime()();

  /// Optional free-form note; NULL when blank.
  TextColumn get note => text().nullable()();

  /// Soft switch to hide an expense from active lists without deleting it.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
