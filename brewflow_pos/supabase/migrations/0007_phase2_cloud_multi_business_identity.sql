-- ---------------------------------------------------------------------------
-- BrewFlow POS — Phase 2: Cloud Multi-Business Identity + RLS
--
-- Replaces the single-shop `current_shop_id()` authorization model with an
-- explicit membership table (`user_shop_memberships`) that lets ONE owner
-- hold OWNER membership for MULTIPLE businesses (Cafe + Food Truck), while
-- each staff member is scoped to exactly one shop (STAFF membership).
--
-- Design decisions (deliberate, do not "simplify" them away):
--
-- 1. `user_shop_memberships` is the AUTHORITATIVE business-authorization
--    source. `user_profiles.shop_id` remains populated and compatible (the
--    client still reads it as the "current/primary" shop for a single-shop
--    session), but RLS — the enforcement boundary — now reads memberships via
--    the SECURITY DEFINER helper `is_shop_member(shop_id)`.
-- 2. `is_shop_member()` is SECURITY DEFINER with a locked search_path and
--    does its own `auth.uid()` membership check, so policies never recurse
--    into a read-protected table and RLS is never bypassable by changing
--    client-supplied `shop_id`: the helper validates the row's shop_id against
--    the authenticated caller's memberships.
-- 3. Multi-shop OWNER access falls out naturally: an owner with an OWNER
--    membership for Cafe and Food Truck satisfies `is_shop_member` for both.
--    STAFF isolation is preserved: a staff member is a member of one shop only.
-- 4. `shops` and `user_profiles` KEEP their existing NO-RLS identity surface.
--    They are the bootstrap/bootstrap-authorization tables the client (anon
--    JWT) writes during first-boot (`pushIdentity`) BEFORE any membership row
--    exists. Enabling RLS here would break first-run owner bootstrap, so the
--    authoritative list-level protection is left for the membership table and
--    the create-staff boundary. Business data below is fully membership-gated.
--
-- Append-only: never edit released migrations. Apply with:
--   supabase db execute --file supabase/migrations/0007_phase2_cloud_multi_business_identity.sql
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Membership table (authoritative business authorization)
-- ---------------------------------------------------------------------------
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

-- A user may hold many memberships; an owner may own many shops; a staff
-- member is expected to hold exactly one, but the model does not hard-enforce
-- it (a trusted operator may expand scope later). Enforce single-shop STAFF
-- at the provisioning boundary (create-staff) instead of a brittle partial
-- unique index.
create index if not exists idx_user_shop_memberships_shop
  on public.user_shop_memberships (shop_id);
create index if not exists idx_user_shop_memberships_user_active
  on public.user_shop_memberships (auth_user_id, is_active);

-- RLS enabled, NO policies: the table is touched only by the service role
-- (create-staff edge function, which bypasses RLS) and the SECURITY DEFINER
-- `is_shop_member()` (owner of the function). Authenticated clients have no
-- direct read/write path to memberships — authorization happens through the
-- helper's evaluated policies, never through client-supplied rows.
alter table public.user_shop_memberships enable row level security;

-- Server-owned updated_at on membership changes.
create or replace function public.touch_membership_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
drop trigger if exists trg_user_shop_memberships_touch
  on public.user_shop_memberships;
create trigger trg_user_shop_memberships_touch
  before update on public.user_shop_memberships
  for each row execute function public.touch_membership_updated_at();

-- ---------------------------------------------------------------------------
-- B. SECURITY DEFINER membership check (powers every business policy)
-- ---------------------------------------------------------------------------
create or replace function public.is_shop_member(target_shop_id uuid)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1
      from public.user_shop_memberships m
     where m.auth_user_id = auth.uid()
       and m.shop_id = target_shop_id
       and m.is_active
  )
$$;

