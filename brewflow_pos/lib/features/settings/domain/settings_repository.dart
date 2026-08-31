/// ---------------------------------------------------------------------------
/// BrewFlow POS — Settings Repository Contract
///
/// Loads and persists [ShopSettings]. Failures surface as sealed
/// [SettingsFailure]s with user-safe, display-ready messages.
/// ---------------------------------------------------------------------------
library;

import 'settings_models.dart';

sealed class SettingsFailure implements Exception {
  const SettingsFailure(this.message);

  /// Display-ready, user-safe explanation of the failure.
  final String message;
}

final class UnexpectedSettingsFailure extends SettingsFailure {
  const UnexpectedSettingsFailure()
    : super('Could not load settings. Please try again.');
}

final class UnexpectedSettingsSaveFailure extends SettingsFailure {
  const UnexpectedSettingsSaveFailure()
    : super('Could not save settings. Please try again.');
}

abstract interface class SettingsRepository {
  /// Loads the persisted settings; returns [ShopSettings.defaults] when
  /// nothing has been saved yet.
  Future<ShopSettings> load();

  /// Persists [settings] so the next [load] returns them unchanged.
  Future<void> save(ShopSettings settings);
}
