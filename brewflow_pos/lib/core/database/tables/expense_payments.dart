import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Expense payments — money the shop actually paid against what it owes
///
/// This is the payable-side mirror of [CustomerPayments]: an expense is what
/// the shop OWES (recorded, `NOT_PAID`, aggregated into shop payable), and an
/// expense payment is what it PAYS against that. Keeping the two apart is what
/// lets a partial settlement exist at all — a payment never edits, reduces or
/// deletes the original expense rows, so the expense history stays exactly as
/// it was recorded.
///
/// Conventions (mirroring [CustomerPayments] deliberately):
/// - Money is INTEGER minor units (paise), see [Expenses].
/// - Append-only money records: no `isActive`, no hard delete, no editing.
///   Reversal is a future compensating entry ([reversed] + [reversedAt]); every
///   due/paid sum filters `reversed = 0` from day one so a reversal needs no
///   migration later.
/// - NO stored balance column. The remaining balance is always derived as
///   `sum(NOT_PAID active expenses for the key) - sum(payments for the key)`.
///   A persisted balance would be a per-device value that sync could not
///   converge on; deriving it means every device computes the identical number
///   from the same rows, which is what makes cross-device balances agree.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_expense_payments_shop', columns: {#shopId})
@TableIndex(name: 'idx_expense_payments_payee', columns: {#shopId, #payeeKey})
@TableIndex(name: 'idx_expense_payments_paid_at', columns: {#shopId, #paidAt})
class ExpensePayments extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this payment. Scopes the payable: Cafe and Food
  /// Truck balances can never mix, because every sum filters on this.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Normalized grouping key of the payee/item this payment settles.
  ///
  /// Holds the *normalized* name (trimmed + lower-cased) rather than a foreign
  /// key to expenses, because a payment can span several expense rows that
  /// share one payee ("Milk" ₹700 + "Milk" ₹900 = one ₹1,600 payable). Storing
  /// the key is what makes partial payment of a group possible at all; the
  /// original expense rows are never touched.
  ///
  /// Deliberately NOT a foreign key: payments must outlive the expense rows
  /// they settle, and expenses can be hidden/removed without losing the money
  /// already paid against them.
  TextColumn get payeeKey => text()();

  /// The payee/item name as it was written when the payment was recorded, used
  /// for display. [payeeKey] stays the grouping identity; keeping the original
  /// casing means payment history reads "Milk" rather than the lower-cased key,
  /// and stays readable if the expenses behind it are later hidden.
  TextColumn get payeeName => text().nullable()();

  /// Amount paid in paise. Must be >= 0; the repository requires > 0 and
  /// rejects anything above the payee's outstanding balance.
  IntColumn get amountPaise =>
      integer().customConstraint('NOT NULL CHECK (amount_paise >= 0)')();

  /// Payment method captured at the counter: CASH, UPI or BANK.
  TextColumn get paymentMethod => text().customConstraint(
    "NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK'))",
  )();

  /// Optional free-form note; NULL when blank.
  TextColumn get note => text().nullable()();

  /// Exact UTC instant the money moved (the business timestamp).
  DateTimeColumn get paidAt => dateTime()();

  /// Compensating-entry flag; FALSE for every payment recorded today.
  BoolColumn get reversed => boolean().withDefault(const Constant(false))();

  /// When [reversed] flips true; NULL otherwise.
  DateTimeColumn get reversedAt => dateTime().nullable()();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
