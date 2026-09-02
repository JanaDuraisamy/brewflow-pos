import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Customers — retained customer profiles
///
/// Business identity of walk-in and regular customers. The phone number is
/// optional but unique when present (case-insensitive checks live in the
/// customers repository; SQLite UNIQUE allows multiple NULLs, so empty values
/// never collide). Customers are deactivated, never hard-deleted, so future
/// modules (orders, due management) can keep referencing them safely.
///
/// Soft-deactivate semantics mirror [Products] and [Categories]: [isActive]
/// hides the customer from active lists without touching history.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_customers_shop', columns: {#shopId})
@TableIndex(name: 'idx_customers_name', columns: {#name})
@TableIndex(name: 'idx_customers_updated_at', columns: {#shopId, #updatedAt})
class Customers extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this customer.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Customer display name.
  TextColumn get name => text()();

  /// Phone number; optional. Unique when present (SQLite unique indexes
  /// treat NULLs as distinct). Case-insensitive uniqueness is enforced by
  /// the repository before insert/update.
  TextColumn get phone => text().nullable().unique()();

  /// Email address; optional. Not unique — a household or business may
  /// share an inbox.
  TextColumn get email => text().nullable()();

  /// Billing/delivery address; optional.
  TextColumn get address => text().nullable()();

  /// Soft switch to hide a customer without deleting their records.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Membership enrolment. When active — and membership pricing is enabled
  /// globally in settings — the counter charges this customer the member
  /// price of every membership-enabled product/variant.
  BoolColumn get membershipActive =>
      boolean().withDefault(const Constant(false))();

  /// Membership fee snapshot in integer paise (e.g. 5000 = ₹50); optional,
  /// informational, and fully owner-editable. Never a billing rule by
  /// itself — charged prices always come from the product/variant member
  /// prices.
  IntColumn get membershipFeePaise => integer().nullable()();

  /// Honest WhatsApp reachability state reported by a verification provider.
  /// 'UNKNOWN' until a real provider verifies the number; never inferred
  /// from formatting/country code.
  TextColumn get whatsappStatus =>
      text().withDefault(const Constant('UNKNOWN'))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
