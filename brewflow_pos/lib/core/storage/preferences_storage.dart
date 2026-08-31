import 'package:brewflow_pos/config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Preferences Storage
///
/// Abstraction over `shared_preferences` for NON-SENSITIVE values only
/// (UI preferences, flags, caches, last-sync timestamps).
///
/// Rules:
/// - Never store sensitive values here — use [SecureStorage].
/// - Never store business/domain records here — use the database.
/// - Raw plugin instances are never exposed to the rest of the app;
///   everything goes through this interface (or [AppStorage]).
///
/// All keys are namespaced with [AppConstants.storageKeyPrefix].
/// [PreferencesStorage.clearAppData] removes ONLY keys inside that
/// namespace, leaving values written by other code untouched.
///
/// This interface is suitable for dependency injection / Riverpod
/// `overrideWithValue` in later stages.
/// ---------------------------------------------------------------------------

abstract interface class PreferencesStorage {
  Future<String?> readString(String key);

  Future<bool> readBool(String key, {bool defaultValue = false});

  Future<int> readInt(String key, {int defaultValue = 0});

  Future<double> readDouble(String key, {double defaultValue = 0});

  Future<List<String>> readStringList(String key);

  Future<bool> writeString(String key, String value);

  Future<bool> writeBool(String key, bool value);

  Future<bool> writeInt(String key, int value);

  Future<bool> writeDouble(String key, double value);

  Future<bool> writeStringList(String key, List<String> value);

  Future<bool> contains(String key);

  Future<bool> remove(String key);

  /// Removes all app-namespaced values from preferences.
  Future<void> clearAppData();
}

/// Default [PreferencesStorage] backed by `shared_preferences`.
final class PreferencesStorageImpl implements PreferencesStorage {
  PreferencesStorageImpl._(this._prefs);

  /// Loads the app-wide preferences instance.
  ///
  /// `shared_preferences` caches the instance after the first call,
  /// so repeated loads are cheap and consistent.
  static Future<PreferencesStorageImpl> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PreferencesStorageImpl._(prefs);
  }

  final SharedPreferences _prefs;

  String _namespaced(String key) => '${AppConstants.storageKeyPrefix}$key';

  @override
  Future<String?> readString(String key) async =>
      _prefs.getString(_namespaced(key));

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      _prefs.getBool(_namespaced(key)) ?? defaultValue;

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async =>
      _prefs.getInt(_namespaced(key)) ?? defaultValue;

  @override
  Future<double> readDouble(String key, {double defaultValue = 0}) async =>
      _prefs.getDouble(_namespaced(key)) ?? defaultValue;

  @override
  Future<List<String>> readStringList(String key) async =>
      _prefs.getStringList(_namespaced(key)) ?? const [];

  @override
  Future<bool> writeString(String key, String value) =>
      _prefs.setString(_namespaced(key), value);

  @override
  Future<bool> writeBool(String key, bool value) =>
      _prefs.setBool(_namespaced(key), value);

  @override
  Future<bool> writeInt(String key, int value) =>
      _prefs.setInt(_namespaced(key), value);

  @override
  Future<bool> writeDouble(String key, double value) =>
      _prefs.setDouble(_namespaced(key), value);

  @override
  Future<bool> writeStringList(String key, List<String> value) =>
      _prefs.setStringList(_namespaced(key), value);

  @override
  Future<bool> contains(String key) async =>
      _prefs.containsKey(_namespaced(key));

  @override
  Future<bool> remove(String key) => _prefs.remove(_namespaced(key));

  @override
  Future<void> clearAppData() async {
    final keys = _prefs
        .getKeys()
        .where((key) => key.startsWith(AppConstants.storageKeyPrefix))
        .toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }
}