-- ---------------------------------------------------------------------------
-- C. Seed existing profiles into memberships (idempotent, preserves access)
-- ---------------------------------------------------------------------------
-- Every provisioned cloud profile (OWNER or STAFF) already has an effective
-- shop via user_profiles.shop_id. Backfill a matching membership row so no
-- existing user loses access on upgrade. Cross-shop food-truck ownership is
-- granted by later provisioning; only in-flight identities are backfilled.
insert into public.user_shop_memberships (auth_user_id, shop_id, role, is_active)
select u.auth_user_id, u.shop_id, u.role, u.is_active
  from public.user_profiles u
  join public.shops s on s.id = u.shop_id
 where u.auth_user_id is not null
   and u.shop_id is not null
   and u.role in ('OWNER', 'STAFF')
on conflict (auth_user_id, shop_id) do update
  set role      = excluded.role,
      is_active = excluded.is_active,
      updated_at = now();

-- ---------------------------------------------------------------------------
-- D. Re-point business RLS from current_shop_id() to is_shop_member(shop_id)
-- ---------------------------------------------------------------------------
-- Enables multi-shop OWNER access while isolating STAFF to a single shop.
-- The helper keeps OWNER access to Cafe AND Food Truck via two memberships.

-- Devices ---------------------------------------------------------------
drop policy if exists devices_select_own_shop on public.devices;
create policy devices_select_own_shop on public.devices
  for select using (is_shop_member(shop_id));

drop policy if exists devices_insert_self on public.devices;
create policy devices_insert_self on public.devices
  for insert
  with check (is_shop_member(shop_id) and user_id = auth.uid());

drop policy if exists devices_update_self on public.devices;
create policy devices_update_self on public.devices
  for update
  using (is_shop_member(shop_id) and user_id = auth.uid())
  with check (is_shop_member(shop_id) and user_id = auth.uid());

-- Categories ------------------------------------------------------------
drop policy if exists categories_all_own_shop on public.categories;
create policy categories_all_own_shop on public.categories
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Products --------------------------------------------------------------
drop policy if exists products_all_own_shop on public.products;
create policy products_all_own_shop on public.products
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Product variants ------------------------------------------------------
drop policy if exists product_variants_all_own_shop on public.product_variants;
create policy product_variants_all_own_shop on public.product_variants
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Suppliers -------------------------------------------------------------
drop policy if exists suppliers_all_own_shop on public.suppliers;
create policy suppliers_all_own_shop on public.suppliers
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Customers -------------------------------------------------------------
drop policy if exists customers_all_own_shop on public.customers;
create policy customers_all_own_shop on public.customers
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Master deletions ------------------------------------------------------
drop policy if exists master_deletions_all_own_shop on public.master_deletions;
create policy master_deletions_all_own_shop on public.master_deletions
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Sales -----------------------------------------------------------------
drop policy if exists sales_all_own_shop on public.sales;
create policy sales_all_own_shop on public.sales
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Sale items ------------------------------------------------------------
drop policy if exists sale_items_all_own_shop on public.sale_items;
create policy sale_items_all_own_shop on public.sale_items
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Expenses --------------------------------------------------------------
drop policy if exists expenses_all_own_shop on public.expenses;
create policy expenses_all_own_shop on public.expenses
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Customer payments -----------------------------------------------------
drop policy if exists customer_payments_all_own_shop on public.customer_payments;
create policy customer_payments_all_own_shop on public.customer_payments
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- Offers ----------------------------------------------------------------
drop policy if exists offers_all_own_shop on public.offers;
create policy offers_all_own_shop on public.offers
  for all using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

-- ---------------------------------------------------------------------------
-- E. Keep the legacy single-shop helper for compatibility
-- ---------------------------------------------------------------------------
-- `current_shop_id()` is retained unmodified: the client reads the "primary
-- / current" shop from user_profiles.shop_id for single-shop sessions and
-- Phases 6.1 behavior. No policy now depends on it, but removing it would be
-- a breaking contract change, so it stays.
-- ---------------------------------------------------------------------------
