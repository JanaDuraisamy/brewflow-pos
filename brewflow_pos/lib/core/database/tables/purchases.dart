import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'purchase_sequences.dart';
import 'shops.dart';
import 'suppliers.dart';

/// ---------------------------------------------------------------------------
/// Purchases — one row per completed stock receiving transaction
///
/// - Money is stored as INTEGER minor units (paise), see [Products].
/// - [Purchases.purchaseNumber] is the human-readable reference
///   (e.g. 'PUR-000012') produced by the counter in [PurchaseSequences].
/// - [Purchases.supplierId] is NULL for walk-in receiving; supplier-linked
///   purchases reference a real profile. Suppliers are never hard-deleted,
///   and the RESTRICT FK is the backstop that keeps receiving history linked
///   to its owner.
/// - [Purchases.createdAt] is the UTC receiving timestamp; it doubles as the
///   purchase date (there is no separate "ordered on" concept — receiving
///   and purchase happen in the same transaction).
/// - Payments/credit terms are out of scope for now: the header records the
///   goods value only, and cash/UPI/BANK handling stays in billing.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_purchases_shop', columns: {#shopId})
@TableIndex(name: 'idx_purchases_created_at', columns: {#shopId, #createdAt})
@TableIndex(name: 'idx_purchases_supplier_id', columns: {#shopId, #supplierId})
class Purchases extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this purchase.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Owning supplier for supplier-linked purchases; NULL for walk-ins.
  /// Deleting a supplier with purchase history is rejected (RESTRICT).
  TextColumn get supplierId => text().nullable().references(
    Suppliers,
    #id,
    onDelete: KeyAction.restrict,
  )();

  /// Human-readable purchase reference; unique per shop.
  TextColumn get purchaseNumber => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, purchaseNumber},
  ];

  /// Sum of line totals in paise, before any adjustments. Must be >= 0.
  IntColumn get subtotalPaise =>
      integer().customConstraint('NOT NULL CHECK (subtotal_paise >= 0)')();

  /// Amount recorded in paise. Equals the subtotal (no discounts/taxes yet).
  IntColumn get totalPaise =>
      integer().customConstraint('NOT NULL CHECK (total_paise >= 0)')();

  /// Optional free-form note about the purchase.
  TextColumn get notes => text().nullable()();

  /// UTC timestamp of the purchase (the receiving transaction).
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
