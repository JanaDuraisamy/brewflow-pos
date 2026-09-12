# Phase 6.1 — Multi-Business / `shopId` Schema + Sync Scoping

BrewFlow POS · Scope: per-shop schema (v17), shop-scoped master-data sync, FK-safe shop-row resolution

> **Status: READY**

## Verification chain

- `dart format .` — clean (changed Dart files).
- `flutter analyze` — **No issues found!**
- `flutter test` — **1341 passed, 2 skipped (pre-existing), 0 failures** ("All tests passed!").

## Objective

Resume the existing (uncommitted) working tree and finish validating Phase 6.1:
confirm the v17 multi-shop schema/migration chain is intact, fix genuine Phase 6.1
issues left over in the working tree, and prove the whole suite is green.

Only one commit exists in the repo (`128e055 chore: prepare BrewFlow for developer
handover`); ALL Phase 6.1 work lives in the working tree and was treated as the
source of truth. No files were reset/stashed/cleaned; no unrelated work was done.

## What was already present (verified intact)

- `Schema17` step class exists in
  `lib/core/database/drift_schemas/schema_versions.dart` (line 7680), matching
  `drift_schema_v17.json`.
- `AppMigrations.upgrade` wires `versions.stepByStep` up through `from16To17`
  (`lib/core/database/migrations/migrations.dart`), covering the per-shop additions,
  the `sale_sequences`/`purchase_sequences` re-creation to composite `(id, shop_id)`
  PKs, and the 10 legacy tables migrated from the `0000...` default to a canonical
  Cafe shop, backfilled and index-added.
- `categories.shop_id` nullable FK → `shops(id)` CASCADE; `purchase_sequences`
  composite PK `(id, shopId)` with `shopId` FK CASCADE; `purchase_items.shop_id`,
  `stock_movements.shop_id` nullable FKs → `shops`. All confirmed in the table
  definitions and the v17 dump.

## Genuine Phase 6.1 issues found & fixed

### 1. Sync tests never materialized the canonical shop row (FK failures)

**Root cause.** The Phase 6.1 sync tests created devices with an empty local
`shops` table while the session/outbox `shopId` was fixed (`'shop-1'` or `'shop'`).
`resolveWritableShopId` (`lib/core/database/shop_resolver.dart`) falls back to
auto-creating a **random-UUID** "Cafe" shop when `shops` is empty, so:

- the local `categories`/`products`/`sales` rows were written with a random UUID
  `shop_id`, while
- the outbox payloads carried the session `shopId`.

The push registered `shopId = '<session>'` on the cloud, and downstream devices
pulled shop-scoped rows whose `shop_id` FK referenced a `shops` row that did not
exist locally → `SqliteException(787): FOREIGN KEY constraint failed` during
application. This cascaded into ~17 failing tests across
`master_data_sync_test` (13), `jiggar_menu_seed_test` (2) and
`paid_sale_due_test` (2).

**Fix.** Mirror owner bootstrap exactly as the already-passing `shop_name_sync_test`
does — seed the canonical single-shop row with the session `shopId` on every
test device:

- `test/features/sync/master_data_sync_test.dart` — `makeDevice` (now `Future<Device>`)
  inserts a `shops` row with `id = shopId` before wiring the repositories/engine;
  every call site `await`s it.
- `test/features/inventory/jiggar_menu_seed_test.dart` — seeds a `shops` row with
  `id = 'shop'` on device A's DB and device B's fresh DB.
- `test/features/customers/paid_sale_due_test.dart` — the sync group's `setUp`
  seeds a `shops` row with `id = 'shop-1'` so the pulled `sales` FK resolves.

With a single canonical shop row present, `resolveWritableShopId` deterministically
returns the session shopId, so local writes, outbox payloads and pull-side FKs all
agree. **Result:** all 17 tests pass.

### 2. Concurrent purchase receives split across two shops (identical numbers)

**Root cause.** Phase 6.1 moved `resolveWritableShopId` **outside** the receiving
transaction in `drift_purchase_repository.dart`. When `receivePurchase` is invoked
concurrently (no explicit `shopId` on a fresh DB with an empty `shops` table), both
calls read "no shop" and each auto-created its **own** random-UUID Cafe shop before
their transactions serialized. The two receives therefore targeted different shops,
and each per-shop `purchase_sequences` counter returned `next_value = 1` → both
purchases got `PUR-000001` (the "concurrent single-item/multi-item receives are
additive and atomic" tests failed).

**Fix.** Resolve the writable shop id **inside** the receiving transaction
(`lib/features/purchases/data/drift_purchase_repository.dart`). Drift serializes
transactions, so the first receive creates the Cafe shop and the second reuses it;
both receives share one shop and one sequence, yielding distinct
`PUR-000001` / `PUR-000002`. This is the production-grade fix (the same race would
otherwise create duplicate shops if the write path ever ran concurrently before
bootstrap). **Result:** all 28 purchase-repository tests pass.

## Failures classified

| Failure location | Count | Classification | Resolution |
| --- | --- | --- | --- |
| `master_data_sync_test.dart` | 13 | Phase 6.1 regression | Free field fixed — missing shop-row seeding (Issue 1) |
| `jiggar_menu_seed_test.dart` | 2 | Phase 6.1 regression | Same root cause (Issue 1) |
| `paid_sale_due_test.dart` | 2 | Phase 6.1 regression | Same root cause (Issue 1) |
| `purchase_repository_test.dart` | 2 | Phase 6.1 regression | `resolveWritableShopId` race (Issue 2) |

No pre-existing failures or environment failures remained after the fixes.

## Notes / honest boundaries (outside Phase 6.1 scope)

- `DriftPurchaseRepository` still has **no outbox/sync integration** and
  `voidPurchase` does not thread a `shopId`. Per the task, this is noted as a
  potential concern but is **not** part of the Phase 6.1 scope (which is the
  schema + sync scoping of master data and purchases).
- The `~2` skipped tests are pre-existing and stable across runs; they are not
  related to this phase.

## Files changed (this session)

- `lib/features/purchases/data/drift_purchase_repository.dart` — resolve shop id
  inside the transaction (concurrency fix).
- `test/features/sync/master_data_sync_test.dart` — seed canonical shop row in
  `makeDevice`; await new `Future<Device>`.
- `test/features/inventory/jiggar_menu_seed_test.dart` — seed `shops` row on both
  devices.
- `test/features/customers/paid_sale_due_test.dart` — seed `shop-1` row in the sync
  group's `setUp`.
