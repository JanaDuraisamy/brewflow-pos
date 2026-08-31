-- ---------------------------------------------------------------------------
-- BrewFlow POS — Phase 6.1: Master-Data Sync (server side)
--
-- Adds the minimum cloud surface for multi-device MASTER DATA sync:
-- categories, products, product_variants, suppliers, customers (+ deletion
-- tombstones). Sales/payments/purchases/expenses/stock are later stages.
--
-- Design decisions (deliberate, do not "simplify" them away):
--
-- 1. Identity surface completed here. 0002 referenced public.shops and the
--    create-staff README seeded a user_profiles WITHOUT shop_id; this
--    migration creates/repairs both so RLS can resolve a caller's shop.
--    Idempotent (if not exists / add column if not exists) so it is safe on
--    projects where the manual seed already ran.
--
-- 2. Conflict policy = LAST SUCCESSFUL PUSH WINS ("last-writer-wins" at the
--    server boundary). Ordering comes from ARRIVAL on the server, never from
--    client clocks: every write stamps updated_at via trigger now(), and pull
--    cursors use that server timestamp only. Client device time is never
--    trusted for conflict resolution.
--
-- 3. Pulls are incremental + idempotent: clients ask for updated_at >
--    cursor ordered ascending, apply upserts by UUID primary key.
--    Hard deletes travel through master_deletions tombstones because deleted
--    rows cannot appear in a row-scan delta query.
--
-- 4. Shop isolation via RLS everywhere. The security-definer helper avoids
--    recursive policy evaluation on user_profiles itself.
--
-- Apply with: supabase db execute --file supabase/migrations/0003_master_data_sync.sql
-- (or paste into the SQL editor). Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Identity surface (shops + user_profiles.shop_id)
-- ---------------------------------------------------------------------------

