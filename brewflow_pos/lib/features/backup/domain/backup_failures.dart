/// ---------------------------------------------------------------------------
/// BrewFlow POS — Backup & Restore Failures
///
/// Sealed [BackupFailure]s with display-ready messages, mirroring the failure
/// style used across the feature domains. Restore failures leave the current
/// shop data untouched (the database replace is a single transaction).
/// ---------------------------------------------------------------------------
library;

sealed class BackupFailure implements Exception {
  const BackupFailure(this.message);

  /// Display-ready, user-safe explanation of the failure.
  final String message;
}

/// The selected file is not a BrewFlow backup at all.
final class InvalidBackupFormatFailure extends BackupFailure {
  const InvalidBackupFormatFailure()
    : super('This file is not a BrewFlow backup.');
}

/// The file is damaged or unreadable (bad JSON, missing fields, typed wrong).
final class CorruptBackupFailure extends BackupFailure {
  const CorruptBackupFailure()
    : super('This backup file is damaged or unreadable.');
}

/// The backup was created by an incompatible schema/backup version.
final class IncompatibleBackupSchemaFailure extends BackupFailure {
  const IncompatibleBackupSchemaFailure()
    : super(
        'This backup was created by a different version of BrewFlow and '
        'cannot be restored here.',
      );
}

/// The backup belongs to a different shop on a different installation.
final class CrossShopBackupFailure extends BackupFailure {
  const CrossShopBackupFailure()
    : super(
        'This backup belongs to a different shop and cannot be restored here.',
      );
}

/// The backup restore succeeded for device data but settings could not be
/// written back.
final class BackupSettingsRestoreFailure extends BackupFailure {
  const BackupSettingsRestoreFailure()
    : super('Backup restored, but settings could not be saved. Try again.');
}

/// Unexpected I/O or database error. Details are logged, never shown.
final class UnexpectedBackupFailure extends BackupFailure {
  const UnexpectedBackupFailure()
    : super('Could not complete the backup right now. Please try again.');
}
