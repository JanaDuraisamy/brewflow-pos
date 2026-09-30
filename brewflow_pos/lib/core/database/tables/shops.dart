import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// Shops — the business context all local data belongs to
///
/// BrewFlow is currently single-shop: exactly one row exists, created once
/// during owner bootstrap. Every future synced entity will carry this id, so
/// multi-device sync (Step 3) can scope data without another migration.
/// Multi-shop switching is deliberately NOT implemented.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_shops_updated_at', columns: {#updatedAt})
class Shops extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business display name; informational until business identity settings
  /// are linked to the shop row.
  TextColumn get name => text()();

  /// Label for this business' receipt numbers (e.g. 'BF-000042', 'FT-000042').
  ///
  /// Per-shop, not per-app: the numbering itself was always isolated in
  /// `sale_sequences` keyed by `(id, shop_id)`, but the *label* was a single
  /// global constant, so a Food Truck sale produced a `BF-` receipt that was
  /// indistinguishable from a Cafe one. The label belongs to the business, so
  /// it lives here and both businesses can be told apart on paper and in
  /// reports.
  ///
  /// The default is written as a LITERAL rather than
  /// `Constant(AppConstants.defaultShopReceiptPrefix)`: drift's schema
  /// exporter compiles a standalone file for the table definitions, so a
  /// reference to app code here fails to resolve and silently degrades the
  /// exported schema. This matches the other `withDefault` columns in this
  /// package. Keep the two in sync.
  TextColumn get receiptPrefix => text().withDefault(const Constant('BF-'))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
