-- ---------------------------------------------------------------------------
-- BrewFlow POS — Sync Foundation (server side)
-- Minimal cloud structures the device-registration client boundary expects.
-- Business-data mirrors arrive in later Phase-6 stages; nothing here is fake.
-- ---------------------------------------------------------------------------

-- Devices: one row per installation. A user MAY have many devices, so there
-- is intentionally NO unique constraint on user_id.
create table if not exists public.devices (
  id uuid primary key,                       -- generated on the device
  shop_id uuid not null references public.shops (id) on delete cascade,
  user_id uuid not null,                     -- supabase auth user
  device_name text,
  platform text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists idx_devices_shop on public.devices (shop_id);

-- Shop isolation is enforced by RLS: a caller may only see devices whose row
-- matches their own shop profile. (RLS activation + policies run once during
-- provisioning together with shops/user_profiles.)
alter table public.devices enable row level security;

-- NOTE: shops/user_profiles tables are provisioned by the existing
-- create-staff bootstrap SQL. This migration only adds the devices surface.
