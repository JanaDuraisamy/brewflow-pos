-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0014: Secondary-Business Membership Claim
--
-- 0013's bootstrap_owner_membership() could NOT heal the second business a
-- device created before cloud memberships existed (via the old pushIdentity
-- table upserts). Its step-3 rule rejected any EXISTING shop that was neither
-- the caller's primary shop (`user_profiles.shop_id`) nor already owned — but
-- the old client could only ever record ONE primary shop, so whichever
-- business was NOT the last-active one has zero OWNER membership and can never
-- mint one. Observed production result:
--   * billing:      create_sale_atomic → is_shop_member() → 42501 → "Sale not
--                   completed. Access denied for this shop."
--   * create-staff: 403 → "Only an active shop owner can add staff members."
--
-- The persisted shop_id (single-valued user_profiles.shop_id) vs the shop the
-- device actually operates is the exact mismatch. This migration re-creates
-- bootstrap_owner_membership() with a RELAXED — not weakened — step-3 rule:
--
--   An EXISTING shop claim is allowed when the caller is the PRIMARY owner,
--   OR already holds an OWNER membership, OR the shop has NO memberships at
--   all (by anyone, including the caller — a self-created second business that
--   the old client could never claim).
--
-- Security stays intact:
--   * A victim shop is by definition operated by someone → it HAS an active
--     OWNER membership → FORBIDDEN (unchanged).
--   * Staff self-promotion → the shop HAS their STAFF membership → FORBIDDEN
--     (their shop is never memberless).
--   * A genuinely self-created lazy business carries ZERO membership rows (the
--     old client never wrote memberships and RLS blocks clients entirely), so
--     it becomes claimable — which is exactly the production heal needed. The
--     existing client push path (primary + Food Truck) calls this on every
--     ensure/retry, so no client change is required.
--
-- Idempotent; grants survive the re-created function (re-granted anyway for
-- clarity). Append-only: never edit released migrations.
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
    -- Existing shop: allowed when (a) it is the caller's primary shop, (b) the
    -- caller already holds an active OWNER membership (idempotent re-push), or
    -- (c) the shop carries NO memberships at all — the pre-membership second
    -- business the old client created but could never claim. A shop that any
    -- membership (OWNER or STAFF, own or other) already covers stays FORBIDDEN.
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