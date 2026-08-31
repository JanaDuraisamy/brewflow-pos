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

  static const String appName = 'BrewFlow POS';
  static const String appVersion = '1.0.0';

  /// The app display / brand name shown as the header wordmark. This is the
  /// display identity and (unlike the shop/business name) is editable from
  /// Settings. Defaults to the core brand wordmark.
  static const String defaultAppDisplayName = 'BrewFlow';

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
  static const int databaseSchemaVersion = 15;

  /// Prefix for human-readable receipt numbers (e.g. 'BF-000042').
  static const String receiptPrefix = 'BF-';

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
