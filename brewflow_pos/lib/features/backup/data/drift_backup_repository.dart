import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/shop_resolver.dart';
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
      // The shop bound to the locally provisioned profile is the authoritative
      // target — the same shop every write stamps via resolveWritableShopId.
      // Resolving it here (instead of the first `shops` row) guarantees the
      // envelope.shopId exactly matches the shopId stamped on every record, so
      // a same-device restore keeps passing the cross-shop guard.
      //
      // Read-only resolution on purpose: exporting must never insert a shop
      // row as a side effect. A device with no provisioned shop yet fails
      // cleanly instead of shipping an empty archive for a phantom shop.
      final shopId = await resolveExistingShopIdOrNull(_db);
      if (shopId == null) {
        throw const UnexpectedBackupFailure();
      }
      final settings = await _settings.load();
      final tables = BackupTables(
        categories: await _selectAllForShop(_db.categories, shopId),
        products: await _selectAllForShop(_db.products, shopId),
        productVariants: await _selectAllForShop(_db.productVariants, shopId),
        customers: await _selectAllForShop(_db.customers, shopId),
        customerPayments: await _selectAllForShop(_db.customerPayments, shopId),
        sales: await _selectAllForShop(_db.sales, shopId),
        saleItems: await _selectAllForShop(_db.saleItems, shopId),
        suppliers: await _selectAllForShop(_db.suppliers, shopId),
        purchases: await _selectAllForShop(_db.purchases, shopId),
        purchaseItems: await _selectAllForShop(_db.purchaseItems, shopId),
        expenses: await _selectAllForShop(_db.expenses, shopId),
        stockMovements: await _selectAllForShop(_db.stockMovements, shopId),
        saleSequences: await _selectAllForShop(_db.saleSequences, shopId),
        purchaseSequences: await _selectAllForShop(
          _db.purchaseSequences,
          shopId,
        ),
      );
      // Consistency guard: every exported business row must belong to the
      // authoritative shop. No one row may reference a different shopId — that
      // would corrupt the archive with mixed-shop data.
      _assertSingleShop(shopId, tables);
      final settingsJson = shopSettingsToJson(settings);
      // The settings block carries the authoritative shop id so the envelope
      // is self-describing: envelope.shopId, settings.shopId and every
      // shop-scoped row must all agree. Verified below before shipping.
      settingsJson[kSettingsShopIdKey] = shopId;
      _assertSettingsShop(shopId, settingsJson);
      return BackupEnvelope(
        shopId: shopId,
        sourceDeviceId: await _deviceIdOrNull(),
        settingsJson: settingsJson,
        tables: tables,
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
    if (envelope.schemaVersion != AppConstants.databaseSchemaVersion) {
      throw const IncompatibleBackupSchemaFailure();
    }
    final localShopExists = await (_db.select(
      _db.shops,
    )..limit(1)).getSingleOrNull();
    if (localShopExists == null) {
      // Nothing was provisioned locally — there is no shop to restore onto.
      throw const CrossShopBackupFailure();
    }
    // Same device can restore a backup it exported: buildBackup stamps the
    // envelope with the authoritative profile-bound shop (the very same shop
    // resolveWritableShopId returns here), so the cross-shop guard passes.
    // Cross-shop archives still fail because their shopId points elsewhere.
    final localShopId = await resolveWritableShopId(_db);
    if (envelope.shopId != localShopId) {
      throw const CrossShopBackupFailure();
    }
    // Ownership is verified row-by-row BEFORE anything is deleted: every
    // shop-scoped row must belong to the envelope's shop (and therefore to
    // this device's shop). A tampered or mixed archive fails here with the
    // current data fully intact — nothing is ever silently overwritten.
    _assertSingleShop(localShopId, envelope.tables);
    // The settings block must agree too (absent on legacy backups, which
    // stay accepted for backward compatibility).
    _assertSettingsShop(localShopId, envelope.settingsJson);
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

  /// Exports ONLY the rows bound to [shopId]. Every business table is
  /// shop-scoped (each row carries a `shopId` column), so filtering here
  /// — instead of dumping every row like the removed [_selectAll] — keeps the
  /// archive to a single shop. This is the root-cause fix: the old export
  /// pulled all rows unconditionally, which mixed rows of different shops into
  /// one envelope and made a same-device restore fail the cross-shop guard.
  Future<List<Map<String, dynamic>>> _selectAllForShop(
    TableInfo<Table, dynamic> table,
    String shopId,
  ) async {
    final rows = await _db.select(table).get();
    return [
      for (final row in rows)
        if (row.toJson()['shopId'] == shopId) row.toJson(),
    ];
  }

  /// Consistency guard run before an export is completed: every exported
  /// business row must belong to the envelope's shop. Should one row reference
  /// a different shopId, the archive would mix two shops and silently corrupt
  /// any later restore — so the export fails instead of shipping it.
  void _assertSingleShop(String shopId, BackupTables tables) {
    void check(List<Map<String, dynamic>> rows) {
      for (final row in rows) {
        if (row['shopId'] != null && row['shopId'] != shopId) {
          throw const CrossShopBackupFailure();
        }
      }
    }

    check(tables.categories);
    check(tables.products);
    check(tables.productVariants);
    check(tables.customers);
    check(tables.customerPayments);
    check(tables.sales);
    check(tables.saleItems);
    check(tables.suppliers);
    check(tables.purchases);
    check(tables.purchaseItems);
    check(tables.expenses);
    check(tables.stockMovements);
    check(tables.saleSequences);
    check(tables.purchaseSequences);
  }

  /// The settings block's shop id must agree with the authoritative shop.
  /// Missing on legacy backups, which stay accepted for backward
  /// compatibility; present-but-different means a foreign or tampered
  /// archive and fails as a cross-shop restore.
  void _assertSettingsShop(String shopId, Map<String, dynamic> settingsJson) {
    final settingsShop = settingsJson[kSettingsShopIdKey];
    if (settingsShop == null) return;
    if (settingsShop != shopId) {
      throw const CrossShopBackupFailure();
    }
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
