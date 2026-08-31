# Backup & Restore

Phase 7.8D introduced JSON-based backup and restore.

## Model

- `BackupEnvelope` (format header `brewflow.backup`, `backupVersion: 1`, `schemaVersion`,
  `shopId`, `createdAt`) containing `settingsJson` and `BackupTables`
  (`lib/features/backup/domain/backup_models.dart`).
- 14 business tables: categories, products, productVariants, customers,
  customerPayments, expenses, sales, saleItems, suppliers, purchases, purchaseItems,
  stockMovements, saleSequences, purchaseSequences.

## Repository

`DriftBackupRepository` (`lib/features/backup/data/drift_backup_repository.dart`):

- `buildBackup()`: reads the 14 tables (`row.toJson()`) + `ShopSettings` into an envelope.
  It **never** exports auth, users, shops, devices, staff_permissions, or sync tables.
- `restoreBackup()`: validates schema version + shop identity match, then in **one**
  Drift transaction clears business tables (children before parents) and inserts backup
  rows (parents before children). Settings are restored after the DB commit.
- Failures are typed `BackupFailure` subtypes: `InvalidBackupFormatFailure`,
  `CorruptBackupFailure`, `IncompatibleBackupSchemaFailure`, `CrossShopBackupFailure`,
  `BackupSettingsRestoreFailure`, `UnexpectedBackupFailure`.

## File store

- `BackupFileStore` interface with `DirectoryBackupFileStore` and
  `AppDocumentsBackupFileStore` implementations
  (`lib/features/backup/data/backup_file_store.dart`).
- Production location: `<app documents>/backups/`
  (via `getApplicationDocumentsDirectory()`).
- File naming: `brewflow_backup_YYYYMMDD_HHMMSS.json` with a collision suffix appended on
  duplicates. Methods: `listFiles`, `write`, `readFile`, `deleteFile`.
- `backupFileStoreProvider` is a `FutureProvider` via `AppDocumentsBackupFileStore.open()`.

## Authorization

Backup UI (`BackupSectionCard` / `MobileBackupSection`) and `_guardBackupAccess` both
require `Permission.settings`. Only users with the SETTINGS permission can create or
restore backups.

## Providers

- `backupRepositoryProvider` — wires `DriftBackupRepository` to the database + settings.
- `backupFileStoreProvider` (see above).
