# Authorization

## Roles

- `UserRole.owner` — the shop owner; implicitly has **every** permission.
- `UserRole.staff` — limited by an explicit permission set.

## Permissions

`Permission` enum (`lib/core/authorization/authorization.dart`) with DB values:

| Permission | dbValue |
| --- | --- |
| `viewDashboard` | `VIEW_DASHBOARD` |
| `billing` | `BILLING` |
| `viewInventory` | `VIEW_INVENTORY` |
| `editInventory` | `EDIT_INVENTORY` |
| `stockAdjustment` | `STOCK_ADJUSTMENT` |
| `purchases` | `PURCHASES` |
| `suppliers` | `SUPPLIERS` |
| `customers` | `CUSTOMERS` |
| `customerLedger` | `CUSTOMER_LEDGER` |
| `expenses` | `EXPENSES` |
| `reports` | `REPORTS` |
| `orders` | `ORDERS` |
| `settings` | `SETTINGS` |
| `manageStaff` | `MANAGE_STAFF` |

`defaultStaffPermissions`: `{billing, viewInventory, customers, orders}`.

## Enforced helpers

All live in `lib/features/staff/presentation/staff_controller.dart`:

- `requirePermission(Ref ref, Permission p)` — throws `PermissionDeniedFailure` if the
  session lacks `p`.
- `requireOwner(Ref ref)` — throws `PermissionDeniedFailure` unless the signed-in profile
  is the owner.
- `canProvider` — `Provider.family<bool, Permission>` for widget-layer conditional UI.

## Service

`AuthorizationService` interface with `RoleBasedAuthorization` implementation
(`lib/core/authorization/authorization.dart`):

- `can(Permission)` — owner always true; staff checks `grantedPermissions`.
- `canForSession` — a null role returns true (for non-session contexts).

## Where it's used

- **Settings**: `SettingsController.save()` calls `requirePermission(ref, Permission.settings)`.
- **Backup/Restore**: `BackupSectionCard` / `MobileBackupSection` gate on
  `canProvider(Permission.settings)`; actions are also guarded by `_guardBackupAccess`.
- **Reports**: `ReportsController.build()` calls `requirePermission(ref, Permission.reports)`.
- **Deletes / voids**: guarded by `requireOwner(ref)`.

## Model

- `UserProfile` (`lib/features/staff/domain/staff_models.dart`): `id`, `email`,
  `authUserId?`, `shopId?`, `displayName?`, `role`, `isActive`, `permissions` (`Set<Permission>`),
  plus `isOwner` getter.
- `StaffPermissions` Drift table: composite PK (`userId`, `permission`), `enabled` bool.
- Staff management (create/update/set permissions) goes through `StaffRepository` /
  `DriftStaffRepository`.
