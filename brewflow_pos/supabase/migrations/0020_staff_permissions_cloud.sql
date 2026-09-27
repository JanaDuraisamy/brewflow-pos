-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0020: Cloud-authoritative staff permission grants
--
-- BUG: fine-grained STAFF permission grants were device-local only (Drift
-- `staff_permissions`). When a staff member signs in on a second device, the
-- cloud resolution path (`claimOwnershipForCloud`) created a local profile
-- with `role = STAFF` but an EMPTY permission set, so the permission-aware
-- shell hid every navigation destination and the route guard redirected all
-- protected locations (including /dashboard) to /no-access: "No access to
-- this area".
--
-- Fix:
--   A. `user_profiles.permissions text[]` carries the owner's grants as the
--      cloud-authoritative copy. `user_profiles` is deliberately the same
--      NO-RLS identity surface that already holds `role`, so the client
--      bootstrap read (`fetchProfile`) resolves grants with zero RLS changes.
--   B. The ONLY writer is the SECURITY DEFINER `set_staff_permissions()` RPC,
--      which verifies the caller is an active OWNER member of the target
--      staff member's shop. A staff member can never grant themselves, and an
--      owner of one shop can never touch another shop's staff. This preserves
--      the existing server/RLS authorization boundary — no policies weakened.
--
-- Enforcement note: server-side business checks stay role/membership based
-- (SECURITY DEFINER `is_shop_member`); the fine-grained set only drives
-- client navigation/UI. It is stored cloud-side so every staff device sees
-- the identical, owner-confirmed grant set.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

alter table public.user_profiles
  add column if not exists permissions text[] not null default '{}';

comment on column public.user_profiles.permissions is
  'Owner-confirmed fine-grained STAFF grants (View/Dashboard etc.). '
  'Only set_staff_permissions() writes this; see migration 0020.';

create or replace function public.set_staff_permissions(
  p_auth_user_id uuid,
  p_permissions text[]
)
returns void
language plpgsql security definer
set search_path = public as $$
declare
  v_target_shop uuid;
  v_target_role text;
  v_token text;
begin
  if p_auth_user_id is null or p_auth_user_id = auth.uid() then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- Validate every token against the known permission vocabulary so the
  -- column never stores garbage the client would silently ignore.
  foreach v_token in array coalesce(p_permissions, '{}') loop
    if v_token not in (
      'VIEW_DASHBOARD',
      'BILLING',
      'VIEW_INVENTORY',
      'EDIT_INVENTORY',
      'STOCK_ADJUSTMENT',
      'PURCHASES',
      'SUPPLIERS',
      'CUSTOMERS',
      'CUSTOMER_LEDGER',
      'EXPENSES',
      'REPORTS',
      'ORDERS',
      'SETTINGS',
      'OFFERS',
      'MANAGE_STAFF'
    ) then
      raise exception 'FORBIDDEN' using errcode='42501';
    end if;
  end loop;

  -- Resolve the target's shop + role. The caller must authorize against the
  -- target's OWN shop — cross-shop grants and self-grants are forbidden.
  select u.shop_id, u.role
    into v_target_shop, v_target_role
    from public.user_profiles u
   where u.auth_user_id = p_auth_user_id;

  if not found then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  if v_target_role <> 'STAFF' then
    -- Owners are implied-all and never carry a stored grant set.
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- Owner gate: the caller must hold an active OWNER membership for the
  -- target's shop (same read the create-staff boundary uses).
  if not exists (
    select 1
      from public.user_shop_memberships m
     where m.auth_user_id = auth.uid()
       and m.shop_id = v_target_shop
       and m.role = 'OWNER'
       and m.is_active
  ) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  update public.user_profiles u
     set permissions = p_permissions,
         updated_at = now()
   where u.auth_user_id = p_auth_user_id
     and u.role = 'STAFF';

  if not found then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
end; $$;

grant execute on function public.set_staff_permissions(uuid, text[]) to authenticated;