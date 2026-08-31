import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/preferences_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Device Identity
///
/// One stable installation UUID per BrewFlow installation. Generated on first
/// use, persisted in PreferencesStorage and reused across restarts,
/// logout/login and user switches — it identifies the DEVICE, never the user
/// or shop:
///
///   DEVICE  = installation identity        (this file)
///   USER    = Supabase auth user id         (identity only)
///   SHOP    = shops.id                      (business scope)
///
/// A fresh UUID avoids hardware-identifier privacy/platform restrictions and
/// is sufficient for server-side device registration.
/// ---------------------------------------------------------------------------

final class DeviceIdentity {
  DeviceIdentity._(this.value);

  /// Stable installation identifier (UUID v4).
  final String value;

  static const String _prefsKey = 'device_id';
  static const Uuid _uuid = Uuid();

  static DeviceIdentity? _cached;

  /// Returns the persisted installation id, creating it once when absent.
  /// Subsequent calls reuse the same id for the lifetime of the process and
  /// every future process (until app data is cleared).
  /// [storage] is injectable for tests; production uses AppStorage.
  static Future<DeviceIdentity> resolve({PreferencesStorage? storage}) async {
    final cached = _cached;
    if (cached != null) return cached;
    final preferences = storage ?? AppStorage.preferences;
    var value = await preferences.readString(_prefsKey);
    if (value == null || value.trim().isEmpty) {
      value = _uuid.v4();
      await preferences.writeString(_prefsKey, value);
    }
    return _cached = DeviceIdentity._(value);
  }

  /// Test seam: clears the process cache so a fresh storage backend yields a
  /// fresh identity.
  static void resetForTest() => _cached = null;
}

/// Riverpod access point; resolves lazily on first read.
final deviceIdProvider = FutureProvider<String>((ref) async {
  return (await DeviceIdentity.resolve()).value;
});
