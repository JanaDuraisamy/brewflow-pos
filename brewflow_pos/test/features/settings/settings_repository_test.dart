import 'package:brewflow_pos/features/settings/data/preferences_settings_repository.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_preferences_storage.dart';

void main() {
  late FakePreferencesStorage preferences;
  late PreferencesSettingsRepository repository;

  setUp(() {
    preferences = FakePreferencesStorage();
    repository = PreferencesSettingsRepository(preferences);
  });

  group('load', () {
    test('returns defaults when nothing has been saved', () async {
      final settings = await repository.load();

      expect(settings.shopName, 'BrewFlow POS');
      expect(settings.appDisplayName, 'BrewFlow');
      expect(settings.ownerName, isNull);
      expect(settings.phone, isNull);
      expect(settings.email, isNull);
      expect(settings.address, isNull);
      expect(settings.lowStockThreshold, 5);
      expect(settings.theme, ThemePreference.system);
    });

    test('returns persisted values when present', () async {
      await preferences.writeString('settings_shop_name', 'Cafe Marina');
      await preferences.writeString('settings_owner_name', 'Jana');
      await preferences.writeString('settings_phone', '9876543210');
      await preferences.writeString('settings_email', 'hi@marina.example');
      await preferences.writeString('settings_address', 'Beach Road');
      await preferences.writeInt('settings_low_stock_threshold', 3);
      await preferences.writeString('settings_theme', 'dark');

      final settings = await repository.load();

      expect(settings.shopName, 'Cafe Marina');
      expect(settings.ownerName, 'Jana');
      expect(settings.phone, '9876543210');
      expect(settings.email, 'hi@marina.example');
      expect(settings.address, 'Beach Road');
      expect(settings.lowStockThreshold, 3);
      expect(settings.theme, ThemePreference.dark);
    });

    test('falls back to defaults for blank values', () async {
      await preferences.writeString('settings_shop_name', '   ');
      await preferences.writeString('settings_owner_name', '');
      await preferences.writeInt('settings_low_stock_threshold', 0);

      final settings = await repository.load();

      expect(settings.shopName, 'BrewFlow POS');
      expect(settings.ownerName, isNull);
      expect(settings.lowStockThreshold, 5);
    });

    test('falls back to default theme for unknown theme names', () async {
      await preferences.writeString('settings_theme', 'matrix');

      final settings = await repository.load();

      expect(settings.theme, ThemePreference.system);
    });
  });

  group('save', () {
    test('round-trips every field through the storage', () async {
      const settings = ShopSettings(
        shopName: 'Cafe Marina',
        appDisplayName: 'Marina POS',
        ownerName: 'Jana',
        phone: '9876543210',
        email: 'hi@marina.example',
        address: 'Beach Road',
        lowStockThreshold: 2,
        theme: ThemePreference.light,
      );

      await repository.save(settings);
      final loaded = await repository.load();

      expect(loaded.shopName, 'Cafe Marina');
      expect(loaded.appDisplayName, 'Marina POS');
      expect(loaded.ownerName, 'Jana');
      expect(loaded.phone, '9876543210');
      expect(loaded.email, 'hi@marina.example');
      expect(loaded.address, 'Beach Road');
      expect(loaded.lowStockThreshold, 2);
      expect(loaded.theme, ThemePreference.light);
    });

    test('overwrites previous values', () async {
      await repository.save(const ShopSettings(shopName: 'First Name'));
      await repository.save(const ShopSettings(shopName: 'Second Name'));

      final loaded = await repository.load();

      expect(loaded.shopName, 'Second Name');
    });
  });
}
