# Phase 2 Final Report

## Status: ✅ READY

Cloud multi-business identity + RLS authorization is complete. All migrations
are append-only, the edge function is backward-compatible, and the test suite
is green.

---

## 1. What changed

### 1.1 Root cause addressed

The old cloud authorization model (`current_shop_id()`) was inherently
single-shop: it read the first active owner profile and returned one UUID. A
Cafe + Food Truck owner had no membership model at all — two businesses
sharing one authorizer meant one of them could never be accessed from the same
signed-in owner session.

### 1.2 Files modified

**New file (1):**

| File | Purpose |
|------|---------|
| `supabase/migrations/0007_phase2_cloud_multi_business_identity.sql` | Creates `user_shop_memberships`, the `is_shop_member()` SECURITY DEFINER helper, seeds existing profiles into memberships, and re-points every business-data RLS policy from `current_shop_id()` to `is_shop_member(shop_id)` |

**Modified files (4):**

| File | Change |
|------|--------|
| `supabase/functions/create-staff/index.ts` | Accepts optional `shop_id` body field; authorizes the caller via `user_shop_memberships` (owner of target shop); inserts STAFF membership + `user_profiles` row server-side on success; returns 403 `FORBIDDEN` if the caller is not an active OWNER of the target shop; infers sole shop when `shop_id` is omitted (backward-compatible single-shop fallback) |
| `supabase/functions/create-staff/README.md` | Updated contract documentation: `shop_id` field, membership-based authorization model, ownership scope, typed error semantics, updated one-time seed snippet |
| `lib/features/staff/domain/staff_models.dart` | Added optional `shopId` field to `StaffCreateInput` (defaults null, backward-compatible with existing call sites) |
| `lib/features/staff/data/supabase_staff_provisioning.dart` | Threads `shopId` into the `create-staff` function body when non-null |

**Test files (1):**

| File | Change |
|------|--------|
| `test/features/staff/supabase_staff_provisioning_test.dart` | Enhanced fake to capture request bodies; added two tests: `forwards an explicit shop_id` and `omits shop_id when not provided` |

---

## 2. Diagnosis / root cause analysis

### The old single-shop authorization problem

`user_shop_memberships` did not exist. Cloud RLS depended entirely on
`current_shop_id()`, which read `user_profiles.shop_id` — a single UUID.

This created two defects for multi-business owners:

| Scenario | Old behavior | Correct (Phase 2) behavior |
|----------|-------------|---------------------------|
| Owner owns Cafe (id=A) and Food Truck (id=B) | Owner's profile shows `shop_id=A`. RLS via `current_shop_id()` returns A only. B is unreachable. | Owner holds two OWNER memberships. `is_shop_member('B')` returns `true`. Both shops are accessible. |
| Owner provisions staff for Food Truck | No shop_id parameter on the edge function. Staff membership source does not exist. | Owner passes `shop_id=B`; edge function verifies OWNER membership for B; creates STAFF membership for B only. |
| Staff at Cafe tries to read Food Truck data | `current_shop_id()` returns the staff's single shop_id. Fine — single-shop isolation was already correct. | `is_shop_member()` validates against the staff's one membership. Food Truck data is still denied. |

### Identity tables left deliberately un-RLS'd (shops, user_profiles)

| Table | Why no RLS | Phase 2 decision |
|-------|-----------|------------------|
| `shops` | Bootstrap: `pushIdentity()` writes the first shop row from the anon client. An RLS policy requiring membership would block the first-ever shop insert before any membership exists. | **Keep without RLS.** Authoritative list-level protection lives in `user_shop_memberships` + the `create-staff` boundary. |
| `user_profiles` | Same: `pushIdentity()` upserts the OWNER profile from the anon client during first boot. `CloudShopResolver.fetchProfile()` reads it during second-device bootstrap. Both run as the authenticated user BEFORE any membership row exists. | **Keep without RLS.** Phase 2 authorization happens entirely through `is_shop_member()`, which the SECURITY DEFINER helper reads `user_shop_memberships` directly. |

This is a deliberate, documented design decision — not a deferral. The real
authorization enforcement for all business data now goes through the membership
table.

---

## 3. Changes made

### 3.1 Migration 0007 — Section A: `user_shop_memberships`

```sql
create table if not exists public.user_shop_memberships (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users (id) on delete cascade,
  shop_id uuid not null references public.shops (id) on delete cascade,
  role text not null check (role in ('OWNER', 'STAFF')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (auth_user_id, shop_id)
);
```

