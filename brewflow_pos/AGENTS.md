# BrewFlow POS — Repo Conventions

## Verification (always run before finishing work)

```bash
dart format .                  # code must be formatted
flutter analyze                # must report "No issues found!"
flutter test                   # full suite must stay green
```

Do not claim work is verified unless these commands actually pass.

## Architecture

- Feature-first layout: `lib/features/<feature>/{data,domain,presentation}`.
- `data/` holds repository implementations (Drift), `domain/` holds models,
  repository interfaces and failures, `presentation/` holds Riverpod
  controllers and Flutter UI.
- App-wide UI lives in `lib/app/`, cross-cutting infrastructure in
  `lib/core/`, cross-feature models in `lib/shared/`.

## State management (Riverpod 3)

- Use `Notifier` / `AsyncNotifier`; keep widget state minimal.
- Repositories are exposed through providers and **overridden with fakes in
  tests** (`test/helpers/`); never touch the real database in widget tests.
- Domain errors are sealed failure types with user-safe display-ready
  messages (e.g. `BillingFailure`). Checkout-style flows must preserve state
  (e.g. the cart) on failure.

## Design system — never hardcode raw values

- Colors: `AppColors.*` only (never `Colors.green`, never inline hex).
- Spacing: `AppSpacing.*` / `AppInsets.*` only (never `EdgeInsets.all(13)`).
- Radius: `AppRadius.*` / `AppBorderRadius.*` only (never
  `BorderRadius.circular(15)`).
- Shadows: `AppShadows.*`.
- Surfaces: `AppCard` / `SectionCard` from the widgets barrel
  `package:brewflow_pos/app/widgets/widgets.dart`.
  Exception: the POS shelf product card uses material `Card` because
  `pos_page_test.dart` locks `find.byType(Card)` for the Add button — keep it.
- Shared state views: `EmptyState`, `LoadingState`, `ErrorState`.
- Header: `PageHeader`, search: `SearchField`, filters: `AppFilterChip`.

## Tests are the contract

- `test/features/billing/pos_page_test.dart` and the rest of the suite assert
  exact user-visible strings, button types, and widget types
  (e.g. `find.widgetWithText(FilledButton, 'Complete Sale')`,
  `'Nothing on the shelf'`, `'1 in cart'`, `find.byType(Card)`).
- Never rename user-visible text, change button constructors
  (`FilledButton.icon` is not matched by `find.byType(FilledButton)`), or swap
  widget types without updating tests.
- Money formatting: integer paise, `Money.formatPaise`; never doubles.

## Data & persistence

- Drift for local SQLite; after editing tables run
  `dart run build_runner build --delete-conflicting-outputs`.
- Offline-first: the app must work with the local database; cloud sync
  (Supabase) is secondary.
- Secrets live in `.env` (see `.env.example`); never commit real secrets.

## General

- Keep changes scoped; no unrelated cleanup.
- Only commit when explicitly asked; never commit `.env` or build artifacts.
