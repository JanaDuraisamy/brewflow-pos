# UI / Design System

## Theme tokens

Reusable tokens live in `lib/core/theme/`, with a single source of truth:

- `AppColors` — color palette (`lib/core/theme/app_colors.dart`). Notable tokens:
  - `error` (e.g. `DC2626`) used for destructive / voided states.
  - `success`, `warning`, surface/text/border tones, gradients.
- `AppSpacing` — spacing scale.
- `AppRadius` / `AppBorderRadius` — corner radii.
- `AppShadows`.

**Rule**: UI code uses `AppColors.*`, `AppSpacing.*`, `AppRadius.*`/`AppBorderRadius.*` —
never raw color/style literals.

## Shared widgets

Reusable building blocks in `lib/shared/`:

- `PageHeader` — screen title/heading.
- `SectionCard` / `AppCard` — content containers.
- `EmptyState`, `LoadingState`, `ErrorState` — standard async states.
- `SearchField` — search input.
- `AppFilterChip` — filter chips.

## Feature screens (notable)

### POS / Billing (`lib/features/billing/presentation/`)

- Product shelf cards. A card whose `remaining <= 0` renders **`Sold out`** in place of
  the Add action — active zero-stock products remain visible.
- Cart panel: line items with price, quantity controls, subtotal, discount, total.
- Payment methods (Paid / Not Paid) and "Complete Sale".
- Hold / Resume bill list.

### Orders (`lib/features/orders/presentation/`)

- `orders_page.dart`: order table tiles + `_OrderCard`. A `_VoidedBadge` (red pill with
  `AppColors.error` + `Icons.block`) renders next to `_PaymentBadge` when
  `order.isVoided`.
- `order_detail_page.dart`: detail header; a `_VoidedBadge` renders next to
  `_PaymentBadge` in the header `Row` when `order.isVoided`.

### Settings / Backup

- `SettingsController` (`AsyncNotifierProvider`) persists via
  `PreferencesSettingsRepository` (shared_preferences keys `settings_*`).
- `BackupSectionCard` / `MobileBackupSection` gate on `Permission.settings`.

### Auth shell

- `AuthShell` (`lib/features/auth/presentation/auth_shell.dart`): email/password form
  with validation and an `_ErrorBanner` for mapped failures.

## Theme preference

- `ThemePreference` enum: `system`, `light`, `dark`.
- `appThemeModeProvider` maps preference -> `ThemeMode`.