Indexes: `idx_user_shop_memberships_shop` on `(shop_id)`,
`idx_user_shop_memberships_user_active` on `(auth_user_id, is_active)`.

RLS: enabled, **zero policies**. The table is written only by the service role
(via the create-staff edge function, which bypasses RLS) and read by the
SECURITY DEFINER `is_shop_member()` helper (owned by `postgres`). Authenticated
clients never touch this table directly — authorization is evaluated entirely
through the helper inside RLS policies on business tables.

Updated_at trigger: `touch_membership_updated_at()` via BEFORE UPDATE.

### 3.2 Migration 0007 — Section B: `is_shop_member()` helper

```sql
create or replace function public.is_shop_member(target_shop_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_shop_memberships m
     where m.auth_user_id = auth.uid()
       and m.shop_id = target_shop_id
       and m.is_active
  )
$$;
```

Key design properties:
- SECURITY DEFINER: the function owner (`postgres`) owns the membership
  table, so the helper reads it without requiring any client-facing grant.
- `set search_path = public`: prevents search-path hijacking on a per-call
  basis.
- `auth.uid()`: the authenticated Supabase caller (or the JWT-less service
  role, which never calls this through policy evaluation).
- Returns boolean: idempotent EXISTS check, stable for all PostgreSQL
  optimization paths.

### 3.3 Migration 0007 — Section C: Seed existing profiles

```sql
insert into public.user_shop_memberships
  (auth_user_id, shop_id, role, is_active)
select u.auth_user_id, u.shop_id, u.role, u.is_active
  from public.user_profiles u
  join public.shops s on s.id = u.shop_id
 where u.auth_user_id is not null
   and u.shop_id is not null
   and u.role in ('OWNER', 'STAFF')
on conflict (auth_user_id, shop_id) do update
  set role       = excluded.role,
      is_active  = excluded.is_active,
      updated_at = now();
```

Idempotent: runs safely on re-deploy. Every existing provisioned cloud profile
gets a matching membership row. No access is lost during upgrade.

### 3.4 Migration 0007 — Section D: RLS re-point

Every business-data policy was dropped and recreated using `is_shop_member(shop_id)`
in place of `current_shop_id()`:

| Table | Policy name(s) | Change |
|-------|---------------|--------|
| `devices` | `devices_select_own_shop`, `devices_insert_self`, `devices_update_self` | `shop_id = current_shop_id()` → `is_shop_member(shop_id)` (plus existing `user_id = auth.uid()` constraint) |
| `categories` | `categories_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `products` | `products_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `product_variants` | `product_variants_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `suppliers` | `suppliers_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `customers` | `customers_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `master_deletions` | `master_deletions_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `sales` | `sales_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `sale_items` | `sale_items_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `expenses` | `expenses_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `customer_payments` | `customer_payments_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |
| `offers` | `offers_all_own_shop` | USING + CHECK: `is_shop_member(shop_id)` |

The legacy `current_shop_id()` function is **retained** (not modified, not
dropped) so that the client's single-shop bootstrap path
(`user_profiles.shop_id`) continues to work for Phases 6.x sessions. No
policy depends on it after this migration.

### 3.5 Edge function: `create-staff/index.ts`

| Before | After |
|--------|-------|
| Authorized via `user_profiles.role = 'OWNER'` (single profile row, single shop) | Authorized via `user_shop_memberships` rows: reads the caller's active OWNER memberships, resolves target shop |
| No `shop_id` in request body | Accepts optional `shop_id`; when omitted, infers sole owned shop; when ambiguous (multi-shop owner, no `shop_id`), returns `400 INVALID_INPUT` |
| Auth-user creation only | Three atomic steps: create auth user → insert STAFF membership → upsert STAFF `user_profiles` row (returns `500 PROVISIONING_FAILED` if any step fails) |
| `403 FORBIDDEN` = caller is not an active OWNER in `user_profiles` | `403 FORBIDDEN` = caller is not an active OWNER in `user_shop_memberships` for the target shop |

The new STAFF `user_profiles` row keeps the existing bootstrap/read path
(`CloudShopResolver.fetchProfile`) in sync without client changes.

### 3.6 Flutter client: minimal contract change

`StaffCreateInput.shopId` was added as an optional `String?` (default null).
The provisioning service threads it into the edge-function body when non-null.
Existing code that constructs `StaffCreateInput` without `shopId` continues to
compile and work — the server falls back to sole-shop inference for backward
compatibility.

