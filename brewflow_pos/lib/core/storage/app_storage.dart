import 'preferences_storage.dart';
import 'secure_storage.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — App Storage Facade
///
/// Single entry point for local storage during bootstrap and across the app.
///
///   await AppStorage.init();            // once, during app bootstrap
///   await AppStorage.secure.write(...); // sensitive values
///   await AppStorage.preferences.readBool(...); // non-sensitive values
///
/// Responsibilities are split:
/// - [AppStorage.secure]      → sensitive values (sessions, tokens)
/// - [AppStorage.preferences] → non-sensitive values (UI preferences, flags)
///
/// [AppStorage.init] accepts injected implementations, which keeps the
/// facade testable and ready for Riverpod wiring in later stages.
/// ---------------------------------------------------------------------------

final class AppStorage {
  AppStorage._();

  static SecureStorage? _secure;
  static PreferencesStorage? _preferences;

  /// Whether [AppStorage.init] has completed.
  static bool get isInitialized => _secure != null && _preferences != null;

  /// Sensitive-value storage (auth sessions, refresh tokens).
  static SecureStorage get secure {
    final storage = _secure;
    if (storage == null) {
      throw StateError(
        'AppStorage: init() must be called before accessing secure storage.',
      );
    }
    return storage;
  }

  /// Non-sensitive-value storage (UI preferences, flags, caches).
  static PreferencesStorage get preferences {
    final storage = _preferences;
    if (storage == null) {
      throw StateError(
        'AppStorage: init() must be called before accessing preferences.',
      );
    }
    return storage;
  }

  /// Initializes both storage backends.
  ///
  /// Idempotent: repeated calls are no-ops after the first successful run.
  /// Optional parameters allow injecting test doubles or alternative
  /// implementations without touching plugin code.
  static Future<void> init({
    SecureStorage? secure,
    PreferencesStorage? preferences,
  }) async {
    if (isInitialized) {
      return;
    }
    _secure = secure ?? SecureStorageImpl();
    _preferences = preferences ?? await PreferencesStorageImpl.load();
  }
}
