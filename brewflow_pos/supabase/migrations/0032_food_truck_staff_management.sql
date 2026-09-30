-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0032: Food Truck staff-management authorization
--
-- Repairs two distinct Food Truck failures without changing Cafe behavior or
-- creating a second authorization system. Memberships remain the only
-- authorization source.
--
-- A. Owner membership for an existing second business
--    `bootstrap_owner_membership()` could permanently refuse to reactivate the
--    caller's own INACTIVE OWNER membership: the old rule treated any existing
--    membership row for the shop as proof that someone else owned it. Because
--    the membership key is (auth_user_id, shop_id), the caller's own inactive
--    OWNER row cannot be another person's claim. This migration preserves the
--    0016 rule for every other row — including STAFF rows and other users'
--    rows — and only ignores the caller's own inactive OWNER row when deciding
--    whether the shop is already claimed. The final upsert then reactivates
--    exactly that one row. No duplicate membership is possible, Cafe's primary
--    membership is untouched, and a STAFF caller still cannot self-promote.
--
-- B. STAFF_PROFILE tombstones for a non-primary shop
--    Migration 0026 requires `shop_id = current_shop_id()` for every
--    `master_deletions` write. That helper returns the caller's primary shop
--    (Cafe), so an owner with a valid Food Truck OWNER membership still cannot
--    write a Food Truck STAFF_PROFILE tombstone. The policies added here are
--    additive and STAFF_PROFILE-only: they allow a write only when the caller
--    holds an active OWNER membership for the tombstone's own shop. Ordinary
--    entities and STAFF_PROFILE reads keep their existing policies.
--
-- C. Atomic staff-profile deletion
--    `delete_staff_profile_atomic()` deletes a STAFF target profile,
--    deactivates that target's STAFF membership, and writes the cross-device
--    STAFF_PROFILE tombstone in one server transaction. A failure anywhere
--    leaves all three unchanged, so the cloud can never lose the profile while
--    missing the tombstone peers need. OWNER targets are refused before any
--    write. Payroll history is untouched by this function.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Owner membership reactivation for an existing second business
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
    -- caller already holds an active OWNER membership (idempotent re-push), (c)
    -- the shop carries NO memberships at all, or (d) the only membership that
    -- would otherwise block the claim is the caller's own INACTIVE OWNER row.
    -- Case (d) is a reactivation, not a new claim: the unique
    -- (auth_user_id, shop_id) key guarantees there is still exactly one row
    -- for this caller and shop after step 4. Every STAFF row, every other
    -- user's row, and every other active OWNER row still blocks the claim.
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
           and not (
             m.auth_user_id = auth.uid()
             and m.role = 'OWNER'
             and m.is_active is false
           )
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

  -- 4. Mint or reactivate the OWNER membership (idempotent by
  --    (auth_user_id, shop_id)).
  insert into public.user_shop_memberships (auth_user_id, shop_id, role, is_active)
  values (auth.uid(), p_shop_id, 'OWNER', true)
  on conflict (auth_user_id, shop_id) do
    update set role = 'OWNER', is_active = true, updated_at = now();

  return true;
end; $$;

grant execute on function public.bootstrap_owner_membership(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Per-shop STAFF_PROFILE tombstone authorization
-- ---------------------------------------------------------------------------
create or replace function public.is_staff_profile_delete_allowed(
  target_shop_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public as $$
  select exists (
    select 1
      from public.user_shop_memberships m
     where m.auth_user_id = auth.uid()
       and m.shop_id = target_shop_id
       and m.role = 'OWNER'
       and m.is_active
  )
$$;

grant execute on function public.is_staff_profile_delete_allowed(uuid) to authenticated;

-- Additive STAFF_PROFILE-only write policies. The inherited
-- master_deletions_all_own_shop policy is intentionally left in place, so
-- every other entity keeps its exact current behavior and STAFF_PROFILE
-- reads remain member-scoped.
drop policy if exists master_deletions_staff_profile_insert_owner
  on public.master_deletions;
create policy master_deletions_staff_profile_insert_owner
  on public.master_deletions
  for insert
  with check (
    entity = 'STAFF_PROFILE'
    and public.is_staff_profile_delete_allowed(shop_id)
  );

drop policy if exists master_deletions_staff_profile_update_owner
  on public.master_deletions;
create policy master_deletions_staff_profile_update_owner
  on public.master_deletions
  for update
  using (
    entity = 'STAFF_PROFILE'
    and public.is_staff_profile_delete_allowed(shop_id)
  )
  with check (
    entity = 'STAFF_PROFILE'
    and public.is_staff_profile_delete_allowed(shop_id)
  );

drop policy if exists master_deletions_staff_profile_delete_owner
  on public.master_deletions;
create policy master_deletions_staff_profile_delete_owner
  on public.master_deletions
  for delete
  using (
    entity = 'STAFF_PROFILE'
    and public.is_staff_profile_delete_allowed(shop_id)
  );

-- ---------------------------------------------------------------------------
-- C. Atomic staff-profile deletion
-- ---------------------------------------------------------------------------
create or replace function public.delete_staff_profile_atomic(
  p_auth_user_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = public as $$
declare
  v_shop_id uuid;
  v_role text;
begin
  if p_auth_user_id is null then
    return false;
  end if;

  -- Lock the target profile for the duration of this transaction so its role
  -- cannot change between the OWNER refusal below and the delete.
  select u.shop_id, u.role
    into v_shop_id, v_role
    from public.user_profiles u
   where u.auth_user_id = p_auth_user_id
   for update;

  -- Unknown targets and OWNER targets both fail closed without writing.
  if not found then
    return false;
  end if;
  if v_role <> 'STAFF' then
    return false;
  end if;
  if v_shop_id is null then
    return false;
  end if;

  -- The caller must own the target's own shop. A Cafe OWNER membership never
  -- authorizes a Food Truck deletion, and the caller's primary shop is
  -- deliberately irrelevant here.
  if not public.is_staff_profile_delete_allowed(v_shop_id) then
    return false;
  end if;

  -- Remove the sign-in profile. The role predicate is repeated so a
  -- concurrent promotion to OWNER cannot slip through.
  delete from public.user_profiles u
   where u.auth_user_id = p_auth_user_id
     and u.role = 'STAFF';
  if not found then
    return false;
  end if;

  -- Revoke the target's shop authorization while preserving the membership
  -- row for audit. A later rehire through create-staff reactivates it; the
  -- row also continues to block STAFF self-promotion through bootstrap.
  update public.user_shop_memberships m
     set is_active = false,
         updated_at = now()
   where m.auth_user_id = p_auth_user_id
     and m.shop_id = v_shop_id
     and m.role = 'STAFF';

  -- Broadcast the cross-device tombstone in the same transaction. Without
  -- this row peers would keep the deleted member forever.
  insert into public.master_deletions (entity, id, shop_id, deleted_at)
  values ('STAFF_PROFILE', p_auth_user_id, v_shop_id, now())
  on conflict (entity, id) do update set
    shop_id = excluded.shop_id,
    deleted_at = excluded.deleted_at;

  return true;
end; $$;

grant execute on function public.delete_staff_profile_atomic(uuid) to authenticated;
