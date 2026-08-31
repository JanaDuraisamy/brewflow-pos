# Architecture

## Layering

BrewFlow POS follows a feature-first, clean-architecture style:

```
lib/
  app/          App shell, router, top-level wiring
  core/         Cross-cutting: database, theme, authorization, services, utils
  features/     One folder per domain feature
  shared/       Reusable widgets / UI building blocks
```

Each feature is split into three layers:

```
lib/features/<feature>/
  presentation/   Widgets, controllers (Riverpod providers)
  domain/         Models, repository interfaces, failures
  data/           Drift repositories and other implementations
```

Dependencies point inward: `presentation -> domain`, and `data -> domain`. Controllers
expose Riverpod providers; widgets read them.

## State management (Riverpod 3)

- `NotifierProvider` for owned, mutable state (e.g. `SettingsController`, `AuthController`, cart).
- `AsyncNotifierProvider` for data loaded from repositories (e.g. `DashboardController`, `ReportsController`, `UserProfileController`).
- `Provider.family<bool, Permission>` for widget-layer authorization checks (`canProvider`).
- Providers are wired in a composition root (e.g. `backupRepositoryProvider`, `settingsRepositoryProvider`, `syncEngineProvider`).

## Persistence (Drift / SQLite)

- Schema version **15** in `lib/core/database/`.
- Tables live in `lib/core/database/tables/` (e.g. `sales`, `sale_items`, `products`, `product_variants`, `categories`, `customers`, `customer_payments`, `expenses`, `suppliers`, `purchases`, `purchase_items`, `stock_movements`, `users`, `shops`, `devices`, `staff_permissions`, `sync_outbox`, `sale_sequences`, `purchase_sequences`).
- Typed migrations in `lib/core/database/migrations/migrations.dart`; schema snapshots under `drift_schemas/`.
- Money is stored as integer paise. Prices/quantities never use floating point.

See [DATABASE.md](DATABASE.md) for the full schema and key migrations.

## Authorization

- `Permission` enum + `RoleBasedAuthorization` in `lib/core/authorization/authorization.dart`.
- Helpers `requirePermission(ref, p)`, `requireOwner(ref)`, and `canProvider` in `lib/features/staff/presentation/staff_controller.dart`.
- Default staff permissions: billing, viewInventory, customers, orders. The owner implicitly has every permission.

See [AUTHORIZATION.md](AUTHORIZATION.md).

## Sync (offline-first)

- Outbox pattern: business writes and outbox appends commit in one Drift transaction via `SyncOutboxCoordinator.run()`.
- `RemoteMasterDataGateway` (Supabase impl) pushes/pulls cursor-paged payloads; `LocalMasterDataApplier` applies them idempotently.
- Standalone (signed-out) operation degrades to plain local writes with no sync.

See [SYNC.md](SYNC.md).

## Backend (optional)

- Supabase: Postgres with row-level security. Tables: `categories`, `products`, `product_variants`, `suppliers`, `customers`, `sales`, `sale_items`, `expenses`, `customer_payments`, `master_deletions`, `devices`.
- Supabase Auth (`GoTrueClient`) for sign-in; refresh/session persistence is managed by Supabase.

## Authentication

- `AuthController` subscribes once to `authStateChanges`; starts at `initializing`, then `authenticated`/`unauthenticated`.
- `SupabaseAuthRepository` wraps `GoTrueClient`; it never stores or exposes tokens.
- `AuthShell` is the login UI. See [PROJECT_STATUS.md](PROJECT_STATUS.md) for the authentication contract.

## Themes and tokens

- Single source of truth in `lib/core/theme/app_colors.dart` and sibling theme files.
- UI code uses `AppColors.*`, `AppSpacing.*`, `AppRadius.*`/`AppBorderRadius.*` — never raw color/style literals.

## Design principles

- Feature code prefers compact repositories over bloated controllers.
- Controllers hold no business logic beyond orchestration; logic sits in domain models and repositories.
- New screens compose shared widgets (`PageHeader`, `SectionCard`, `EmptyState`, `LoadingState`, `ErrorState`, `SearchField`, `AppFilterChip`).
