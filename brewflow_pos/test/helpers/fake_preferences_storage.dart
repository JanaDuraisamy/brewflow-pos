import 'package:brewflow_pos/core/storage/preferences_storage.dart';

/// In-memory [PreferencesStorage] for tests.
///
/// Mirrors the shared_preferences-backed semantics used by the app: values
/// are stored as typed entries, reads fall back to defaults, and removals
/// work per key.
final class FakePreferencesStorage implements PreferencesStorage {
  final Map<String, Object> _values = {};

  @override
  Future<String?> readString(String key) async => _values[key] as String?;

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      _values[key] as bool? ?? defaultValue;

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async =>
      _values[key] as int? ?? defaultValue;

  @override
  Future<double> readDouble(String key, {double defaultValue = 0}) async =>
      _values[key] as double? ?? defaultValue;

  @override
  Future<List<String>> readStringList(String key) async =>
      List<String>.from(_values[key] as List<String>? ?? const []);

  @override
  Future<bool> writeString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> writeBool(String key, bool value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> writeInt(String key, int value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> writeDouble(String key, double value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> writeStringList(String key, List<String> value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> contains(String key) async => _values.containsKey(key);

  @override
  Future<bool> remove(String key) async => _values.remove(key) != null;

  @override
  Future<void> clearAppData() async => _values.clear();
}
