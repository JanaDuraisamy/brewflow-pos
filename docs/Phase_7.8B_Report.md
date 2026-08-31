# Phase 7.8B — Product-Level Polish: Branding, Account Menu, Context Actions & Phone UX

BrewFlow POS · Offline-first Flutter POS with Supabase sync

## Overview

Phase 7.8B delivers the second wave of product-level UX work across both phone
(`<600dp`) and tablet (`>=600dp`) layouts. Phone-or-tablet specific behavior is
gated exclusively by `AppBreakpoint` (`width < 600` → compact), never by device
model. Every built-in user holds a real role and every destructive path is
guarded by an explicit confirmation surface.

## What changed

### 1. Business name vs. app display name

- `AppConstants.defaultAppDisplayName = 'BrewFlow'` in `lib/config/constants.dart`.
- `ShopSettings.appDisplayName` added to `lib/features/settings/domain/settings_models.dart`
  with persistence in `preferences_settings_repository.dart`
  (`_appDisplayNameKey`).
- Editable "App Display Name" row in `settings_page.dart`.
- `_MobileAppBar` (and the desktop shell wordmark) render the editable display
  name instead of a hardcoded constant, so branding is a runtime preference.

### 2. Account menu replaces avatar → Settings

- New `lib/app/widgets/account_menu.dart`: `AccountMenuButton` and
  `showAccountMenu` with **Profile**, **Change Account** and **Sign out**.
- Dashboard avatar tap now opens the account menu on every form factor; the
  settings shortcut moved into the menu itself.

### 3. OWNER full authorization at the data layer

Verified: the data layer (`lib/features/*/data/*`, Supabase RPC calls) contains
**zero authorization/branching logic**. `Owner` holds every `AppPermission`
value through the permission enum in the app layer. No code change required.

### 4. Long-press context action sheets (all six entities)

New shared helper `lib/app/widgets/context_actions.dart`
(`ContextMenuItem`, `showContextActionSheet`, `confirmDestructive`); exported
through the `widgets.dart` barrel. `AppCard` gained an `onLongPress` parameter.

| Entity | Sheets/actions |
| --- | --- |
| Products | Edit · Adjust Stock · Deactivate / Activate |
| Customers | View · Edit · Deactivate / Activate |
| Expenses | Edit · Deactivate / Activate |
| Orders | View Details |
| Suppliers | Edit · Deactivate / Activate |
| Purchases | View Details |

Applied to both the phone card and the tablet card variant of each entity.
`showContextActionSheet` pops the sheet before invoking the action, so
follow-up dialogs (edit, confirm) present cleanly.

### 5. Destructive-action confirmation surfaces

- `confirmDestructive(context, {title, subject, consequence, confirmLabel})`
  renders an `AlertDialog` with a red destructive `FilledButton`
  (`AppColors.error`).
- All deactivate paths (product/customer/expense/supplier, single or bulk) are
  guarded by it; **no entity supports deletion from the lists in this phase**.
  Activation is intentionally not confirmed (non-destructive).

### 6. Phone filter rows → filter sheet

New `lib/app/widgets/filter_sheet.dart`
(`FilterSheetButton(activeCount, onPressed)` + `showFilterSheet`), exported from
`widgets.dart`. On compact widths the crowded inline filter wraps are replaced
by a single button with an active-count badge that opens a bottom sheet with
the same controls plus a destructive Reset action.

- Inventory · Customers · Expenses · Orders · Suppliers (purchases already had
  a compact pattern).

### 7. Phone long-press multi-select / bulk mode (products)

- `_MobileInventoryView` (new `ConsumerStatefulWidget`) owns selection state on
  `<600dp`: a **Select** action joins the phone header; long-press on a product
  card toggles selection mode too.
- Selection shows check traits on cards, a `_SelectionBar` (count + close), and
  a `_BatchActionBar` with **Activate** / **Deactivate**.
- Bulk **Deactivate** requires the destructive confirmation; bulk activate is
  immediate. No bulk deletion exists (non-destructive only).
- Desktop/tablet inventory is untouched.

### 8. Layout boundaries

All phone-only changes live behind compact (`<600dp`) branches; tablet/desktop
render exactly the prior layouts (only interactions added, no visual redesign).

## Verification

- `dart format .` — 329 files, no changes required (clean).
- `flutter analyze` — **No issues found.**
- `flutter test` — **1218 passed, 2 skipped** (baseline 1184 → 1206 → 1218).

New telephony-added coverage:

- `mobile_inventory_layout_test.dart` — 36 tests (long-press sheets, filter
  sheet, bulk select/confirm/cancel at 360–480dp).
- `mobile_customers_layout_test.dart` — 8 tests.
- `mobile_expenses_layout_test.dart` — 14 tests.
- `mobile_orders_layout_test.dart` — 7 tests.
- `mobile_purchases_suppliers_layout_test.dart` — 9 tests.
- Branding + account-menu coverage inside settings/dashboard suites.

Phone tests run explicitly at 360/375/390/411/430/480dp; the default 800×600
test surface exercises tablet/desktop paths in the same suite.

## Files

- `lib/config/constants.dart`
- `lib/app/widgets/{account_menu,context_actions,filter_sheet}.dart`
- `lib/app/widgets/widgets.dart`, `lib/app/widgets/app_card.dart`
- `lib/app/shells/app_shell.dart`
- `lib/features/settings/{domain/settings_models,data/preferences_settings_repository,presentation/settings_page}.dart`
- `lib/features/{inventory,customers,expenses,orders,purchases}/presentation/*.dart`
- Tests: `test/features/*/{mobile_*_layout_test.dart, ...}`

## Notes

- No schema changes; settings persistence is additive (nullable default).
- Owner/role checks remain in the app layer only; per Task 3 no data-layer
  branching was introduced.