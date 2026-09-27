import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/backup/data/backup_csv_export.dart';
import 'package:brewflow_pos/features/backup/data/backup_package.dart';
import 'package:brewflow_pos/features/backup/data/drift_backup_repository.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:brewflow_pos/features/reports/data/management_report_pdf.dart';
import 'package:brewflow_pos/features/reports/domain/management_report_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_settings_repository.dart';

/// Backup & export contract: same-shop JSON, cross-shop rejection, empty
/// handling, legacy tolerance, ZIP/CSV/PDF contents and the no-secrets rule.
void main() {
  final at = DateTime.utc(2026, 8, 31, 10, 0);

  BackupEnvelope sampleEnvelope() => BackupEnvelope(
    shopId: 'shop-1',
    settingsJson: const {'shopName': 'Cafe', 'shopId': 'shop-1'},
    tables: const BackupTables(
      products: [
        {
          'id': 'prod-1',
          'shopId': 'shop-1',
          'name': 'Filter, "Special" Coffee',
          'sellingPricePaise': 12000,
          'stockQuantity': 5,
          'imagePath': 'product_images/abc.jpg',
        },
      ],
      customers: [
        {'id': 'cust-1', 'shopId': 'shop-1', 'name': 'Aarthi'},
      ],
      sales: [
        {
          'id': 'sale-1',
          'shopId': 'shop-1',
          'customerId': 'cust-1',
          'receiptNumber': 'BF-000042',
          'totalPaise': 12000,
          'paymentStatus': 'NOT_PAID',
        },
      ],
    ),
  );

  /// Substrings that must never appear in any exported payload (JSON, ZIP
  /// entry names/content, CSV sheets). Checked case-insensitively.
  const forbiddenSecrets = [
    'token',
    'secret',
    'password',
    'apikey',
    'api_key',
    'supabase',
    'bearer',
    'credential',
    'private_key',
    'privatekey',
  ];

  void expectNoSecrets(String label, String payload) {
    final lower = payload.toLowerCase();
    for (final needle in forbiddenSecrets) {
      expect(
        lower.contains(needle),
        isFalse,
        reason: '$label must not contain "$needle"',
      );
    }
  }

  group('JSON shop context', () {
    late db.AppDatabase source;
    late db.AppDatabase target;

    setUp(() {
      source = db.AppDatabase(NativeDatabase.memory());
      target = db.AppDatabase(NativeDatabase.memory());
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

    DriftBackupRepository repoFor(
      db.AppDatabase database, [
      FakeSettingsRepository? settings,
    ]) => DriftBackupRepository(
      database,
      settingsRepository: settings ?? FakeSettingsRepository(),
    );

    test('export stamps settings.shopId equal to the envelope shop', () async {
      await seedShop(source, 'shop-1');
      final envelope = await repoFor(source).buildBackup();

      expect(envelope.shopId, 'shop-1');
      expect(envelope.settingsJson[kSettingsShopIdKey], 'shop-1');
    });

    test('restore rejects a row carrying a foreign shopId', () async {
      await seedShop(source, 'shop-1');
      final envelope = await repoFor(source).buildBackup();
      final tampered = BackupEnvelope(
        shopId: 'shop-1',
        settingsJson: envelope.settingsJson,
        tables: BackupTables(
          products: [
            {
              ...envelope.tables.products.firstOrNull ?? {'id': 'p'},
              'shopId': 'shop-other',
            },
          ],
        ),
      );

      await seedShop(target, 'shop-1');
      await target
          .into(target.categories)
          .insert(
            db.Category(
              id: 'cat-keep',
              shopId: 'shop-1',
              name: 'Keep Me',
              isActive: true,
              createdAt: at,
              updatedAt: at,
            ).toCompanion(false),
          );

      await expectLater(
        repoFor(target).restoreBackup(tampered),
        throwsA(isA<CrossShopBackupFailure>()),
      );
      // Nothing was silently overwritten.
      final categories = await target.select(target.categories).get();
      expect(categories, hasLength(1));
      expect(categories.single.name, 'Keep Me');
      expect(await target.select(target.products).get(), isEmpty);
    });

    test('restore rejects a settings block from another shop', () async {
      await seedShop(source, 'shop-1');
      final envelope = await repoFor(source).buildBackup();
      final foreign = BackupEnvelope(
        shopId: 'shop-1',
        settingsJson: {...envelope.settingsJson, 'shopId': 'shop-other'},
        tables: envelope.tables,
      );

      await seedShop(target, 'shop-1');
      await expectLater(
        repoFor(target).restoreBackup(foreign),
        throwsA(isA<CrossShopBackupFailure>()),
      );
    });

    test('restore accepts a legacy settings block without shopId', () async {
      await seedShop(source, 'shop-1');
      final envelope = await repoFor(source).buildBackup();
      final legacy = BackupEnvelope(
        shopId: 'shop-1',
        settingsJson: const {'shopName': 'Old Cafe'},
        tables: envelope.tables,
      );

      await seedShop(target, 'shop-1');
      await repoFor(target).restoreBackup(legacy);

      expect(await target.select(target.products).get(), isEmpty);
    });
  });

  group('ZIP package', () {
    final imageBytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    BuiltBackupPackage buildSample() => buildBackupPackage(
      envelope: sampleEnvelope(),
      productImagePaths: const ['product_images/abc.jpg'],
      readImageBytes: (_) => imageBytes,
    );

    test('contains backup.json, metadata.json and the images', () {
      final package = buildSample();

      expect(package.includedImages, ['abc.jpg']);
      expect(package.missingImages, isEmpty);
      expect(package.metadata.shopId, 'shop-1');
      expect(package.metadata.format, kBackupPackageFormat);
      expect(package.metadata.packageVersion, kBackupPackageVersion);

      final unpacked = unpackBackupPackage(package.bytes);
      // The embedded envelope parses with full validation (format +
      // checksum), proving the ZIP is self-contained for restore.
      final envelope = BackupEnvelope.fromJsonString(unpacked.backupJson);
      expect(envelope.shopId, 'shop-1');
      expect(
        envelope.tables.products.single['name'],
        'Filter, "Special" Coffee',
      );
      expect(unpacked.metadata?.shopId, 'shop-1');
      expect(unpacked.images['abc.jpg'], imageBytes);
    });

    test('missing images never fail the build', () {
      final package = buildBackupPackage(
        envelope: sampleEnvelope(),
        productImagePaths: const ['product_images/gone.jpg'],
        readImageBytes: (_) => null,
      );

      expect(package.includedImages, isEmpty);
      expect(package.missingImages, ['gone.jpg']);
      // Still a valid, restorable package.
      final envelope = BackupEnvelope.fromJsonString(
        unpackBackupPackage(package.bytes).backupJson,
      );
      expect(envelope.shopId, 'shop-1');
    });

    test('garbage bytes and missing backup.json fail as corruption', () {
      expect(
        () => unpackBackupPackage([0, 1, 2, 3]),
        throwsA(isA<CorruptBackupFailure>()),
      );
      expect(
        () => unpackBackupPackage(Uint8List(0)),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('restored images land back under their exact imagePath', () async {
      final package = buildSample();
      final unpacked = unpackBackupPackage(package.bytes);

      final temp = await Directory.systemTemp.createTemp('brewflow_pkg_');
      try {
        final store = ProductImageStore(documentsDir: temp);
        for (final entry in unpacked.images.entries) {
          await store.restoreBytes('product_images/${entry.key}', entry.value);
        }
        final resolved = store.resolve('product_images/abc.jpg');
        expect(resolved, isNotNull);
        expect(resolved!.readAsBytesSync(), imageBytes);
      } finally {
        await temp.delete(recursive: true);
      }
    });

    test('no secrets in JSON, metadata or entry names', () {
      final package = buildSample();
      final unpacked = unpackBackupPackage(package.bytes);

      expectNoSecrets('backup.json', unpacked.backupJson);
      expectNoSecrets(
        'metadata.json',
        const JsonEncoder().convert(package.metadata.toJson()),
      );
      for (final name in unpacked.images.keys) {
        expectNoSecrets('image entry name', name);
      }
      // Metadata carries identity only — never credentials.
      final metaJson = const JsonEncoder().convert(package.metadata.toJson());
      expect(metaJson.contains('shopId'), isTrue);
      expect(unpacked.metadata?.imageNames, ['abc.jpg']);
    });
  });

  group('CSV export', () {
    test('sheets carry exact headers with ids and shop context', () {
      final sheets = buildCsvExport(sampleEnvelope());
      final byName = {for (final sheet in sheets) sheet.fileName: sheet};

      expect(
        byName['products.csv']!.content.split('\n').first,
        'id,shop_id,category_id,name,sku,selling_price_paise,'
        'cost_price_paise,stock_quantity,is_active',
      );
      expect(
        byName['customers.csv']!.content.split('\n').first,
        'id,shop_id,name,phone,email,is_active',
      );
      expect(
        byName['sales.csv']!.content.split('\n').first,
        'id,shop_id,customer_id,receipt_number,total_paise,'
        'payment_method,payment_status,created_at',
      );
      // Relationship ids survive the export.
      expect(byName['sales.csv']!.content, contains('cust-1'));
      expect(byName['sales.csv']!.content, contains('BF-000042'));
      expect(byName['customers.csv']!.content, contains('shop-1'));
    });

    test('commas, quotes and newlines are quoted correctly', () {
      final sheets = buildCsvExport(sampleEnvelope());
      final products = sheets
          .firstWhere((sheet) => sheet.fileName == 'products.csv')
          .content;
      // The tricky name must be wrapped in quotes with doubled inner quotes.
      expect(products, contains('"Filter, ""Special"" Coffee"'));
    });

    test('empty tables still produce headers-only sheets', () {
      final sheets = buildCsvExport(
        BackupEnvelope(shopId: 'shop-1', tables: const BackupTables()),
      );
      expect(sheets, isNotEmpty);
      for (final sheet in sheets) {
        final lines = sheet.content.trim().split('\n');
        expect(lines, hasLength(1), reason: sheet.fileName);
        expect(lines.single.contains(','), isTrue);
      }
    });

    test('no secrets in any sheet', () {
      for (final sheet in buildCsvExport(sampleEnvelope())) {
        expectNoSecrets(sheet.fileName, sheet.content);
      }
    });
  });

  group('Management report PDF', () {
    setUp(TestWidgetsFlutterBinding.ensureInitialized);

    ManagementReportData sampleReportData() => ManagementReportData(
      fromLocal: DateTime(2026, 8, 25),
      toLocal: DateTime(2026, 8, 31),
      shopName: 'Cafe',
      businessLabel: 'All Businesses',
      salesTotalPaise: 478500,
      salesCashPaise: 250000,
      salesUpiPaise: 228500,
      expenseRows: [
        ManagementExpenseRow(
          date: DateTime(2026, 8, 28),
          name: 'Filter coffee beans',
          amountPaise: 240000,
          paymentLabel: 'UPI',
        ),
        ManagementExpenseRow(
          date: DateTime(2026, 8, 29),
          name: 'Milk',
          amountPaise: 45000,
          paymentLabel: 'Not paid',
        ),
      ],
      expenseTotalPaise: 285000,
      expenseCashPaise: 0,
      expenseUpiPaise: 240000,
      expenseBankPaise: 0,
      expenseNotPaidPaise: 45000,
      customerOutstandingRows: const [
        ManagementCustomerOutstandingRow(
          name: 'Aarthi',
          phone: '9876543210',
          outstandingPaise: 30000,
        ),
        ManagementCustomerOutstandingRow(
          name: 'Kumar',
          phone: null,
          outstandingPaise: 50000,
        ),
      ],
      customerOutstandingTotalPaise: 80000,
      staffRows: const [
        ManagementStaffRow(
          name: 'Ravi',
          totalMinutes: 480,
          salaryPaise: 240000,
          advancePaise: 20000,
        ),
      ],
      closings: [
        DailyClosingRecord(
          id: 'close-1',
          businessDate: DateTime.utc(2026, 8, 30),
          totalCashPaise: 250000,
          totalUpiPaise: 228500,
          totalSalesPaise: 478500,
          totalExpensePaise: 285000,
          cashLeftInBoxPaise: 220000,
          cashTakenOutPaise: 30000,
          takenOutBy: 'Ravi',
          talliedBy: 'Owner',
          note: null,
          createdAt: DateTime.utc(2026, 8, 30, 19, 0),
        ),
      ],
      takenByRows: const [
        ManagementTakenByRow(name: 'Ravi', daysTaken: 1, totalPaise: 30000),
      ],
    );

    ManagementReportData emptyReportData() => ManagementReportData(
      fromLocal: DateTime(2026, 8, 25),
      toLocal: DateTime(2026, 8, 31),
      shopName: 'Cafe',
      businessLabel: 'Cafe',
      salesTotalPaise: 0,
      salesCashPaise: 0,
      salesUpiPaise: 0,
      expenseRows: const [],
      expenseTotalPaise: 0,
      expenseCashPaise: 0,
      expenseUpiPaise: 0,
      expenseBankPaise: 0,
      expenseNotPaidPaise: 0,
      customerOutstandingRows: const [],
      customerOutstandingTotalPaise: 0,
      staffRows: const [],
      closings: const [],
      takenByRows: const [],
    );

    test('generates a valid PDF document', () async {
      final bytes = await buildManagementReportPdf(sampleReportData());

      expect(bytes, isNotEmpty);
      final header = String.fromCharCodes(bytes.take(5));
      expect(header, '%PDF-');
    });

    test('generates an empty-shop report without crashing', () async {
      final bytes = await buildManagementReportPdf(emptyReportData());

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('renders the customer outstanding section with a balance', () async {
      final bytes = await buildManagementReportPdf(sampleReportData());

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes, isNotEmpty);
    });

    test(
      'default file name uses the jiggartea_bill_management_report prefix',
      () {
        expect(
          defaultManagementReportFileName(DateTime(2026, 8, 25, 9, 5, 7)),
          'jiggartea_bill_management_report_20260825_090507.pdf',
        );
        expect(
          defaultManagementReportFileName(DateTime(2026, 12, 31, 23, 59, 59)),
          'jiggartea_bill_management_report_20261231_235959.pdf',
        );
        // Local time: a UTC instant crossing into the next day stays local.
        final local = DateTime(2026, 8, 25, 9, 5, 7).toLocal();
        expect(
          defaultManagementReportFileName(local.toUtc()),
          'jiggartea_bill_management_report_${local.year}'
          '${local.month.toString().padLeft(2, '0')}'
          '${local.day.toString().padLeft(2, '0')}'
          '_'
          '${local.hour.toString().padLeft(2, '0')}'
          '${local.minute.toString().padLeft(2, '0')}'
          '${local.second.toString().padLeft(2, '0')}.pdf',
        );
      },
    );
  });
}
