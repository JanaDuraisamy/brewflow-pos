/// ---------------------------------------------------------------------------
/// BrewFlow POS — Settings Domain Models
///
/// [ShopSettings] is the single, persisted copy of business identity and
/// preference values. Persistence details (preference keys, namespacing)
/// never leak past the repository boundary.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/config/constants.dart';

/// App appearance preference. 'System' follows the device theme.
enum ThemePreference {
  system,
  light,
  dark;

  String get label => switch (this) {
    ThemePreference.system => 'System',
    ThemePreference.light => 'Light',
    ThemePreference.dark => 'Dark',
  };
}

final class ShopSettings {
  const ShopSettings({
    required this.shopName,
    this.appDisplayName = AppConstants.defaultAppDisplayName,
    this.ownerName,
    this.phone,
    this.email,
    this.address,
    this.lowStockThreshold = defaultLowStockThreshold,
    this.theme = defaultTheme,
    this.membershipEnabled = defaultMembershipEnabled,
  });

  /// Display name of the shop; defaults to the app name on first run.
  final String shopName;

  /// App display / brand name shown as the header wordmark. Separate from the
  /// business [shopName]; editable from Settings.
  final String appDisplayName;

  final String? ownerName;
  final String? phone;
  final String? email;
  final String? address;

  /// Stock count below which a product is flagged 'running low'.
  final int lowStockThreshold;

  /// Appearance preference; null-safe default is [defaultTheme].
  final ThemePreference theme;

  /// Global membership-pricing switch. ON → member customers are charged the
  /// configured member prices (and the counter can toggle member pricing).
  /// OFF → membership pricing is globally disabled: every customer pays
  /// normal selling prices. Enrolment flags and member prices are never
  /// deleted by this switch — turning it back on restores member pricing.
  final bool membershipEnabled;

  static const int defaultLowStockThreshold = 5;
  static const ThemePreference defaultTheme = ThemePreference.system;

  /// Membership starts enabled so existing shops keep their member prices;
  /// owners can switch it off any time without losing data.
  static const bool defaultMembershipEnabled = true;

  /// Fallback values used before any settings have been persisted.
  factory ShopSettings.defaults() =>
      const ShopSettings(shopName: AppConstants.appName);

  ShopSettings copyWith({
    String? shopName,
    String? appDisplayName,
    String? Function()? ownerName,
    String? Function()? phone,
    String? Function()? email,
    String? Function()? address,
    int? lowStockThreshold,
    ThemePreference? theme,
    bool? membershipEnabled,
  }) => ShopSettings(
    shopName: shopName ?? this.shopName,
    appDisplayName: appDisplayName ?? this.appDisplayName,
    ownerName: ownerName != null ? ownerName() : this.ownerName,
    phone: phone != null ? phone() : this.phone,
    email: email != null ? email() : this.email,
    address: address != null ? address() : this.address,
    lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
    theme: theme ?? this.theme,
    membershipEnabled: membershipEnabled ?? this.membershipEnabled,
  );
}
