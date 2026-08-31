# BrewFlow POS

Offline-first, multi-device point-of-sale system for cafés and small retail.
Built with Flutter (Dart 3.12+), Riverpod for state, Drift for local SQLite
storage, and Supabase for cloud sync.

## Features

- **Dashboard** — key business metrics (sales, orders, revenue) refreshed from
  live repository data.
- **Inventory** — manage products, categories, and stock levels with search,
  filters, and responsive card/table layouts.
- **Billing & POS** — searchable product shelf with category filters, cart with
  quantity steppers and stock caps, cash/UPI/bank payment selection, checkout,
  and receipt summary.
- **Orders** — order list and detail views with status handling and filtering.
- **Customers** — customer profiles with search, status filters, and
  responsive card/table layouts; optional detail fields with unique-when-present
  phone numbers.
- **Expenses** — expense records with category and payment-method dropdowns,
  date presets, search, soft deactivation, and responsive card/table layouts;
  amounts stored in paise.
- **Auth** — secure sign-in backed by secure storage; the app shows the right
  surface for signed-in / signed-out states.

## Architecture

Feature-first layout under `lib/`:

```
lib/
├── app/            # App-wide UI: shells, shared widgets (design system), pages
├── core/           # Database (Drift), network, storage, router, theme, utils
├── features/       # Feature modules: auth, billing, dashboard, inventory,
│                   #   orders, customers, expenses, reports, settings, splash
│   ├── data/       #   repository implementations (Drift, fakes in tests)
│   ├── domain/     #   models, repository interfaces, failures
│   └── presentation/ # Riverpod controllers + Flutter UI
└── shared/         # Cross-feature enums, models, providers, repositories
```

### Conventions

- **State**: Riverpod 3 (`Notifier` / `AsyncNotifier`). Controllers live in
  `presentation/`; repositories are injected via providers and overridden with
  fakes in tests.
- **Design system**: never hardcode colors, spacing, radius, or shadows —
  use `AppColors`, `AppSpacing`/`AppInsets`, `AppRadius`, `AppShadows`, and the
  shared widgets (`AppCard`, `SearchField`, `AppFilterChip`, `PageHeader`,
  `EmptyState`/`LoadingState`/`ErrorState`) from
  `package:brewflow_pos/app/widgets/widgets.dart`.
- **Money**: integer paise everywhere; format with `Money.formatPaise`. Never
  use doubles for currency.
- **Failures**: domain errors are typed, sealed failures with user-safe,
  display-ready messages (e.g. `BillingFailure`).
- **Tests**: the widget/unit suite is the contract — user-visible strings,
  button types, and widget types are asserted and must not be renamed without
  updating tests.

## Getting started

```bash
flutter pub get
cp .env.example .env   # configure secrets before running
```

## Code generation

Drift tables, freezed models, and Riverpod generators:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Verification

```bash
dart format .                  # code must be formatted
flutter analyze                # must report "No issues found!"
flutter test                   # full suite (405 tests) must stay green
```

## Building

```bash
flutter build apk --release    # release APK
```
