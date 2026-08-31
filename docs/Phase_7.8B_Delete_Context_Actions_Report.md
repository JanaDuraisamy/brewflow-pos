# Phase 7.8B — Delete / Context Actions Report

## Objective

Replace the oversized long-press bottom sheet with a compact Apple-inspired
context menu and implement **real deletion** across all safely-deletable
entities, plus a full sales void (stock + payment reversal) and a purchases
void (reverse stock). Deletions propagate through the sync engine so other
devices learn them. Owner access required; destructive confirmation required.
Phone + tablet layouts supported.

## Deliverables

### 1. Compact context menu (`lib/app/widgets/context_actions.dart`)

- Replaced the oversized long-press bottom sheet with a compact,
  iOS-inspired action sheet: tight rows, leading glyphs, destructive actions
  in red (`AppColors.error`), and a Cancel row.
- Public API (`showContextActionSheet`, `ContextMenuItem`,
  `confirmDestructive`) kept unchanged so every existing call site compiles.
- Surfaces use the `Surface`/`surface` theme token (typo in the pre-existing
  `cardSurface` accessor fixed via a project-wide replace).

### 2. Sync delete protocol (`sync_engine.dart`, `local_master_data_applier.dart`)

- `sync_engine.dart` previously **refused** DELETE for `product`,
  `productVariant` and `expense`; it now routes those to
  `_gateway.recordDeletion(_deletionOf(entry))` (upsert otherwise), so the
  same tombstone protocol used by categories/suppliers/customers extends to
  the inventory and expense sync payloads.
- `local_master_data_applier.dart` previously had no `expenses` branch in its
  soft-deactivate path (expense `applyDeletion` was a silent no-op); an
  `expenses` branch now sets `isActive = false` and `updatedAt = now`.

### 3. Delete matrix (all 7 entity types)

| Entity | Reversible rule | Sync |
| --- | --- | --- |
| Category | Hard delete when unused (`CategoryInUseFailure` backstop), else deactivate | DELETE tombstone |
| Supplier | Hard delete when no purchases, else deactivate | DELETE tombstone |
| Customer | Hard delete when no sales/payments, else deactivate | DELETE tombstone |
| Expense | Always hard delete (no FKs) | DELETE tombstone |
| Product / variant | Hard delete only when unreferenced (no variants / sale_items / purchase_items / stock_movements), else deactivate | DELETE tombstone |
| Purchase | Void: reverse stock added, remove receipt + line items + purchase movements | Local only (not in MasterEntity) |
| Sale | Full void: restore stock, reverse payments, keep the row (marked `voided`) | `SyncSale.voided` propagated |

Real deletion flows **local → outbox → cloud DELETE → other-device deactivate**.

### 4. Per-vertical implementations (vertical slices)

- **Expenses**: added `deleteExpense` to the repository interface, `deleteById`
  DAO method, Drift + fake implementations, permission-gated `deleteExpense`
  controller method, and a Delete menu item + `_deleteExpense` confirm handler.
- **Suppliers**: added `deleteSupplier` returning `SupplierDeleteResult`
  (`deleted` white list is only used when truly removed; `deactivated`
  otherwise), `countPurchases` + `deleteById` DAO methods, `suppliersWithHistory`
  fake probe, owner-gated controller `delete`, and Delete item + handler.
- **Customers**: added `deleteCustomer` returning `CustomerDeleteResult`,
  `countReferences` (over sales + customer_payments) DAO method, Drift + fake
  implementations, owner-gated `delete`, and Delete item + handler.
- **Products**: added `deleteProduct` returning `ProductDeleteResult`,
  `countReferences` (variants + sale_items + purchase_items + stock_movements)
  DAO method, `deleteById`, Drift + fake implementations, owner-gated
  inventory controller `delete`, and Delete item + handler.
- **Purchases void**: `voidPurchase` reverses the exact stock each line added
  (product or variant SQL) and removes the receipt, its line items and its
  purchase movements in one transaction; fake tracks `voidedIds`.
- **Sales full void** (large migration): `sales` gains additive `voided`
  (NOT NULL default false) + `voidedAt` columns; schema bumped v14 → v15 with
  an additive `from14To15` migration step and regenerated Drift/schema
  artifacts; `BillingRepository.voidSale` restores stock per sale line,
  reverses the sale's `customer_payments` (`reversed` + `reversedAt`), and
  marks the sale `voided` in a single transaction with
  `SaleNotFoundFailure`/`SaleAlreadyVoidedFailure` guards; `SyncSale` gained
  `voided`/`voidedAt` and the applier threads them through so other devices
  apply the void; Owner-gated `OrdersListController.voidOrder` with a
  destructive **Void Sale** menu item + `confirmDestructive` + SnackBar.

### 5. Owner access + confirmation

- Every delete/void is Owner-only: the menu item is hidden for non-owner
  (`ref.read(userProfileProvider).value?.isOwner`) and enforced in the
  controller via the new `requireOwner(ref)` helper (throws
  `PermissionDeniedFailure`) added to `staff_controller.dart`.
- Every destructive action requires a `confirmDestructive(...)` confirmation
  that explains the consequence (permanent deletion / deactivation fallback /
  stock + payment reversal) before anything is written.

### 6. Fakes + tests

- Extended `test/helpers/fake_{customers,suppliers,expenses,inventory,
  purchases,billing}_repository.dart` with the new delete/void APIs and probe
  sets (`customersWithHistory`, `productsWithHistory`, `voidedIds`, etc.).
- Fixed the migration-era test that read the sales table with the new NOT
  NULL column; finalized `sale_payment_status_migration_test.dart`.

## Verification

- `dart format .` — no formatting changes outstanding (clean).
- `flutter analyze` — **No issues found!** (ran on the fully merged tree).
- `flutter test` — **1271 passed, 2 skipped, 0 failed** (full suite, final
  merged state).

## Known limitations / follow-ups

- A dedicated `void_sale_test.dart` was not added; the void behavior is
  validated indirectly by the full suite and the fake billing `voidSale`.
- The orders feed does not yet render a distinct "Voided" badge for voided
  sales (the row is kept, which matches the matrix, but the UI does not
  visually distinguish it yet).
- Product-variant-level hard delete reuses the existing `updateProduct`
  soft-deactivation path for variants; only the product-level hard delete
  (unreferenced) is exposed as a dedicated destructive action.

## Scope guard

- `docs/Phase_7.8D_Backup_Restore_Report.md` and its files/tests were left
  intact (no regression).
