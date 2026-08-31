import 'package:brewflow_pos/config/constants.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Secure Storage
///
/// Abstraction over `flutter_secure_storage` for SENSITIVE values only
/// (auth sessions, refresh tokens, credentials).
///
/// Rules:
/// - Never store business/domain records here — use the database.
/// - Never store Supabase credentials here — they live in `.env`.
/// - Raw plugin instances are never exposed to the rest of the app;
///   everything goes through this interface (or [AppStorage]).
///
/// Keys are namespaced with [AppConstants.storageKeyPrefix] to avoid
/// collisions with values written by other code or plugins.
///
/// This interface is suitable for dependency injection / Riverpod
/// `overrideWithValue` in later stages.
/// ---------------------------------------------------------------------------

abstract interface class SecureStorage {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<bool> readBool(String key, {bool defaultValue = false});

  Future<void> writeBool(String key, bool value);

  Future<int> readInt(String key, {int defaultValue = 0});

  Future<void> writeInt(String key, int value);

  Future<bool> contains(String key);

  Future<void> delete(String key);

  /// Removes all values written to secure storage by this app.
  Future<void> clear();
}

/// Default [SecureStorage] backed by `flutter_secure_storage`.
final class SecureStorageImpl implements SecureStorage {
  SecureStorageImpl({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  String _namespaced(String key) => '${AppConstants.storageKeyPrefix}$key';

  @override
  Future<String?> read(String key) => _storage.read(key: _namespaced(key));

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: _namespaced(key), value: value);

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async {
    final raw = await _storage.read(key: _namespaced(key));
    return raw == null ? defaultValue : raw == 'true';
  }

  @override
  Future<void> writeBool(String key, bool value) =>
      write(key, value.toString());

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async {
    final raw = await _storage.read(key: _namespaced(key));
    final parsed = raw == null ? null : int.tryParse(raw);
    return parsed ?? defaultValue;
  }

  @override
  Future<void> writeInt(String key, int value) => write(key, value.toString());

  @override
  Future<bool> contains(String key) =>
      _storage.containsKey(key: _namespaced(key));

  @override
  Future<void> delete(String key) => _storage.delete(key: _namespaced(key));

  @override
  Future<void> clear() => _storage.deleteAll();
}
