-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0013: Owner Membership Bootstrap
--
-- Fixes a Phase-2 gap: when the client pushes its cloud identity
-- (CloudShopResolver.pushIdentity), it creates the `shops` row and an OWNER
-- `user_profiles` row — but NEVER a `user_shop_memberships` row. Migration
-- 0007 seeded memberships ONLY for profiles that existed when it ran, so any
-- owner bootstrapped afterwards (a fresh install, or a reinstalled device)
-- has NO OWNER membership for their own shop.
--
-- Consequences (observed in production):
--   * Every cloud-authoritative write is rejected: create_sale_atomic,
--     void_sale_atomic, next_receipt_number, receive_purchase_atomic and
--     next_purchase_number all ENFORCE `is_shop_member(shop_id)` → FORBIDDEN
--     → the POS shows "Sale not completed. Access denied for this shop."
--   * create-staff authorizes the caller ONLY via an active OWNER
--     `user_shop_memberships` row for the target shop → 403 FORBIDDEN →
--     "Only an active shop owner can add staff members."
--
-- This migration:
--   A. Introduces a client-callable SECURITY DEFINER RPC
--      `bootstrap_owner_membership(p_shop_id, p_shop_name, p_email)` that
--      idempotently creates the caller's OWNER membership (replacing the two
--      naked table upserts that pushIdentity used to do).
--   B. Re-seeds memberships from user_profiles (same idempotent rule as 0007)
--      so already-deployed shops heal on migration without waiting for a
--      client push.
--
-- Security model (deliberate, consistent with 0007 §2):
--   * `user_profiles`/`shops` remain client-writable bootstrap surfaces; the
--     RPC adds no NEW capability the client did not already have via
--     pushIdentity (it still only ever writes the CALLER's OWN profile row).
--   * The RPC constrains auth.uid() throughout: a caller can only mint a
--     membership tying THEIR OWN auth account to a shop.
--   * For an EXISTING shop, membership is minted only when the shop is the
--     caller's primary shop (user_profiles.shop_id) OR the caller already
--     holds an active OWNER membership there (idempotent re-push for second
--     businesses such as Food Truck).
--   * A brand-new shop id may be created + claimed as a second business —
--     but only by an active OWNER, and only for a shop id that does not yet
--     exist (a victim shop already exists, so its id fails the check).
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. bootstrap_owner_membership
-- ---------------------------------------------------------------------------
create or replace function public.bootstrap_owner_membership(
  p_shop_id uuid,
  p_shop_name text,
  p_email text
)
returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_role text;
  v_active boolean;
  v_primary_shop uuid;
  v_shop_exists boolean;
begin
  if p_shop_id is null then
    raise exception 'FORBIDDEN: null shop id' using errcode='42501';
  end if;

  -- 1. Upsert the caller's OWN user_profiles row (self-bootstrap, mirrors the
  --    client pushIdentity semantics). The primary shop is only written on
  --    FIRST insert: pushing a second business must never re-point a
  --    multi-business owner's primary shop away from their original shop.
  insert into public.user_profiles (auth_user_id, email, role, shop_id, is_active)
  values (
    auth.uid(),
    coalesce(p_email, ''),
    'OWNER',
    p_shop_id,
    true
  )
  on conflict (auth_user_id) do update set
    email     = coalesce(excluded.email, public.user_profiles.email),
    role      = 'OWNER',
    shop_id   = coalesce(public.user_profiles.shop_id, excluded.shop_id),
    is_active = true,
    updated_at = now();

  -- 2. The caller must resolve as an active OWNER (defensive; satisfied by
  --    the upsert above for the self-bootstrap path).
  select role, is_active, shop_id
    into v_role, v_active, v_primary_shop
    from public.user_profiles
   where auth_user_id = auth.uid();

  if not found or v_role <> 'OWNER' or v_active is not true then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- 3. Classify the shop: existing (needs an ownership claim) vs brand-new
  --    (owner's second business).
  select exists (select 1 from public.shops where id = p_shop_id)
    into v_shop_exists;

  if v_shop_exists then
    -- Existing shop: allowed when it is the caller's primary shop, or when
    -- the caller already owns it (idempotent re-push of a second business).
    if v_primary_shop <> p_shop_id then
      if not exists (
        select 1
          from public.user_shop_memberships m
         where m.auth_user_id = auth.uid()
           and m.shop_id = p_shop_id
           and m.role = 'OWNER'
           and m.is_active
      ) then
        raise exception 'FORBIDDEN' using errcode='42501';
      end if;
    end if;
  else
    -- Brand-new shop: create it, then mint the OWNER membership below.
    insert into public.shops (id, name)
    values (p_shop_id, coalesce(nullif(p_shop_name, ''), 'My Shop'))
    on conflict (id) do update set name = coalesce(nullif(excluded.name, ''), public.shops.name);
  end if;

  -- 4. Mint the OWNER membership (idempotent by (auth_user_id, shop_id)).
  insert into public.user_shop_memberships (auth_user_id, shop_id, role, is_active)
  values (auth.uid(), p_shop_id, 'OWNER', true)
  on conflict (auth_user_id, shop_id) do
    update set role = 'OWNER', is_active = true, updated_at = now();

  return true;
end; $$;

grant execute on function public.bootstrap_owner_membership(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Healing backfill: seed memberships for every existing profile
--    (idempotent; repeats 0007's rule so owners/offline-created profiles that
--    predate 0013 gain access without waiting for a client push).
-- ---------------------------------------------------------------------------
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