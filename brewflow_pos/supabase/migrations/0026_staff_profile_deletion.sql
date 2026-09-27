-- BrewFlow POS — Migration 0026: Staff master deletion
--
-- Allows STAFF_PROFILE tombstones so an owner deleting a staff member
-- propagates to every other device for the shop.
--
-- The tombstone id is the Supabase auth user id, which is what each peer
-- matches its local users.auth_user_id on.
--
-- Historical payroll is deliberately NOT touched or cascaded:
-- staff_attendance, staff_advances, staff_monthly_salaries and
-- staff_daily_salaries key staff by a plain `staff_user_id text` column with
-- no foreign key to user_profiles, so deleting the profile row leaves that
-- history intact and correctly attributed.
ALTER TABLE public.master_deletions DROP CONSTRAINT IF EXISTS master_deletions_entity_check;
ALTER TABLE public.master_deletions ADD CONSTRAINT master_deletions_entity_check CHECK (entity IN ('CATEGORY','PRODUCT','PRODUCT_VARIANT','SUPPLIER','CUSTOMER','EXPENSE','OFFER','STAFF_PROFILE'));

-- ---------------------------------------------------------------------------
-- Owner-only STAFF_PROFILE tombstones
--
-- The inherited master_deletions policy scopes by SHOP only, so any STAFF
-- profile in the shop could forge a STAFF_PROFILE tombstone and evict a
-- colleague from every device. Removing a staff member is an owner decision,
-- so the policy is recreated with an extra owner check applied to STAFF_PROFILE
-- writes ONLY. Reads are untouched, because every device must still be able to
-- pull the tombstone, and every other entity keeps its existing shop-scoped
-- behaviour so this migration changes nothing about existing deletions.
-- ---------------------------------------------------------------------------
create or replace function public.is_shop_owner()
returns boolean
language sql
stable
security definer
set search_path = public as $$
  select exists (
    select 1
      from public.user_profiles u
     where u.auth_user_id = auth.uid()
       and u.is_active
       and u.role = 'OWNER'
  )
$$;

grant execute on function public.is_shop_owner() to authenticated;

drop policy if exists master_deletions_all_own_shop on public.master_deletions;
create policy master_deletions_all_own_shop on public.master_deletions
  for all
  using (shop_id = public.current_shop_id())
  with check (
    shop_id = public.current_shop_id()
    and (entity <> 'STAFF_PROFILE' or public.is_shop_owner())
  );
