/// Static, compile-time configuration shared across the app.
///
/// Rules:
/// - Never put secrets here — secrets live in `.env` (see [AppEnv]).
/// - Prefer constants over magic strings/numbers in application code.
///
/// Sections are grouped for future consumers:
///   app identity, database, storage, network, sync, authentication.
library;

final class AppConstants {
  AppConstants._();

  // -------------------------------------------------------------------------
  // App Identity
  // -------------------------------------------------------------------------

  static const String appName = 'JiggarTea Bill';
  static const String appVersion = '2.4.0-beta.7';

  /// The app display / brand name shown as the header wordmark. This is the
  /// display identity and (unlike the shop/business name) is editable from
  /// Settings. Defaults to the core brand wordmark.
  static const String defaultAppDisplayName = 'JiggarTea Bill';

  /// Default locale for formatting (dates, currency, numbers).
  static const String defaultLocale = 'en';

  /// Default currency for billing and reports.
  static const String defaultCurrency = 'INR';

  // -------------------------------------------------------------------------
  // Database (Drift)
  // -------------------------------------------------------------------------

  /// Name of the local SQLite database file.
  static const String databaseFileName = 'brewflow_pos.db';

  /// Current schema version. Bump on every database migration.
  static const int databaseSchemaVersion = 31;

  /// Receipt prefix stamped onto a newly created business (e.g. 'BF-000042').
  ///
  /// This is only a DEFAULT for `shops.receipt_prefix` — the value written when
  /// a shop row is created. Receipts are labelled from the shop's own column,
  /// never from this constant, so a second business on the same device can
  /// carry a different label without disturbing the first one's numbering.
  static const String defaultShopReceiptPrefix = 'BF-';

  /// Receipt prefix for the Food Truck business (e.g. 'FT-000042'), so truck
  /// receipts never look like Cafe receipts on the same till roll.
  static const String foodTruckReceiptPrefix = 'FT-';

  /// Prefix for human-readable purchase numbers (e.g. 'PUR-000012').
  static const String purchaseNumberPrefix = 'PUR-';

  // -------------------------------------------------------------------------
  // Storage
  // -------------------------------------------------------------------------

  /// Prefix applied to shared preferences keys.
  static const String storageKeyPrefix = 'brewflow_';

  /// Key under which the auth session is stored in secure storage.
  static const String authSessionKey = 'brewflow_auth_session';

  // -------------------------------------------------------------------------
  // Network
  // -------------------------------------------------------------------------

  static const Duration networkTimeout = Duration(seconds: 15);

  static const int networkRetryCount = 3;

  static const Duration networkRetryDelay = Duration(seconds: 2);

  // -------------------------------------------------------------------------
  // Sync
  // -------------------------------------------------------------------------

  /// Interval between background sync attempts while online.
  static const Duration syncInterval = Duration(seconds: 30);

  /// Maximum number of queued operations pushed in one sync batch.
  static const int syncBatchSize = 100;

  // -------------------------------------------------------------------------
  // Authentication
  // -------------------------------------------------------------------------

  /// Maximum session age before a re-login is forced.
  static const Duration authSessionMaxAge = Duration(days: 30);
}
