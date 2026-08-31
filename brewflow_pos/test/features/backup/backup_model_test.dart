import 'dart:convert';

import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const settingsJson = <String, dynamic>{
    'shopName': 'Cafe Marina',
    'appDisplayName': 'Marina POS',
    'lowStockThreshold': 3,
    'theme': 'dark',
    'membershipEnabled': true,
  };

  BackupTables tables() => const BackupTables(
    categories: [
      {'id': 'cat-1', 'name': 'Beverages', 'isActive': true},
    ],
    products: [
      {
        'id': 'prod-1',
        'categoryId': 'cat-1',
        'name': 'Filter Coffee',
        'sellingPricePaise': 12000,
        'stockQuantity': 5,
      },
    ],
    saleSequences: [
      {'id': 'receipt', 'nextValue': 42},
    ],
  );

  BackupEnvelope envelope() => BackupEnvelope(
    shopId: 'shop-1',
    sourceDeviceId: ' device-1 ',
    settingsJson: settingsJson,
    tables: tables(),
  );

  group('encode / decode round trip', () {
    test('preserves header, settings and table rows', () {
      final decoded = BackupEnvelope.fromJsonString(envelope().encodeJson());

      expect(decoded.format, kBackupFormat);
      expect(decoded.backupVersion, kBackupVersion);
      expect(decoded.shopId, 'shop-1');
      expect(decoded.sourceDeviceId, 'device-1');
      expect(decoded.schemaVersion, AppConstants.databaseSchemaVersion);
      expect(decoded.settingsJson['shopName'], 'Cafe Marina');
      expect(decoded.tables.summary.categories, 1);
      expect(decoded.tables.summary.products, 1);
      expect(decoded.tables.summary.saleSequences, 1);
      expect(decoded.tables.products.single['name'], 'Filter Coffee');
      expect(decoded.tables.categories.single['id'], 'cat-1');
    });

    test('round trips through a toJson map without loss', () {
      final decoded = BackupEnvelope.fromJson(envelope().toJson());
      expect(decoded.shopId, 'shop-1');
      expect(decoded.tables.products, tables().products);
    });
  });

  group('structural validation', () {
    test('rejects a non-BrewFlow document', () {
      expect(
        () => BackupEnvelope.fromJsonString(
          jsonEncode({'format': 'something.else'}),
        ),
        throwsA(isA<InvalidBackupFormatFailure>()),
      );
    });

    test('rejects an unknown envelope layout (newer backup tool)', () {
      final raw = jsonEncode({
        ...envelope().toJson(),
        'backupVersion': kBackupVersion + 1,
      });
      expect(
        () => BackupEnvelope.fromJsonString(raw),
        throwsA(isA<IncompatibleBackupSchemaFailure>()),
      );
    });

    test('rejects malformed JSON as corruption', () {
      expect(
        () => BackupEnvelope.fromJsonString('{not json'),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects a non-object root as corruption', () {
      expect(
        () => BackupEnvelope.fromJsonString('[1, 2, 3]'),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects a missing or empty shopId', () {
      final noShop = Map<String, dynamic>.from(envelope().toJson())
        ..remove('shopId');
      expect(
        () => BackupEnvelope.fromJson(noShop),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects a wrong-typed schemaVersion', () {
      final badSchema = Map<String, dynamic>.from(envelope().toJson())
        ..['schemaVersion'] = '14';
      expect(
        () => BackupEnvelope.fromJson(badSchema),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects a wrong-typed table container', () {
      final badData = Map<String, dynamic>.from(envelope().toJson());
      (badData['data'] as Map<String, dynamic>)['products'] = 'not-a-list';
      expect(
        () => BackupEnvelope.fromJson(badData),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects non-map table rows', () {
      final badRows = Map<String, dynamic>.from(envelope().toJson());
      (badRows['data'] as Map<String, dynamic>)['products'] = ['not-a-map'];
      expect(
        () => BackupEnvelope.fromJson(badRows),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });

    test('rejects a damaged settings block', () {
      final badSettings = Map<String, dynamic>.from(envelope().toJson())
        ..['settings'] = 'oops';
      expect(
        () => BackupEnvelope.fromJson(badSettings),
        throwsA(isA<CorruptBackupFailure>()),
      );
    });
  });

  group('tolerance', () {
    test('missing table keys and settings decode to empty containers', () {
      final minimal = {
        'format': kBackupFormat,
        'backupVersion': kBackupVersion,
        'shopId': 'shop-1',
        'schemaVersion': AppConstants.databaseSchemaVersion,
        'data': <String, dynamic>{},
      };
      final decoded = BackupEnvelope.fromJson(minimal);

      expect(decoded.tables.summary.total, 0);
      expect(decoded.settingsJson, isEmpty);
      expect(decoded.sourceDeviceId, isNull);
    });

    test('blank sourceDeviceId is dropped', () {
      final blank = Map<String, dynamic>.from(envelope().toJson())
        ..['sourceDeviceId'] = '   ';
      expect(BackupEnvelope.fromJson(blank).sourceDeviceId, isNull);
    });
  });

  group('BackupSummary', () {
    test('counts rows and totals', () {
      final summary = tables().summary;
      expect(summary.categories, 1);
      expect(summary.products, 1);
      expect(summary.saleSequences, 1);
      expect(summary.total, 3);
    });
  });

  group('settings codec', () {
    test('round trips ShopSettings values', () {
      final settings = const ShopSettings(
        shopName: 'Cafe Marina',
        appDisplayName: 'Margarita',
        ownerName: 'Jana',
        phone: '9876543210',
        email: 'hi@marina.example',
        address: 'Beach Road',
        lowStockThreshold: 7,
        theme: ThemePreference.light,
        membershipEnabled: false,
      );

      final restored = shopSettingsFromJson(shopSettingsToJson(settings));

      expect(restored, isNotNull);
      expect(restored!.shopName, 'Cafe Marina');
      expect(restored.appDisplayName, 'Margarita');
      expect(restored.ownerName, 'Jana');
      expect(restored.phone, '9876543210');
      expect(restored.email, 'hi@marina.example');
      expect(restored.address, 'Beach Road');
      expect(restored.lowStockThreshold, 7);
      expect(restored.theme, ThemePreference.light);
      expect(restored.membershipEnabled, isFalse);
    });

    test('returns null when the shop name is missing', () {
      expect(shopSettingsFromJson(const {'lowStockThreshold': 3}), isNull);
    });

    test('falls back safely on damaged values', () {
      final restored = shopSettingsFromJson(const {
        'shopName': 'Cafe Marina',
        'appDisplayName': 123,
        'lowStockThreshold': 'many',
        'theme': 'neon',
        'membershipEnabled': 'yes',
      });

      expect(restored, isNotNull);
      expect(restored!.appDisplayName, AppConstants.defaultAppDisplayName);
      expect(restored.lowStockThreshold, ShopSettings.defaultLowStockThreshold);
      expect(restored.theme, ShopSettings.defaultTheme);
      expect(restored.membershipEnabled, ShopSettings.defaultMembershipEnabled);
    });
  });
}
