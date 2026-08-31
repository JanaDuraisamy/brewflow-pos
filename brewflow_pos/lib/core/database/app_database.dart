import 'dart:io';

import 'package:brewflow_pos/config/constants.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import 'migrations/migrations.dart';
import 'tables/categories.dart';
import 'tables/customer_payments.dart';
import 'tables/customers.dart';
import 'tables/expenses.dart';
import 'tables/products.dart';
import 'tables/product_variants.dart';
import 'tables/purchase_items.dart';
import 'tables/purchase_sequences.dart';
import 'tables/purchases.dart';
import 'tables/sale_items.dart';
import 'tables/sale_sequences.dart';
import 'tables/sales.dart';
import 'tables/devices.dart';
import 'tables/shops.dart';
import 'tables/sync_outbox.dart';
import 'tables/sync_state.dart';
import 'tables/staff_permissions.dart';
import 'tables/stock_movements.dart';
import 'tables/suppliers.dart';
import 'tables/users.dart';

part 'app_database.g.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Local Database (Drift)
///
/// Offline-first local source of truth for business data.
///
/// Conventions:
/// - Identifiers: UUID v4 strings generated on device.
/// - Timestamps: UTC `DateTime`, stored as ISO-8601 text
///   (`store_date_time_values_as_text: true` in build.yaml) — lexicographic
///   ordering equals chronological ordering, and sub-second precision is
///   preserved for future sync conflict handling.
/// - Money: integer minor units (paise), see [Products].
/// - Foreign keys are enforced via PRAGMA in [AppDatabase.migration].
///
/// The executor runs in a background isolate (`createInBackground`) so
/// database I/O never blocks the UI thread.
///
/// Instantiate through [AppDatabase.open]. Intended to be wired into
/// bootstrap/Riverpod in later stages — nothing else initializes it yet.
/// ---------------------------------------------------------------------------
@DriftDatabase(
  tables: [
    Users,
    Shops,
    Devices,
    SyncOutbox,
    SyncState,
    StaffPermissions,
    Categories,
    Products,
    ProductVariants,
    Customers,
    CustomerPayments,
    Expenses,
    Sales,
    SaleItems,
    SaleSequences,
    StockMovements,
    Suppliers,
    Purchases,
    PurchaseItems,
    PurchaseSequences,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Opens the production database file in the app documents directory.
  AppDatabase.open() : super(_openConnection());

  @override
  int get schemaVersion => AppConstants.databaseSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: AppMigrations.upgrade,
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() => LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, AppConstants.databaseFileName));
    return NativeDatabase.createInBackground(file);
  });
}
