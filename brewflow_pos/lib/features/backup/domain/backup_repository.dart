/// ---------------------------------------------------------------------------
/// BrewFlow POS — Backup Repository Contract
///
/// [buildBackup] snapshots the current shop's business data (and the
/// non-sensitive [ShopSettings]) into a portable [BackupEnvelope].
/// [restoreBackup] validates the envelope against the current shop and schema
/// version, then replaces all business data in a single transaction, rolling
/// back completely on any failure. Settings are written back after the
/// database commit.
///
/// Auth/user identity, shop identity, device identity, staff permissions and
/// all sync tables are NEVER part of a backup or a restore. No secrets are
/// ever written into a backup.
/// ---------------------------------------------------------------------------
library;

import 'backup_models.dart';

abstract interface class BackupRepository {
  /// Reads the current shop state into a portable envelope.
  Future<BackupEnvelope> buildBackup();

  /// Validates [envelope] against the current shop and schema version, then
  /// replaces all business data transactionally and restores settings.
  ///
  /// Throws [BackupFailure] subtypes; the database state is unchanged when
  /// any failure occurs.
  Future<void> restoreBackup(BackupEnvelope envelope);
}
