# Sync

Offline-first sync to Supabase uses a transactional outbox pattern. Synchronized
operation is optional; a signed-out device runs fully standalone.

## Outbox pattern

- `SyncOutbox` Drift table with `status` (PENDING/IN_FLIGHT/DONE/FAILED), `attemptCount`,
  `lastAttemptAt`, `lastError`, `createdAt`, and deterministic IDs
  (`obx|shop|op|entity|id`) that collapse replayed pending changes.
- `SyncOutboxCoordinator.run({write, snapshots})`
  (`lib/features/sync/data/sync_outbox_coordinator.dart`) runs the business write and the
  outbox appends in **one** Drift transaction — they commit or roll back together.
- When no `SyncSessionContext` resolves (signed out / tests), it degrades to plain local
  writes with no outbox entries.
- An `onEnqueue` callback fires a debounced fast-sync kick after each enqueue.

## Engine

- `SyncEngine.runCycle({deviceId, shopId})`:
  1. Category reconciliation (resolve local/cloud collisions, adopt canonical category).
  2. PUSH — drain the outbox FIFO in batches; mark DONE, or FAILED after `maxAttempts = 8`.
  3. PULL — categories -> products -> variants -> suppliers -> customers -> sales ->
     saleItems -> expenses -> customerPayments -> deletions, each page applied atomically.
- Reentrant `runCycle` calls collapse (a cycle already in flight is not duplicated).
- Offline-first: a failed cycle changes nothing except retry bookkeeping.

## Gateway

- `RemoteMasterDataGateway` (`lib/features/sync/domain/master_data_gateway.dart`) is the
  pull/push interface; `SupabaseMasterDataGateway` implements it over `SupabaseClient`.
- Pushes use `onConflict: 'id'`; pulls are cursor-based, ascending by `updated_at`
  (`gt(updated_at, since)`).
- RLS is enforced server-side via `user_profiles`.

## Local applier

- `LocalMasterDataApplier` (`lib/features/sync/data/local_master_data_applier.dart`)
  applies pulled pages idempotently with UUID upserts into Drift.
- **Pending-local-wins**: rows with a local PENDING outbox entry are skipped on pull.
- Category collisions are resolved by renaming the local duplicate, inserting the
  canonical, then repointing products + outbox payloads.
- Deletions: categories hard-delete when unreferenced, else soft-deactivate; other
  master-data entities soft-deactivate (`isActive = false`). Sales/saleItems/
  customerPayments are append-only and never deleted.
- Product images are never overwritten by sync.

## Delete tombstones

- Local deletes write an outbox entry with `operation: 'DELETE'`.
- Pushes call `_gateway.recordDeletion(SyncDeletion(...))` into `master_deletions`.
- Pulls `_drainDeletions` from `master_deletions` and apply locally.
- DELETE is supported for category, product, productVariant, supplier, customer, expense.
  It is **not** supported for sale, saleItem, or customerPayment.

## Controller / session

- `SyncSessionController` (`lib/features/sync/presentation/sync_controller.dart`)
  lifecycle: `idle -> preparing -> active`. Watches `userProfileProvider` +
  `authRepositoryProvider`.
- On an active session: ensures device registration (local + cloud), pushes cloud
  identity, revives FAILED outbox entries, starts periodic 30-second sync cycles, and
  watches connectivity for catch-up. Fast-sync (2-second debounce) fires on every outbox
  enqueue and on connectivity restore.

## Providers

`syncGatewayProvider`, `remoteDeviceGatewayProvider`, `syncRepositoryProvider`,
`localMasterDataApplierProvider`, `syncEngineProvider`,
`deviceRegistrationCoordinatorProvider`, `syncOutboxCoordinatorProvider`, `syncKickProvider`.
