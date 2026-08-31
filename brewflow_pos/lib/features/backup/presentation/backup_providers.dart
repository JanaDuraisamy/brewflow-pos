import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/data/drift_backup_repository.dart';
import 'package:brewflow_pos/features/backup/domain/backup_repository.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Backup Providers
///
/// [backupFileStoreProvider] resolves the on-device backup folder lazily.
/// [backupRepositoryProvider] wires the Drift [BackupRepository] to the
/// current database and settings repositories.
///
/// Widgets must NOT watch these providers during build (opening the database
/// or the documents directory can hit plugins); always resolve them with
/// `await ref.read(...future)` inside a handler.
/// ---------------------------------------------------------------------------

/// On-device backup folder (resolved once, reused for the app lifetime).
final backupFileStoreProvider = FutureProvider<BackupFileStore>((ref) {
  return AppDocumentsBackupFileStore.open();
});

/// Backup engine bound to the current shop database and settings store.
final backupRepositoryProvider = Provider<BackupRepository>((ref) {
  final database = ref.watch(appDatabaseProvider);
  final settings = ref.watch(settingsRepositoryProvider);
  return DriftBackupRepository(database, settingsRepository: settings);
});
