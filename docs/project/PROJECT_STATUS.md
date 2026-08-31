# Project Status

Status snapshot as of **Phase 7.8E** (2026-08-31).

## Verdict

- `dart format .` — clean.
- `flutter analyze` — **No issues found!**
- `flutter test` — **All tests passed** (`+1278 ~2`, 2 skipped, 0 failures).
- `flutter build apk --debug` — see the Phase 7.8E report for the build result.

## What Phase 7.8E delivered

### Bug 7.8E-B — zero-stock products hidden from POS

- **Fix**: `posProductsProvider` in
  `lib/features/billing/presentation/billing_controller.dart` no longer filters out
  active zero-stock products. Active zero-stock products are now **visible** on the
  shelf and rendered as "Sold out".
- The cart still rejects them (`InsufficientStockFailure`), and checkout keeps its
  `WHERE stock_quantity >= ?` SQL guard, so nothing broken can be sold.
- Four POS page tests that previously asserted zero-stock products are hidden were
  updated to assert the corrected (visible) behavior — the fix was **not** reverted.

### Void-sale + Voided badge

- Schema migration 14 -> 15 adds `sales.voided` / `sales.voidedAt`.
- `voidSale` restores stock, keeps the row marked voided, and reverses linked
  customer payments (`reversed` + `reversedAt`); double-void throws
  `SaleAlreadyVoidedFailure`.
- `OrderSummary`/`Order` now carry `isVoided`/`voidedAt`; orders list + detail render a
  Voided badge (`AppColors.error` + `Icons.block`).

### Regression tests

- `billing_repository_test.dart` — new `voidSale` group (4 tests).
- `billing_controller_test.dart` — new POS zero-stock visibility group (2 tests).
- `orders_page_test.dart` — new Voided-badge test; `seedOrder` extended.
- `pos_page_test.dart` — updated to corrected zero-stock behavior.

### Documentation

- This `docs/project/` set created (11 files): README, ARCHITECTURE, DATABASE, SYNC,
  AUTHORIZATION, UI, BACKUP_RESTORE, PRINTER, TESTING, DEVELOPMENT_GUIDE, PROJECT_STATUS.

## Feature status

| Area | Status | Notes |
| --- | --- | --- |
| Billing / POS | Done | Cart + checkout, holds, Not Paid credit sales, stock-0 handling |
| Void sales | Done (7.8E) | Restores stock, keeps row, reverses payments, Owner-only |
| Orders | Done (7.8E) | History, detail, print/share, Voided badge |
| Inventory | Done | Low-stock / out-of-stock, variants, categories, stock ledger |
| Customers / Ledger | Done | Due/paid tracking, race-safe payment settlement |
| Reports | Done | Sales, payments, expenses, profit/loss, top products |
| Dashboard | Done | Day KPIs, low-stock/out-of-stock, due customers |
| Purchases | Done | Purchase orders + receipts |
| Expenses | Done | By category + payment method |
| Staff / AuthZ | Done | Owner/staff roles, permissions, enforced helpers |
| Settings | Done | Shop identity, low-stock threshold, theme, membership |
| Auth (Supabase) | Done | Email/password via GoTrue; session managed by Supabase |
| Sync | Done | Outbox offline-first, master-data + transactions |
| Backup / Restore | Done (7.8D) | JSON envelope, 14 business tables |
| Printing | Partial | ESC/POS encoder + service boundary; transport not yet verified |
| Reports/Auth contract | Contract | Repository-based; see individual docs |

## Known boundaries / honest notes

- Printing reports `PrintUnavailable` (the HOP-E200 hardware adapter is not yet verified;
  no transport ships).
- Backup never exports auth/users/shops/devices/staff_permissions/sync tables.
- Sync sales/saleItems/customerPayments are append-only and never delete-tombstoned.
- The app runs standalone when signed out; synchronized behavior requires Supabase.

## Related reports

- `docs/Phase_7.8B_Report.md`
- `docs/Phase_7.8B_Delete_Context_Actions_Report.md`
- `docs/Phase_7.8C_Printer_Report.md`
- `docs/Phase_7.8D_Backup_Restore_Report.md`
- Phase 7.8E FINAL REPORT (issue of this phase)
