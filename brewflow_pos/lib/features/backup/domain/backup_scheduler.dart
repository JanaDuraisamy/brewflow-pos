/// ---------------------------------------------------------------------------
/// BrewFlow POS — Automatic Daily Backup Scheduler
///
/// [DailyBackupScheduler] produces one on-device backup per calendar day for
/// the current shop, using the same [BackupRepository] and [BackupFileStore]
/// as the manual "Create backup" flow (JSON envelope with integrity checksum).
///
/// Guarantees:
///   • same-day dedup — an automatic backup is created at most once a day,
///     tracked through [BackupScheduleStore];
///   • retention — after a successful backup the store is trimmed to the
///     newest [retentionCount] backups, oldest deleted first;
///   • failure isolation — any error yields [AutoBackupFailed] and never
///     throws, so startup is never blocked by a backup problem.
///
/// Runs are best-effort and non-interactive: there is no UI prompt and the
/// scheduler never touches auth, sync or settings.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_repository.dart';

/// Outcome of one automatic-backup attempt.
sealed class AutoBackupResult {
  const AutoBackupResult();
}

/// A fresh automatic backup was written and retention was applied.
final class AutoBackupCreated extends AutoBackupResult {
  const AutoBackupCreated();
}

/// A backup for today already exists; this run was skipped.
final class AutoBackupSkippedToday extends AutoBackupResult {
  const AutoBackupSkippedToday();
}

/// The automatic backup could not be produced. Details are logged, never
/// surfaced; the run can be retried on the next app start.
final class AutoBackupFailed extends AutoBackupResult {
  const AutoBackupFailed();
}

/// Tracks the most recent successful automatic backup so a same-day duplicate
/// is never written. Backed by preferences in production.
abstract interface class BackupScheduleStore {
  /// The local date/time of the last successful automatic backup, or `null`
  /// when none has ever run.
  Future<DateTime?> lastAutoBackup();

  /// Records [at] as the last successful automatic backup.
  Future<void> markAutoBackup(DateTime at);
}

/// Creates one on-device backup per day with bounded retention.
final class DailyBackupScheduler {
  DailyBackupScheduler({
    required BackupRepository backupRepository,
    required BackupFileStore fileStore,
    required BackupScheduleStore scheduleStore,
    required DateTime Function() clock,
    this.retentionCount = 10,
  }) : _repository = backupRepository,
       _store = fileStore,
       _schedule = scheduleStore,
       _now = clock;

  final BackupRepository _repository;
  final BackupFileStore _store;
  final BackupScheduleStore _schedule;
  final DateTime Function() _now;

  /// Number of most-recent backups to keep on disk after a run.
  final int retentionCount;

  /// Runs the daily backup. Safe to call on every app start.
  Future<AutoBackupResult> run() async {
    try {
      final current = _now();
      final last = await _schedule.lastAutoBackup();
      if (last != null && _localDateKey(last) == _localDateKey(current)) {
        return const AutoBackupSkippedToday();
      }

      final envelope = await _repository.buildBackup();
      await _store.write(backupFileName(current), envelope.encodeJson());
      await _schedule.markAutoBackup(current);
      await _enforceRetention();
      return const AutoBackupCreated();
    } on BackupFailure {
      return const AutoBackupFailed();
    } on Object {
      return const AutoBackupFailed();
    }
  }

  /// Deletes the oldest backups beyond [retentionCount], keeping the newest.
  Future<void> _enforceRetention() async {
    final files = await _store.listFiles();
    if (files.length <= retentionCount) return;
    final excess = files.sublist(retentionCount);
    for (final file in excess) {
      try {
        await _store.deleteFile(file.name);
      } on Object {
        // A failed delete never fails the whole run; it is retried next day.
      }
    }
  }

  /// Local calendar-day key (`yyyy-MM-dd`) used for same-day detection.
  String _localDateKey(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
