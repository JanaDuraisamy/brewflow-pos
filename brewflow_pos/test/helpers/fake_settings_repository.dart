import 'dart:async';

import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';

/// In-memory [SettingsRepository] for tests.
///
/// Can fail on demand for load or save, and can gate saves so in-flight
/// (loading) states are observable.
final class FakeSettingsRepository implements SettingsRepository {
  ShopSettings stored = ShopSettings.defaults();

  /// Thrown by [load] when set.
  Object? loadError;

  /// Thrown by [save] when set.
  Object? saveError;

  /// When set, loads wait until released (in-flight state tests).
  Completer<void>? loadGate;

  /// When set, saves wait until released (in-flight state tests).
  Completer<void>? saveGate;

  /// Records every settings value passed to [save].
  final List<ShopSettings> saved = [];

  @override
  Future<ShopSettings> load() async {
    final error = loadError;
    if (error != null) {
      throw error;
    }
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
    return stored;
  }

  @override
  Future<void> save(ShopSettings settings) async {
    final error = saveError;
    if (error != null) {
      throw error;
    }
    final gate = saveGate;
    if (gate != null) {
      await gate.future;
    }
    stored = settings;
    saved.add(settings);
  }
}
