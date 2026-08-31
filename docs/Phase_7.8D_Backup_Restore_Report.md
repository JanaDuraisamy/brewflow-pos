# Phase 7.8D — Backup + Restore

BrewFlow POS · Scope: JSON-envelope backup/restore of all business data + settings

> **Premise correction.** The 7.8D task assumed a backup/restore feature existed
> and only needed finishing. The audit found **zero backup/restore
> implementation** in the codebase (no models, no engine, no data store, no UI,
> no providers). Per the build-decision, the feature was implemented end-to-end
> in this phase.

## Architecture

Feature-first, under `lib/features/backup/`:

1. **Domain** — `domain/backup_failures.dart`
   Sealed `BackupFailure` (user-safe `message`) with concrete failures:
   `InvalidBackupFormatFailure`, `CorruptBackupFailure`,
   `IncompatibleBackupSchemaFailure`, `CrossShopBackupFailure`,
   `BackupSettingsRestoreFailure`, `UnexpectedBackupFailure`.
2. **Domain model** — `domain/backup_models.dart`
   - Envelope container → JSON. Format constants renamed to avoid field
     shadowing: **`kBackupFormat`** (`'brewflow.backup'`) and **`kBackupVersion`**
     (`1`).
   - `BackupEnvelope` fields: `format`, `formatVersion`, `createdAt`,
     `sourceDeviceId?`, `shopId`, `schemaVersion` (must equal
     `AppConstants.databaseSchemaVersion` = 14), `settingsJson`, `tables`.
   - `BackupTables` — all **14 business tables** (categories, products,
     productVariants, customers, customerPayments, expenses, sales, saleItems,
     suppliers, purchases, purchaseItems, stockMovements, saleSequences,
     purchaseSequences).
   - `BackupSummary` (row counts + total) and tolerant settings codec
     (`shopSettingsToJson` / `shopSettingsFromJson`).
3. **Interface** — `domain/backup_repository.dart`
   `BackupRepository` with `buildBackup()` and `restoreBackup(BackupEnvelope)`.
   Doc-block documents scope: business data + non-sensitive shop settings are
   included; secrets and runtime state are excluded.
4. **Engine** — `data/drift_backup_repository.dart`
   `DriftBackupRepository` (Drift, tag `Backup`).
   - `buildBackup`: shop lookup → settings load → read all 14 tables via a
     generic `_selectAll` → envelope.
   - `restoreBackup`:
     - Guards FIRST: `schemaVersion` mismatch → `IncompatibleBackupSchemaFailure`;
       missing shop row or `envelope.shopId != shop.id` →
       `CrossShopBackupFailure`. Checks run before any write.
     - Single Drift transaction: delete children-first, insert parents-first
       (see order below), so any insert error rolls back entirely — no partial
       restore.
     - Settings written AFTER the DB transaction commits; a settings-save
       failure is a distinct `BackupSettingsRestoreFailure` (restored data kept).
   - Generic `_insertRows<D, C>` converts row `FormatException`/`TypeError` →
     `CorruptBackupFailure`.
   - All unexpected errors are logged and wrapped as `UnexpectedBackupFailure`.
5. **File store** — `data/backup_file_store.dart`
   `BackupFileInfo`, `compareBackupFileInfo` (newest-first),
   `backupFileName(DateTime)` (`brewflow_backup_YYYYMMDD_HHMMSS.json`),
   `BackupFileStore` interface, `DirectoryBackupFileStore` (lazy dir create,
   JSON-only listing, collision suffix `_2`/`_3`), and
   `AppDocumentsBackupFileStore.open()` rooted at `<app documents>/backups/`.
6. **Providers** — `presentation/backup_providers.dart`
   `backupFileStoreProvider` (Future) and `backupRepositoryProvider`
   (wraps `DriftBackupRepository` over `appDatabaseProvider` +
   `settingsRepositoryProvider`).
7. **UI** — `presentation/backup_section.dart` + `settings_page.dart`
   **Data & Backup** desktop card + phone section. All provider reads are lazy
   (inside handlers via `ref.read`); nothing is `ref.watch`ed during build, so
   existing settings widget tests (which do not override backup providers) stay
   green.

## Included data

- All 14 business tables (full rows, preserving IDs and foreign keys).
- Non-sensitive shop settings (`shopName`, `appDisplayName`, owner/contact,
  address, low-stock threshold, theme, membership toggle).
- Receipt/purchase sequence counters (`saleSequences`, `purchaseSequences`) so
  numbering does not restart after restore.
- **Excluded by design**: secrets, tokens, API keys, credentials, runtime/local
  device state. `sourceDeviceId` is recorded but optional and never treated as
  a secret.

## Export (Create backup) flow

