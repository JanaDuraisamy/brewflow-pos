import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// Suppliers — retained vendor profiles
///
/// Business identity of the vendors stock is received from. The phone number
/// is optional but unique when present (case-insensitive checks live in the
/// suppliers repository; SQLite UNIQUE allows multiple NULLs, so empty values
/// never collide). Suppliers are deactivated, never hard-deleted, so purchase
/// history can keep referencing them safely.
///
/// Soft-deactivate semantics mirror [Customers], [Products] and [Categories]:
/// [isActive] hides the supplier from active lists without touching history.
/// A purchase may also be recorded without any supplier (walk-in receiving);
/// [Purchases.supplierId] is nullable and RESTRICT keeps history safe.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_suppliers_name', columns: {#name})
@TableIndex(name: 'idx_suppliers_updated_at', columns: {#updatedAt})
class Suppliers extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Supplier display name.
  TextColumn get name => text()();

  /// Phone number; optional. Unique when present (SQLite unique indexes
  /// treat NULLs as distinct). Case-insensitive uniqueness is enforced by
  /// the repository before insert/update.
  TextColumn get phone => text().nullable().unique()();

  /// Email address; optional. Not unique — a business may share an inbox.
  TextColumn get email => text().nullable()();

  /// Billing/delivery address; optional.
  TextColumn get address => text().nullable()();

  /// Optional free-form note about the supplier.
  TextColumn get notes => text().nullable()();

  /// Soft switch to hide a supplier without deleting their records.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