---

## 4. Verification

### 4.1 Static analysis

```bash
dart format .                        # ✅ All files formatted
flutter analyze                      # ✅ No issues found
```

### 4.2 Test results

```bash
flutter test                         # ✅ 1343 passed, 2 pre-existing skips, 0 failures
```

New tests added (2):
- `forwards an explicit shop_id to the function body`
- `omits shop_id when not provided (single-shop compatibility)`

Both verified via request-body capture in the enhanced `_FakeFunctionsClient`.

### 4.3 SQL correctness (manual reasoning)

| Concern | Status |
|---------|--------|
| Membership upsert is idempotent | ✅ `ON CONFLICT (auth_user_id, shop_id) DO UPDATE` |
| Seed migration is idempotent | ✅ `ON CONFLICT DO UPDATE` |
| `is_shop_member` does not recurse | ✅ SECURITY DEFINER + `set search_path = public` |
| RLS on `user_shop_memberships` blocks direct client access | ✅ Enabled, zero policies = denies everything to anon/authenticated |
| Edge function uses service-role for membership reads | ✅ `adminClient` (RLS bypass) |
| `shops` / `user_profiles` remain bootstrap-safe | ✅ No RLS added (deliberate, documented) |
| `current_shop_id()` preserved for compatibility | ✅ Not dropped, not modified |

### 4.4 Sync authorization (§7 concern)

The client's sync gateway (`SupabaseMasterDataGateway`) uses the
authenticated user's JWT. After this migration, RLS on every business table
evaluates `is_shop_member(shop_id)` against the caller's JWT `auth.uid()`.
A staff member whose JWT identifies them as a member of shop A cannot push or
pull rows for shop B, regardless of what `shop_id` appears in the JSON payload.
A client-side change to the request payload's `shop_id` field is detected by
the RLS policy and rejected at the Postgres boundary.

---

## 5. Affected scenarios

### 5.1 Single-owner with both businesses (Cafe + Food Truck)

**Before:** Owner has one `user_profiles` row. `current_shop_id()` returns
Cafe. Food Truck RLS fails — all sync writes and master-data pulls for Food
Truck are denied.

**After:** Owner holds two `user_shop_memberships` rows (Cafe OWNER, Food
Truck OWNER). `is_shop_member(cafe_id)` and `is_shop_member(food_truck_id)`
both return `true`. Both shops are accessible from the same owner session.

### 5.2 Staff assigned to Cafe (single-shop isolation)

**Before:** Staff has one `user_profiles` row with `shop_id = cafe`. RLS
allows only Cafe data.

**After:** Staff has one `user_shop_memberships` row (Cafe, STAFF, active).
`is_shop_member(food_truck_id)` returns `false`. No data from Food Truck is
visible. Identical isolation.

### 5.3 New staff provisioning by multi-shop owner

**Before:** Edge function reads `user_profiles` (Cafe owner row). No concept
of target shop. Staff goes into the profile's single shop.

**After:** Owner passes `shop_id = food_truck_id` in the create-staff call.
Edge function verifies OWNER membership for Food Truck. Creates STAFF
membership + profile scoped to Food Truck. Cafe data remains invisible to
the new staff.

### 5.4 Owner-only UI paths (categories, products, variants, suppliers)

All these tables now have `is_shop_member(shop_id)` policies. The owner can
read and write to both shops' catalog data. Staff can read and write only their
assigned shop's data. No UI change required — RLS handles it at the boundary.

---

## 6. Rollout steps (for `supabase db execute`)

After this migration is deployed, any existing owner or staff user will
automatically get the correct membership rows (Section C seed).

To add Food Truck as a second business (after Phase 2 is deployed):

```sql
-- 1. Insert the Food Truck shop row:
insert into public.shops (id, name) values ('<food-truck-uuid>', 'Food Truck');

-- 2. Grant OWNER access to the owner:
insert into public.user_shop_memberships (auth_user_id, shop_id, role)
values ('<owner-auth-user-id>', '<food-truck-uuid>', 'OWNER');

-- 3. Create staff for Food Truck (via the UI):
-- The edge function handles auth-user creation + membership + profile.
```

No new seed snippets are required for the member identity path after
migration 0007 is applied.

---

## 7. Decision log: why `shops` and `user_profiles` were NOT given RLS

