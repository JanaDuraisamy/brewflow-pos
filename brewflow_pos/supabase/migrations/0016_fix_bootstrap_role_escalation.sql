-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0016: Fix bootstrap_owner_membership role escalation
--
-- BUG: migrations 0013/0014's bootstrap_owner_membership() unconditionally
-- sets role = 'OWNER' on every profile upsert (including conflict updates).
-- When a STAFF user calls pushIdentity on a fresh device/install, their
-- cloud user_profiles role is silently upgraded from STAFF to OWNER. This
-- cascades:
--   • The RPC's own step-2 FORBIDDEN check never fires (it reads the role
--     the upsert just wrote, which is always OWNER).
--   • The OWNER membership is minted, unlocking every is_shop_member-gated
--     RPC (create_sale_atomic, void_sale_atomic, etc.).
--   • The local device then resolves the profile as OWNER via
--     claimOwnershipForCloud, granting full owner access to a staff account.
--
-- Fix:
--   A. On INSERT (first profile): create as OWNER (unchanged — first device
--      bootstrapping the shop is the owner).
--   B. On CONFLICT (existing profile): preserve the existing role. A staff
--      account's role must only change via explicit owner action (updateStaff
--      or cloud create-staff), never through a self-service bootstrap.
--   C. Only mint OWNER membership when the resolved role is OWNER.
--      Staff members get their membership through the create-staff RPC
--      (0007), not through bootstrap.
--
-- Append-only: never edit released migrations.
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

  -- 1. Upsert the caller's OWN user_profiles row (self-bootstrap).
  --    INSERT: create as OWNER (first device bootstrapping the shop).
  --    CONFLICT: preserve the existing role and is_active — a staff account
  --    must never be silently escalated to OWNER through a re-push.
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
    shop_id   = coalesce(public.user_profiles.shop_id, excluded.shop_id),
    updated_at = now();

  -- 2. The caller must resolve as an active OWNER.
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
    -- Existing shop: allowed when (a) it is the caller's primary shop, (b) the
    -- caller already holds an active OWNER membership (idempotent re-push), or
    -- (c) the shop carries NO memberships at all — the pre-membership second
    -- business the old client created but could never claim.
    if v_primary_shop <> p_shop_id
      and not exists (
        select 1
          from public.user_shop_memberships m
         where m.auth_user_id = auth.uid()
           and m.shop_id = p_shop_id
           and m.role = 'OWNER'
           and m.is_active
      )
      and exists (
        select 1
          from public.user_shop_memberships m
         where m.shop_id = p_shop_id
      )
    then
      raise exception 'FORBIDDEN' using errcode='42501';
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
