import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/storage/preferences_storage.dart';

import '../domain/settings_models.dart';
import '../domain/settings_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Preferences-Backed Settings Repository
///
/// Persists [ShopSettings] through [PreferencesStorage] (shared_preferences
/// under the app namespace). Values are small, non-sensitive and read
/// synchronously on first load, so preferences — not the database — are the
/// right home for them.
///
/// Read rules mirror the model defaults: blank values fall back to
/// [ShopSettings.defaults], and out-of-range numbers fall back to their
/// default so corrupt values can never crash or poison the UI.
/// ---------------------------------------------------------------------------

final class PreferencesSettingsRepository implements SettingsRepository {
  PreferencesSettingsRepository(this._preferences);

  final PreferencesStorage _preferences;

  static const String _shopNameKey = 'settings_shop_name';
  static const String _appDisplayNameKey = 'settings_app_display_name';
  static const String _ownerNameKey = 'settings_owner_name';
  static const String _phoneKey = 'settings_phone';
  static const String _emailKey = 'settings_email';
  static const String _addressKey = 'settings_address';
  static const String _lowStockThresholdKey = 'settings_low_stock_threshold';
  static const String _themeKey = 'settings_theme';
  static const String _membershipEnabledKey = 'settings_membership_enabled';

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<ShopSettings> load() async {
    final shopName = _blankToNull(await _preferences.readString(_shopNameKey));
    final lowStock = await _preferences.readInt(
      _lowStockThresholdKey,
      defaultValue: 0,
    );
    final themeName = _blankToNull(await _preferences.readString(_themeKey));
    final membershipEnabled = await _preferences.readBool(
      _membershipEnabledKey,
      defaultValue: ShopSettings.defaultMembershipEnabled,
    );
    return ShopSettings(
      shopName: shopName ?? AppConstants.appName,
      appDisplayName:
          _blankToNull(await _preferences.readString(_appDisplayNameKey)) ??
          AppConstants.defaultAppDisplayName,
      ownerName: _blankToNull(await _preferences.readString(_ownerNameKey)),
      phone: _blankToNull(await _preferences.readString(_phoneKey)),
      email: _blankToNull(await _preferences.readString(_emailKey)),
      address: _blankToNull(await _preferences.readString(_addressKey)),
      lowStockThreshold: lowStock > 0
          ? lowStock
          : ShopSettings.defaultLowStockThreshold,
      theme:
          ThemePreference.values.asNameMap()[themeName] ??
          ShopSettings.defaultTheme,
      membershipEnabled: membershipEnabled,
    );
  }

  @override
  Future<void> save(ShopSettings settings) async {
    await _preferences.writeString(_shopNameKey, settings.shopName);
    await _preferences.writeString(_appDisplayNameKey, settings.appDisplayName);
    await _preferences.writeString(_ownerNameKey, settings.ownerName ?? '');
    await _preferences.writeString(_phoneKey, settings.phone ?? '');
    await _preferences.writeString(_emailKey, settings.email ?? '');
    await _preferences.writeString(_addressKey, settings.address ?? '');
    await _preferences.writeInt(
      _lowStockThresholdKey,
      settings.lowStockThreshold,
    );
    await _preferences.writeString(_themeKey, settings.theme.name);
    await _preferences.writeBool(
      _membershipEnabledKey,
      settings.membershipEnabled,
    );
  }
}