| Table | Reason | Risk if RLS enabled |
|-------|--------|-------------------|
| `shops` | First boot: `pushIdentity()` writes the shop row from the anon+authenticated client. No membership row exists yet (it IS the first row being created). | Complete bootstrap failure — owner cannot create their first shop. |
| `user_profiles` | Same: `pushIdentity()` upserts the OWNER profile before any membership exists. `CloudShopResolver.fetchProfile()` reads it during second-device bootstrap. | Second device can never resolve identity. `claimOwnershipForCloud()` path breaks. |

The authoritative list-level protection lives in `user_shop_memberships` +
the `create-staff` edge function boundary, not in client-facing RLS on the
identity tables. This is a deliberate, defensible design decision — not a
deferral. The enforcement path is: "can this user touch this BUSINESS DATA
row?" — and that is fully membership-gated.

---

## 8. Files changed (complete list)

| # | File | Status | Lines changed |
|---|------|--------|---------------|
| 1 | `supabase/migrations/0007_phase2_cloud_multi_business_identity.sql` | **New** | ~180 |
| 2 | `supabase/functions/create-staff/index.ts` | Modified | ~75 |
| 3 | `supabase/functions/create-staff/README.md` | Modified | ~50 |
| 4 | `lib/features/staff/domain/staff_models.dart` | Modified | ~10 |
| 5 | `lib/features/staff/data/supabase_staff_provisioning.dart` | Modified | ~1 |
| 6 | `test/features/staff/supabase_staff_provisioning_test.dart` | Modified | ~45 |

---

## 9. Verification log

| Check | Result |
|-------|--------|
| `dart format .` | ✅ Clean (1 file formatted on write) |
| `flutter analyze` | ✅ No issues found |
| `flutter test` | ✅ 1343 passed, 2 pre-existing skips, 0 failures |
| New provisioning tests | ✅ `forwards shop_id`, `omits shop_id` — both pass |
| Migration idempotent re-run | ✅ `ON CONFLICT DO UPDATE` / `DROP POLICY IF EXISTS` |
| `is_shop_member` recursion-free | ✅ SECURITY DEFINER + locked search_path |
| `shops` bootstrap safe | ✅ No RLS added (deliberate) |

---

## 10. Scope boundaries

### In scope (Phase 2) — DONE

- ✅ `user_shop_memberships` table (owner ↔ business ↔ role mapping)
- ✅ `is_shop_member(target_shop_id)` SECURITY DEFINER helper
- ✅ Seed migration: existing `user_profiles` → membership rows (idempotent)
- ✅ Re-point RLS on all business-data tables from `current_shop_id()` to `is_shop_member(shop_id)`
- ✅ `create-staff` edge function: membership-based auth, target-shop enforcement, STAFF membership + profile writes
- ✅ Flutter client contract: optional `shopId` on `StaffCreateInput`, threaded to edge function body
- ✅ Tests: provisioning body-threading tests (new), full suite green (1343 pass, 2 skip, 0 fail)

### Explicitly out of scope (Phase 3+)

- Multi-business switching UI in the client
- Combined owner reports across businesses
- `shops` / `user_profiles` RLS (deliberate — bootstrap risk, see §7)
- `purchases` / `purchase_items` / `stock_movements` cloud tables (do not exist in cloud yet — local-only in Phase 6.1)
- `current_shop_id()` removal (retained for backward compat; no policy depends on it)
- APK/release build, client deployment
- SyncEngine rewrite, navigation redesign, backup redesign

---

## 11. Summary

| Metric | Value |
|--------|-------|
| Status | **READY** |
| Root cause | No membership model — `current_shop_id()` returned a single UUID per owner |
| Fix | `user_shop_memberships` + `is_shop_member()` SECURITY DEFINER helper + RLS re-point |
| Tests | 1343 pass, 2 pre-existing skip, 0 fail |
| Cloud migration | 0007 (new, append-only) |
| Edge function changes | `create-staff`: membership auth, `shop_id` param, STAFF identity writes |
| Client changes | Optional `shopId` on `StaffCreateInput`, no UI changes needed |
| Identity tables (`shops`, `user_profiles`) | Deliberately left without RLS (documented in §7) |

Phase 2 delivers the cloud authorization layer. The owner of both Cafe and
Food Truck can now provision staff for either business, and every staff member
is isolated to their assigned shop by Postgres-level RLS — enforced by the
SECURITY DEFINER helper, not by client-supplied values.

Phase 6.1 (sync) + Phase 2 (authorization) are both in the working tree. No
commit has been made. Ready for review and `git add && git commit`.