create table if not exists public.shops (
  id uuid primary key,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_profiles (
  auth_user_id uuid primary key references auth.users (id) on delete cascade,
  email text not null,
  role text not null check (role in ('OWNER', 'STAFF')),
  display_name text,
  shop_id uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Repairs projects provisioned from the older create-staff seed snippet
-- whose user_profiles row predates shop scoping.
alter table public.user_profiles
  add column if not exists shop_id uuid references public.shops (id);
alter table public.user_profiles
  add column if not exists display_name text;
alter table public.user_profiles
  add column if not exists updated_at timestamptz not null default now();

-- Caller's active shop membership. SECURITY DEFINER keeps policies on other
-- tables from recursing into user_profiles' own policies.
create or replace function public.current_shop_id() returns uuid
language sql stable security definer
set search_path = public as $$
  select u.shop_id from public.user_profiles u
   where u.auth_user_id = auth.uid() and u.is_active
$$;

-- ---------------------------------------------------------------------------
-- B. Devices RLS (0002 enabled RLS but defined no policies)
-- ---------------------------------------------------------------------------

create policy devices_select_own_shop
  on public.devices for select
  using (shop_id = public.current_shop_id());

-- An installation may register/refresh ITSELF only: the authenticated user
-- must be a member of the claimed shop AND own the claimed user_id. One user
-- may still register MANY devices (no unique on user_id).
create policy devices_insert_self
  on public.devices for insert
  with check (
    shop_id = public.current_shop_id()
    and user_id = auth.uid()
  );

create policy devices_update_self
  on public.devices for update
  using (shop_id = public.current_shop_id() and user_id = auth.uid())
  with check (shop_id = public.current_shop_id() and user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- C. Master-data mirrors
-- ---------------------------------------------------------------------------

create table if not exists public.categories (
  id uuid primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  client_created_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_categories_shop_name
  on public.categories (shop_id, name);
create index if not exists idx_categories_pull
  on public.categories (shop_id, updated_at);

create table if not exists public.products (
  id uuid primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  category_id uuid not null references public.categories (id),
  name text not null,
  sku text,
  selling_price_paise integer not null
    check (selling_price_paise >= 0),
  cost_price_paise integer check (cost_price_paise is null or cost_price_paise >= 0),
  -- Local stock snapshot mirrors the local device's view; authoritative stock
  -- reconciliation across devices is a LATER phase. Never used for billing
  -- decisions server-side in 6.1.
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  stock_unit text not null default 'COUNT'
    check (stock_unit in ('COUNT', 'ML', 'GRAM', 'KG', 'NONE')),
  low_stock_mode text not null default 'USE_DEFAULT'
    check (low_stock_mode in ('USE_DEFAULT', 'CUSTOM', 'OFF')),
  low_stock_threshold integer
    check (low_stock_threshold is null or low_stock_threshold >= 0),
  membership_enabled boolean not null default false,
  member_price_paise integer
    check (member_price_paise is null or member_price_paise >= 0),
  image_path text,
  is_active boolean not null default true,
  client_created_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_products_shop_sku
  on public.products (shop_id, sku);
create index if not exists idx_products_pull
  on public.products (shop_id, updated_at);
create index if not exists idx_products_category
  on public.products (category_id);

create table if not exists public.product_variants (
  id uuid primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  product_id uuid not null references public.products (id),
  name text not null,
  sku text,
  selling_price_paise integer not null
    check (selling_price_paise >= 0),
  cost_price_paise integer check (cost_price_paise is null or cost_price_paise >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  low_stock_mode text not null default 'USE_DEFAULT'
    check (low_stock_mode in ('USE_DEFAULT', 'CUSTOM', 'OFF')),
  low_stock_threshold integer
    check (low_stock_threshold is null or low_stock_threshold >= 0),
  membership_enabled boolean not null default false,
  member_price_paise integer
    check (member_price_paise is null or member_price_paise >= 0),
  is_active boolean not null default true,
  client_created_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_product_variants_shop_sku
  on public.product_variants (shop_id, sku);
create index if not exists idx_product_variants_pull
  on public.product_variants (shop_id, updated_at);
create index if not exists idx_product_variants_product
  on public.product_variants (product_id);

create table if not exists public.suppliers (
  id uuid primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  client_created_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_suppliers_shop_phone
  on public.suppliers (shop_id, phone);
create index if not exists idx_suppliers_pull
  on public.suppliers (shop_id, updated_at);

create table if not exists public.customers (
  id uuid primary key,
  shop_id uuid not null references public.shops (id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  is_active boolean not null default true,
  membership_active boolean not null default false,
  membership_fee_paise integer,
  whatsapp_status text not null default 'UNKNOWN'
    check (whatsapp_status in ('UNKNOWN', 'VERIFIED', 'NOT_VERIFIED', 'UNAVAILABLE')),
  client_created_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists ux_customers_shop_phone
  on public.customers (shop_id, phone);
create index if not exists idx_customers_pull
  on public.customers (shop_id, updated_at);

-- Tombstones make hard deletes visible to incremental pulls. Categories are
-- hard-deleted locally when unused; everything else deactivates softly, but
-- the tombstone surface stays generic for later phases.
create table if not exists public.master_deletions (
  entity text not null check (entity in (
    'CATEGORY', 'PRODUCT', 'PRODUCT_VARIANT', 'SUPPLIER', 'CUSTOMER'
  )),
  id uuid not null,
  shop_id uuid not null references public.shops (id) on delete cascade,
  deleted_at timestamptz not null default now(),
  primary key (entity, id)
);
create index if not exists idx_master_deletions_pull
  on public.master_deletions (shop_id, deleted_at);

-- ---------------------------------------------------------------------------
-- D. Server-owned timestamps
-- ---------------------------------------------------------------------------

-- updated_at always reflects SERVER commit time (arrival order); clients may
-- supply their creation instant separately (client_created_at) for history.
create or replace function public.touch_row_updated_at() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_devices_touch on public.devices;
create trigger trg_devices_touch before update on public.devices
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_categories_touch on public.categories;
create trigger trg_categories_touch before update on public.categories
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_products_touch on public.products;
create trigger trg_products_touch before update on public.products
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_product_variants_touch on public.product_variants;
create trigger trg_product_variants_touch before update on public.product_variants
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_suppliers_touch on public.suppliers;
create trigger trg_suppliers_touch before update on public.suppliers
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_customers_touch on public.customers;
create trigger trg_customers_touch before update on public.customers
  for each row execute function public.touch_row_updated_at();

drop trigger if exists trg_shops_touch on public.shops;
create trigger trg_shops_touch before update on public.shops
  for each row execute function public.touch_row_updated_at();

-- ---------------------------------------------------------------------------
-- E. Master-data RLS — callers may only ever touch their own shop
-- ---------------------------------------------------------------------------

create policy categories_all_own_shop on public.categories
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());

create policy products_all_own_shop on public.products
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());

create policy product_variants_all_own_shop on public.product_variants
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());

create policy suppliers_all_own_shop on public.suppliers
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());

create policy customers_all_own_shop on public.customers
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());

create policy master_deletions_all_own_shop on public.master_deletions
  for all using (shop_id = public.current_shop_id())
  with check (shop_id = public.current_shop_id());
