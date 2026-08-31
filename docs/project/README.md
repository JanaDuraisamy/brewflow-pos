# BrewFlow POS

A feature-first, offline-first retail point-of-sale (POS) app built with Flutter, Riverpod (3.x) and a local Drift (SQLite) database with optional Supabase cloud sync.

## What it does

- Run a full store POS off a single device with full offline capability.
- Sell items, track inventory, manage customers and their due/paid ledgers.
- Record purchases, suppliers, expenses, orders and staff.
- View reports, sales summaries, profit/loss and a live dashboard.
- Sync master data and transactions to a Supabase backend when online.
- Print/share receipts; back up and restore all business data as JSON.

## Project location

The Flutter app lives in `brewflow_pos/`. Reports and project docs live in `docs/`.

## Getting started

```bash
cd brewflow_pos
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

## Feature overview

| Feature | Responsibilities |
| --- | --- |
| Billing / POS | Product shelf, cart, checkout, holds/Resume, credit "Not Paid" sales, void sales |
| Inventory | Products, variants, categories, stock levels, low-stock / out-of-stock |
| Customers | Profiles, customer ledger with due/paid tracking |
| Orders | Full sale history with detail, print/share receipts, voided-sale badge |
| Reports | Sales summary, payment breakdown, expenses, profit/loss, top products |
| Dashboard | KPIs: day sales, profit, bills, low-stock, due customers, etc. |
| Purchases | Purchase orders and receipts adding to stock |
| Expenses | Expense tracking by category and payment method |
| Staff | Roles (owner/staff), permissions, profiles |
| Settings | Shop identity, low-stock threshold, theme, membership switch |
| Backup | JSON back-up and restore of all business tables |
| Printing | ESC/POS receipt formatting; printer transport adapter boundary |
| Sync | Outbox-based offline-first sync to Supabase |

## Architecture at a glance

- **Feature-first layout**: `lib/features/<feature>/{data,domain,presentation}`.
- **State**: Riverpod 3 (`NotifierProvider` / `AsyncNotifierProvider`).
- **Persistence**: Drift (SQLite), schema version 15, with typed migrations.
- **Design system**: `lib/core/theme/` — `AppColors`, `AppSpacing`, `AppRadius`, `AppShadows`, shared widgets in `lib/shared/`.
- **Authorization**: `Permission` enum + `RoleBasedAuthorization` (`lib/core/authorization/`), helpers in `lib/features/staff/presentation/staff_controller.dart`.

See [ARCHITECTURE.md](ARCHITECTURE.md) for details.

## Key behavior notes

- Active zero-stock products remain visible on the POS shelf and are shown as "Sold out"; the cart rejects them with `InsufficientStockFailure`.
- Voiding a sale restores stock, keeps the sale row marked voided, and reverses any linked customer payments.
- All money is stored as integer paise and formatted via `Money` helpers (never floating point).
- Deletes and voids are Owner-only.

## Verification

```bash
dart format .
flutter analyze    # expects: No issues found!
flutter test       # full suite (see TESTING.md)
flutter build apk --debug
```
