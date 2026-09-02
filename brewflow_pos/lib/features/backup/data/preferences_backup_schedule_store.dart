import 'package:brewflow_pos/core/storage/preferences_storage.dart';
import 'package:brewflow_pos/features/backup/domain/backup_scheduler.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Preferences-Backed Auto-Backup Schedule Store
///
/// Persists the date of the last successful automatic backup in
/// [PreferencesStorage] so a same-day run is skipped across app restarts.
/// Values are non-sensitive schedule metadata only.
/// ---------------------------------------------------------------------------

final class PreferencesBackupScheduleStore implements BackupScheduleStore {
  PreferencesBackupScheduleStore(this._preferences);

  final PreferencesStorage _preferences;

  static const String _lastRunKey = 'backup_last_auto_run';

  @override
  Future<DateTime?> lastAutoBackup() async {
    final raw = await _preferences.readString(_lastRunKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  @override
  Future<void> markAutoBackup(DateTime at) async {
    await _preferences.writeString(_lastRunKey, at.toIso8601String());
  }
}
