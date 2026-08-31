import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/features/settings/data/preferences_settings_repository.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Settings State (Riverpod)
///
/// Composition:
/// - [settingsRepositoryProvider] → preferences-backed repository (override
///                                  in tests with a fake).
/// - [shopSettingsProvider]       → the persisted [ShopSettings], loaded once
///                                  and replaced atomically on save.
/// - [appThemeModeProvider]       → maps the stored theme preference onto the
///                                  Material [ThemeMode] used by the app root.
///
/// Saving keeps the previous state visible until the repository confirms the
/// write; failures leave the current state untouched and surface as a
/// user-safe [SettingsFailure].
/// ---------------------------------------------------------------------------

/// Owns the single settings repository for the application scope.
final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return PreferencesSettingsRepository(AppStorage.preferences);
});

/// The persisted shop settings; falls back to [ShopSettings.defaults] when
/// nothing has been saved yet.
final shopSettingsProvider =
    AsyncNotifierProvider<SettingsController, ShopSettings>(
      SettingsController.new,
    );

final class SettingsController extends AsyncNotifier<ShopSettings> {
  static const String tag = 'Settings';

  @override
  Future<ShopSettings> build() async {
    final repository = ref.watch(settingsRepositoryProvider);
    try {
      return await repository.load();
    } on SettingsFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load settings',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSettingsFailure();
    }
  }

  /// Persists [next] and exposes it as the current state.
  ///
  /// The previous value stays visible until the repository confirms the
  /// write; on failure it remains untouched and the [SettingsFailure] passes
  /// through for the UI to show.
  Future<void> save(ShopSettings next) async {
    requirePermission(ref, Permission.settings);
    try {
      await ref.read(settingsRepositoryProvider).save(next);
      state = AsyncData(next);
    } on SettingsFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Settings save failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedSettingsSaveFailure();
    }
  }
}

/// Maps the stored theme preference onto the [ThemeMode] the app root uses.
///
/// Falls back to the system theme while settings are loading or unavailable
/// (for example during early bootstrap), so the app never blocks on it.
final appThemeModeProvider = Provider<ThemeMode>((ref) {
  final theme =
      ref.watch(shopSettingsProvider).value?.theme ?? ShopSettings.defaultTheme;
  return switch (theme) {
    ThemePreference.system => ThemeMode.system,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.dark => ThemeMode.dark,
  };
});

/// Maps any thrown object to a user-safe message.
///
/// [SettingsFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String settingsErrorMessage(Object error, {String? fallback}) {
  if (error is SettingsFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
