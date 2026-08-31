import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_repository.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';
import 'package:drift/drift.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Backup Repository
///
/// [buildBackup] snapshots the business tables (products, categories,
/// variants, customers, payments, sales, sale items, suppliers, purchases,
/// purchase items, expenses, stock movements and the receipt/purchase
/// counters) together with the non-sensitive settings. Auth/users, shops,
/// devices, staff permissions and sync tables are never exported.
///
/// [restoreBackup] first validates the envelope (schema version + current
/// shop identity), then replaces the business data in ONE transaction so an
/// interrupted or failed restore leaves no partial state:
///   1. existing business rows are removed children-before-parents
///   2. backup rows are inserted parents-before-children (FK-safe)
/// Settings are written back only after the database commit.
/// ---------------------------------------------------------------------------

final class DriftBackupRepository implements BackupRepository {
  DriftBackupRepository(
    db.AppDatabase database, {
    required SettingsRepository settingsRepository,
  }) : _db = database,
       _settings = settingsRepository;

  static const String tag = 'Backup';

  final db.AppDatabase _db;
  final SettingsRepository _settings;

  @override
  Future<BackupEnvelope> buildBackup() async {
    try {
      final shop = await (_db.select(_db.shops)..limit(1)).getSingleOrNull();
      if (shop == null) {
        throw const UnexpectedBackupFailure();
      }
      final settings = await _settings.load();
      return BackupEnvelope(
        shopId: shop.id,
        sourceDeviceId: await _deviceIdOrNull(),
        settingsJson: shopSettingsToJson(settings),
        tables: BackupTables(
          categories: await _selectAll(_db.categories),
          products: await _selectAll(_db.products),
          productVariants: await _selectAll(_db.productVariants),
          customers: await _selectAll(_db.customers),
          customerPayments: await _selectAll(_db.customerPayments),
          expenses: await _selectAll(_db.expenses),
          sales: await _selectAll(_db.sales),
          saleItems: await _selectAll(_db.saleItems),
          suppliers: await _selectAll(_db.suppliers),
          purchases: await _selectAll(_db.purchases),
          purchaseItems: await _selectAll(_db.purchaseItems),
          stockMovements: await _selectAll(_db.stockMovements),
          saleSequences: await _selectAll(_db.saleSequences),
          purchaseSequences: await _selectAll(_db.purchaseSequences),
        ),
      );
    } on BackupFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'Backup export failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedBackupFailure();
    }
  }

  @override
  Future<void> restoreBackup(BackupEnvelope envelope) async {
    final shop = await (_db.select(_db.shops)..limit(1)).getSingleOrNull();
    if (envelope.schemaVersion != AppConstants.databaseSchemaVersion) {
      throw const IncompatibleBackupSchemaFailure();
    }
    if (shop == null || envelope.shopId != shop.id) {
      throw const CrossShopBackupFailure();
    }
    try {
      await _db.transaction(() async {
        await _clearBusinessTables();
        await _insertTables(envelope.tables);
      });
    } on BackupFailure {
      rethrow;
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'Backup restore failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedBackupFailure();
    }

    final settings = shopSettingsFromJson(envelope.settingsJson);
    if (settings == null) return;
    try {
      await _settings.save(settings);
    } on Object catch (error, stackTrace) {
      AppLog.error(
        'Backup settings restore failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const BackupSettingsRestoreFailure();
    }
  }

  Future<List<Map<String, dynamic>>> _selectAll(
    TableInfo<Table, dynamic> table,
  ) async {
    final rows = await _db.select(table).get();
    return [for (final row in rows) row.toJson()];
  }

  /// Removes every existing business row children-before-parents so no FK
  /// RESTRICT forbids a delete. Auth/shop/device/sync tables stay untouched.
  Future<void> _clearBusinessTables() async {
    await _db.delete(_db.stockMovements).go();
    await _db.delete(_db.purchaseItems).go();
    await _db.delete(_db.purchases).go();
    await _db.delete(_db.saleItems).go();
    await _db.delete(_db.customerPayments).go();
    await _db.delete(_db.sales).go();
    await _db.delete(_db.productVariants).go();
    await _db.delete(_db.products).go();
    await _db.delete(_db.categories).go();
    await _db.delete(_db.expenses).go();
    await _db.delete(_db.customers).go();
    await _db.delete(_db.suppliers).go();
    await _db.delete(_db.saleSequences).go();
    await _db.delete(_db.purchaseSequences).go();
  }

  /// Inserts every backup row parents-before-children so every FK resolves.
  Future<void> _insertTables(BackupTables tables) async {
    await _insertRows(
      _db.categories,
      tables.categories,
      (row) => db.Category.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.suppliers,
      tables.suppliers,
      (row) => db.Supplier.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.customers,
      tables.customers,
      (row) => db.Customer.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.products,
      tables.products,
      (row) => db.Product.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.productVariants,
      tables.productVariants,
      (row) => db.ProductVariant.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.purchases,
      tables.purchases,
      (row) => db.Purchase.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.sales,
      tables.sales,
      (row) => db.Sale.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.purchaseItems,
      tables.purchaseItems,
      (row) => db.PurchaseItem.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.saleItems,
      tables.saleItems,
      (row) => db.SaleItem.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.stockMovements,
      tables.stockMovements,
      (row) => db.StockMovement.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.customerPayments,
      tables.customerPayments,
      (row) => db.CustomerPayment.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.expenses,
      tables.expenses,
      (row) => db.Expense.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.saleSequences,
      tables.saleSequences,
      (row) => db.SaleSequence.fromJson(row).toCompanion(false),
    );
    await _insertRows(
      _db.purchaseSequences,
      tables.purchaseSequences,
      (row) => db.PurchaseSequence.fromJson(row).toCompanion(false),
    );
  }

  /// Decodes one table of backup rows through the generated Drift codecs and
  /// inserts them. A malformed row fails as [CorruptBackupFailure]; FK or
  /// constraint violations propagate to roll back the whole restore.
  Future<void> _insertRows<D extends DataClass, C extends Insertable<D>>(
    TableInfo<Table, D> table,
    List<Map<String, dynamic>> rows,
    C Function(Map<String, dynamic>) companion,
  ) async {
    for (final row in rows) {
      try {
        await _db.into(table).insert(companion(row));
      } on FormatException {
        throw const CorruptBackupFailure();
      } on TypeError {
        throw const CorruptBackupFailure();
      }
    }
  }

  Future<String?> _deviceIdOrNull() async {
    try {
      return (await DeviceIdentity.resolve()).value;
    } on Object {
      return null;
    }
  }
}