1. Owner (SETTINGS permission) taps **Create backup**.
2. `_createBackup` (widget-layer permission guard → `buildBackup` → store
   `write`) saves `<documents>/backups/brewflow_backup_<stamp>.json`.
3. Confirmation dialog shows the file name, a compact summary
   (`backupSummaryLine`, e.g. `4 products, 3 customers`), and a **Share backup**
   action which sends the raw JSON through the existing text-only `ShareService`.

## Restore flow

1. Owner taps **Restore backup** → on-device files listed newest-first with
   size + timestamp in a picker dialog.
2. Picking a file reads + parses it (`BackupEnvelope.fromJsonString`).
3. `confirmDestructive` shows the file, created time and a summary with an
   explicit "cannot be undone" consequence.
4. Confirmed → `restoreBackup` (schema + cross-shop guards, transactional
   replace) → on success the cached data providers are invalidated and a
   "Backup restored." snackbar shows.

Restore write order (single transaction): clear children-first
(stockMovements → purchaseItems → purchases → saleItems → customerPayments →
sales → productVariants → products → categories → expenses → customers →
suppliers → saleSequences → purchaseSequences); insert parents-first (the
reverse).

## Safety handling

- **Invalid/foreign file** → `InvalidBackupFormatFailure`; **corrupt row /
  unreadable file** → `CorruptBackupFailure`; everything inside the transaction
  rolls back (no partial restore).
- **Schema mismatch** → rejected up front (`IncompatibleBackupSchemaFailure`).
- **Cross-shop / missing target shop** → rejected up front, target untouched
  (`CrossShopBackupFailure`).
- **Interrupted restore** → Drift transaction semantics: any failure during
  clear/insert aborts and rolls back to the pre-restore state.
- **Settings-restore failure** → data committed, distinct
  `BackupSettingsRestoreFailure` surfaced (data kept).
- Widget permission gate mirrors `requirePermission`: the section renders only
  for staff with SETTINGS, and every action re-checks the capability.

## Phone result

**Pass (code + widget tests).** `MobileBackupSection` renders at phone widths
with the same Create/Restore actions; the phone settings widget test asserts
the `DATA & BACKUP` section, both buttons, and no exceptions.

## Tablet / desktop result

**Pass.** `BackupSectionCard` added to the expanded settings layout between
Preferences and Printer. Desktop create/restore flows asserted by widget tests.
(The existing printer "Test Print" test needed a `pumpAndSettle` after
`ensureVisible` because the new section pushed the printer below the fixed
test viewport — a test-only adjustment, not a behavior change.)

## Tests

- `test/features/backup/backup_model_test.dart` — envelope round-trip, invalid /
  corrupt / incompatible / missing-shopId / bad-schemaVersion / wrong-type
  container / non-map rows / settings damage, tolerant parsing, summary counts,
  settings codec round-trip + null + fallbacks.
- `test/features/backup/backup_file_store_test.dart` — write/list (newest-first)
  /collision suffix/read/delete/missing-file-safe/JSON-only filter/lazy dir
  create/file-name format.
- `test/features/backup/backup_repository_test.dart` — in-memory Drift:
  export snapshots full sale graph + settings; restore replaces target
  preserving IDs/FK + shop row untouched; receipt counter preserved; settings
  written after commit; empty-restore wipe; cross-shop rejected intact; schema
  mismatch rejected; missing shop rejected; corrupt row full rollback;
  settings-save failure → `BackupSettingsRestoreFailure` with data kept.
- `test/features/backup/backup_settings_test.dart` — widget tests for desktop +
  phone rendering, owner vs staff visibility, create+share flow, export-failure
  snackbar, restore list/preview/confirm, cancel, no-backups toast,
  corrupt-file error, restore-failure message. Uses an **in-memory fake
  `BackupFileStore`** (real `dart:io` futures do not resolve under the widget
  test's fake-async zone).
- `test/helpers/fake_backup_repository.dart` — configurable fake with
  `buildError` / `restoreError` / `restoreCalled` / `restored` recording.
- Existing tests preserved (not weakened).
- `dart format .` — clean · `flutter analyze` — No issues found ·
  `flutter test` — **1271 passed, 2 skipped** (baseline 1224 → 1271).

## Remaining issues / limitations

- **Cross-device restore NOT TESTED** — no second physical device; the
  envelope/restore logic is platform-independent and covered by repository
  tests, but a full device-to-device transfer was not verified here.
- **Hardware share-sheet NOT TESTED** — sharing goes through the existing
  `ShareService` abstraction (fake-verified only); the actual platform share
  sheet cannot be opened in this environment.
- Backups are stored on-device only (`<documents>/backups/`); there is no
  cloud copy. Users should share backups to keep an off-device copy.
