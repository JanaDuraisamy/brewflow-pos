import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/backup/data/drift_backup_repository.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_settings_repository.dart';

/// Backup engine tests against a real in-memory Drift database: migrations,
/// CHECK constraints and FOREIGN KEY ordering behave exactly like production.
void main() {
  late db.AppDatabase source;
  late db.AppDatabase target;
  late FakeSettingsRepository sourceSettings;
  late FakeSettingsRepository targetSettings;
  late DriftBackupRepository repository;

  final at = DateTime.utc(2026, 8, 31, 10, 0);

  setUp(() {
    source = db.AppDatabase(NativeDatabase.memory());
    target = db.AppDatabase(NativeDatabase.memory());
    sourceSettings = FakeSettingsRepository()
      ..stored = const ShopSettings(
        shopName: 'Source Shop',
        lowStockThreshold: 7,
        theme: ThemePreference.dark,
      );
    targetSettings = FakeSettingsRepository();
    repository = DriftBackupRepository(
      source,
      settingsRepository: sourceSettings,
    );
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  Future<void> seedShop(db.AppDatabase database, String shopId) async {
    await database
        .into(database.shops)
        .insert(
          db.Shop(
            id: shopId,
            name: 'Shop',
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
  }

  /// Seeds one complete sale graph (category → product → customer → sale →
  /// sale item + supplier + stock movement + expense + receipt counter).
  Future<void> seedSourceData(db.AppDatabase database) async {
    await database
        .into(database.categories)
        .insert(
          db.Category(
            id: 'cat-1',
            shopId: 'shop-1',
            name: 'Beverages',
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.products)
        .insert(
          db.Product(
            id: 'prod-1',
            shopId: 'shop-1',
            categoryId: 'cat-1',
            name: 'Filter Coffee',
            sku: null,
            sellingPricePaise: 12000,
            costPricePaise: null,
            stockQuantity: 5,
            stockUnit: 'COUNT',
            lowStockMode: 'USE_DEFAULT',
            lowStockThreshold: null,
            membershipEnabled: false,
            memberPricePaise: null,
            imagePath: null,
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.customers)
        .insert(
          db.Customer(
            id: 'cust-1',
            shopId: 'shop-1',
            name: 'Aarthi',
            phone: null,
            email: null,
            address: null,
            isActive: true,
            membershipActive: false,
            membershipFeePaise: null,
            whatsappStatus: 'UNKNOWN',
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.sales)
        .insert(
          db.Sale(
            id: 'sale-1',
            shopId: 'shop-1',
            customerId: 'cust-1',
            receiptNumber: 'BF-000042',
            subtotalPaise: 12000,
            totalPaise: 12000,
            offerDiscountPaise: 0,
            paymentMethod: 'CASH',
            paymentStatus: 'PAID',
            voided: false,
            voidedAt: null,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.saleItems)
        .insert(
          db.SaleItem(
            id: 'si-1',
            shopId: 'shop-1',
            saleId: 'sale-1',
            productId: 'prod-1',
            variantId: null,
            productName: 'Filter Coffee',
            variantName: null,
            sku: null,
            unitPricePaise: 12000,
            quantity: 1,
            lineTotalPaise: 12000,
            offerDiscountPaise: 0,
            appliedOfferId: null,
            appliedOfferName: null,
            appliedOfferType: null,
          ).toCompanion(false),
        );
    await database
        .into(database.stockMovements)
        .insert(
          db.StockMovement(
            id: 'sm-1',
            shopId: 'shop-1',
            productId: 'prod-1',
            variantId: null,
            movementType: 'SALE',
            quantity: -1,
            stockBefore: 6,
            stockAfter: 5,
            reason: null,
            note: null,
            referenceType: 'SALE',
            referenceId: 'sale-1',
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.suppliers)
        .insert(
          db.Supplier(
            id: 'sup-1',
            shopId: 'shop-1',
            name: 'Green Beans Co',
            phone: null,
            email: null,
            address: null,
            notes: null,
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.expenses)
        .insert(
          db.Expense(
            id: 'exp-1',
            shopId: 'shop-1',
            name: 'Electricity',
            amountPaise: 150000,
            category: 'UTILITIES',
            paymentMethod: 'UPI',
            paymentStatus: 'PAID',
            expenseDate: at,
            note: null,
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.saleSequences)
        .insert(
          db.SaleSequence(
            id: 'receipt',
            shopId: 'shop-1',
            nextValue: 42,
          ).toCompanion(false),
        );
  }

  /// Seeds a small, clearly different dataset on the target database.
  Future<void> seedTargetData(db.AppDatabase database) async {
    await database
        .into(database.categories)
        .insert(
          db.Category(
            id: 'cat-9',
            shopId: 'shop-1',
            name: 'Old Data',
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
    await database
        .into(database.products)
        .insert(
          db.Product(
            id: 'old-prod',
            shopId: 'shop-1',
            categoryId: 'cat-9',
            name: 'Stale Item',
            sellingPricePaise: 500,
            stockQuantity: 1,
            stockUnit: 'COUNT',
            lowStockMode: 'USE_DEFAULT',
            membershipEnabled: false,
            isActive: true,
            createdAt: at,
            updatedAt: at,
          ).toCompanion(false),
        );
  }

  Future<BackupEnvelope> buildBackup(DriftBackupRepository repository) =>
      repository.buildBackup();

  group('buildBackup', () {
    test('snapshots the whole business graph under the current shop', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);

      final envelope = await buildBackup(repository);

      expect(envelope.shopId, 'shop-1');
      final summary = envelope.tables.summary;
      expect(summary.categories, 1);
      expect(summary.products, 1);
      expect(summary.customers, 1);
      expect(summary.sales, 1);
      expect(summary.saleItems, 1);
      expect(summary.stockMovements, 1);
      expect(summary.suppliers, 1);
      expect(summary.expenses, 1);
      expect(summary.saleSequences, 1);
      expect(envelope.tables.sales.single['receiptNumber'], 'BF-000042');
      expect(envelope.tables.saleSequences.single['nextValue'], 42);
    });

    test('includes the non-sensitive shop settings', () async {
      await seedShop(source, 'shop-1');
      final envelope = await buildBackup(repository);

      expect(envelope.settingsJson['shopName'], 'Source Shop');
      expect(envelope.settingsJson['lowStockThreshold'], 7);
      expect(envelope.settingsJson['theme'], 'dark');
    });

    test('fails cleanly when no shop exists yet', () async {
      await expectLater(
        buildBackup(repository),
        throwsA(isA<UnexpectedBackupFailure>()),
      );
    });
  });

  group('restoreBackup', () {
    test('replaces the target data with the backup, preserving IDs', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      await seedTargetData(target);

      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await targetRepo.restoreBackup(envelope);

      final categories = await target.select(target.categories).get();
      expect(categories, hasLength(1));
      expect(categories.single.id, 'cat-1');
      expect(categories.single.name, 'Beverages');

      final products = await target.select(target.products).get();
      expect(products.single.id, 'prod-1');
      expect(products.single.stockQuantity, 5);
      expect(products.single.stockUnit, 'COUNT');

      final customers = await target.select(target.customers).get();
      expect(customers.single.name, 'Aarthi');

      final sales = await target.select(target.sales).get();
      expect(sales.single.receiptNumber, 'BF-000042');
      expect(sales.single.totalPaise, 12000);

      final items = await target.select(target.saleItems).get();
      expect(items.single.productName, 'Filter Coffee');

      final movements = await target.select(target.stockMovements).get();
      expect(movements.single.stockBefore, 6);
      expect(movements.single.movementType, 'SALE');

      final suppliers = await target.select(target.suppliers).get();
      expect(suppliers.single.name, 'Green Beans Co');

      final expenses = await target.select(target.expenses).get();
      expect(expenses.single.name, 'Electricity');

      // The target shop row itself is never touched by a restore.
      final shops = await target.select(target.shops).get();
      expect(shops, hasLength(1));
      expect(shops.single.id, 'shop-1');
      expect(shops.single.name, 'Shop');
    });

    test('preserves the receipt counter so numbers do not restart', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      await seedTargetData(target);
      await target
          .into(target.saleSequences)
          .insert(
            db.SaleSequence(
              id: 'receipt',
              shopId: 'shop-1',
              nextValue: 999,
            ).toCompanion(false),
          );

      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await targetRepo.restoreBackup(envelope);

      final sequences = await target.select(target.saleSequences).get();
      expect(sequences.single.nextValue, 42);
    });

    test('writes backup settings back after the data commit', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await targetRepo.restoreBackup(envelope);

      expect(targetSettings.saved, hasLength(1));
      expect(targetSettings.saved.single.shopName, 'Source Shop');
      expect(targetSettings.saved.single.lowStockThreshold, 7);
      expect(targetSettings.saved.single.theme, ThemePreference.dark);
      expect(
        targetSettings.stored.appDisplayName,
        ShopSettings.defaults().appDisplayName,
      );
    });

    test('an empty backup restores an empty shop (wipe semantics)', () async {
      await seedShop(source, 'shop-1');
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      await seedTargetData(target);

      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await targetRepo.restoreBackup(envelope);

      expect(await target.select(target.products).get(), isEmpty);
      expect(await target.select(target.categories).get(), isEmpty);
    });

    test(
      'rejects a backup from a different shop and leaves data intact',
      () async {
        await seedShop(source, 'shop-1');
        await seedSourceData(source);
        final envelope = await buildBackup(repository);
        final crossShop = BackupEnvelope(
          shopId: 'shop-other',
          tables: envelope.tables,
        );

        await seedShop(target, 'shop-1');
        await seedTargetData(target);
        final targetRepo = DriftBackupRepository(
          target,
          settingsRepository: targetSettings,
        );

        await expectLater(
          targetRepo.restoreBackup(crossShop),
          throwsA(isA<CrossShopBackupFailure>()),
        );
        expect(await target.select(target.products).get(), hasLength(1));
        expect(
          (await target.select(target.products).get()).single.name,
          'Stale Item',
        );
        expect(targetSettings.saved, isEmpty);
      },
    );

    test('rejects a mismatched schema version', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = BackupEnvelope(
        shopId: 'shop-1',
        schemaVersion: 99,
        tables: BackupTables(
          products: [
            {'id': 'x', 'name': 'leak'},
          ],
        ),
      );

      await seedShop(target, 'shop-1');
      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await expectLater(
        targetRepo.restoreBackup(envelope),
        throwsA(isA<IncompatibleBackupSchemaFailure>()),
      );
    });

    test('rejects when the target shop row is missing', () async {
      await seedShop(source, 'shop-1');
      final envelope = await buildBackup(repository);

      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );
      await expectLater(
        targetRepo.restoreBackup(envelope),
        throwsA(isA<CrossShopBackupFailure>()),
      );
    });

    test('a corrupt row rolls back completely — no partial restore', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      await seedTargetData(target);
      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: targetSettings,
      );

      final corrupt = BackupEnvelope(
        shopId: 'shop-1',
        tables: BackupTables(
          categories: [
            {'id': 'cat-corrupt'}, // missing required 'name' column
          ],
          products: envelope.tables.products,
        ),
      );

      await expectLater(
        targetRepo.restoreBackup(corrupt),
        throwsA(isA<CorruptBackupFailure>()),
      );

      // The transaction rolled back: original data is fully intact.
      expect(await target.select(target.categories).get(), hasLength(1));
      expect(
        (await target.select(target.categories).get()).single.name,
        'Old Data',
      );
      expect(await target.select(target.products).get(), hasLength(1));
      expect(
        ((await target.select(target.products).get()).single).name,
        'Stale Item',
      );
      expect(targetSettings.saved, isEmpty);
    });

    test('a settings write failure does not touch the restored data', () async {
      await seedShop(source, 'shop-1');
      await seedSourceData(source);
      final envelope = await buildBackup(repository);

      await seedShop(target, 'shop-1');
      final failingSettings = FakeSettingsRepository()
        ..saveError = StateError('prefs unavailable');
      final targetRepo = DriftBackupRepository(
        target,
        settingsRepository: failingSettings,
      );

      await expectLater(
        targetRepo.restoreBackup(envelope),
        throwsA(isA<BackupSettingsRestoreFailure>()),
      );
      // Data commit already happened and stays.
      expect(await target.select(target.products).get(), hasLength(1));
      expect(
        (await target.select(target.products).get()).single.name,
        'Filter Coffee',
      );
    });
  });
}
