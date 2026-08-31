# Development Guide

## Commands

Run from `brewflow_pos/`:

```bash
flutter pub get
dart format .            # format all Dart
flutter analyze          # lint + static type checks
flutter test             # full test suite
flutter run              # run app
flutter build apk --debug
```

`flutter analyze` is expected to report `No issues found!`.

## Code layout rules

- Keep the feature-first structure: `lib/features/<feature>/{presentation,domain,data}`.
- Put reusable pure logic in `domain/` (models, repository interfaces, failures).
- Put Drift repositories and external adapters in `data/`.
- Put Riverpod providers/controllers and widgets in `presentation/`.

## Conventions

- **Money**: always integer paise; format with `Money` helpers. Never float currency.
- **Tokens**: use `AppColors.*`, `AppSpacing.*`, `AppRadius.*`/`AppBorderRadius.*`.
  No raw color/style literals in UI code.
- **State**: prefer Riverpod `NotifierProvider`/`AsyncNotifierProvider` over ad-hoc state.
- **Private widgets**: if a private widget takes no key, write `const _MyWidget();` —
  do not add `super.key` (triggers `unused_element_parameter`).
- **No unnecessary comments** in code. Document *why* with doc comments only where it
  adds value, and update doc comments when behavior changes.

## Changing schema

1. Update the table definition in `lib/core/database/tables/<table>.dart`.
2. Bump the schema version and add a typed migration in
   `lib/core/database/migrations/migrations.dart`.
3. Regenerate Drift code (`dart run build_runner build` when `drift_dev` codegen is used)
   and update `drift_schemas/` snapshots.
4. Update this `docs/project/` set (DATABASE.md, SYNC.md, etc.) to match.

## Changing sync / business writes

- Master-data business changes must go through `SyncOutboxCoordinator.run()` so the write
  and outbox append commit atomically (see SYNC.md).
- Sales/saleItems/customerPayments are append-only and are never deleted via tombstones.
- Do not bypass or weaken the strict sync architecture for quick fixes.

## Changing authorization

- Add permissions to the `Permission` enum + its DB mapping in
  `lib/core/authorization/authorization.dart`.
- Default staff permissions live in the same location / `staff_models.dart`.
- Guard controller actions with `requirePermission` / `requireOwner`.

## POS stock rules

- Active zero-stock products stay visible on the shelf as "Sold out" — do not remove
  them from `posProductsProvider` (that was Bug 7.8E-B).
- The cart `add()` blocks stock <= 0 with `InsufficientStockFailure`.
- The checkout path has a `WHERE stock_quantity >= ?` SQL guard.

## Voiding sales

- Void restores stock, keeps the row marked voided, and reverses linked customer
  payments. It is Owner-only. Do not hard-delete voided sales.

## Verifying work

Before finishing a change, run, at minimum:

```bash
dart format .
flutter analyze
flutter test
```

If a non-trivial verification (e.g. `flutter build apk --debug`) is requested, run it too
and report the actual result.
