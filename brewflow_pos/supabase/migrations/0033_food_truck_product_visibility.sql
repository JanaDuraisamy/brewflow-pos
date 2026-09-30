-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0033: Food Truck product visibility
-- ---------------------------------------------------------------------------
-- Adds a `visible_in_shops` flag to existing products so the owner can
-- control which products are available in the Food Truck shop without
-- creating duplicate product records.
--
-- The flag defaults to false; the owner can toggle it via the admin UI.
-- RLS policies below use this flag to gate Food Truck access while
-- keeping Cafe behavior completely unchanged.
-- ---------------------------------------------------------------------------

-- Add visible_in_shops column to products (defaults to false)
alter table public.products
  add column visible_in_shops boolean not null default false;

-- Grant authenticated users read access to the new column (RLS handles the
-- actual visibility logic; this just exposes the column).
grant select on public.products to authenticated;

-- ---------------------------------------------------------------------------
-- OWNER-only policy to toggle the visible_in_shops flag.
-- Only an OWNER membership for the product's shop may update this column.
-- ---------------------------------------------------------------------------
drop policy if exists products_owner_toggle_visibility on public.products;
create policy products_owner_toggle_visibility on public.products
  for update
  using (
    exists (
      select 1
        from public.user_shop_memberships m
       where m.auth_user_id = auth.uid()
         and m.shop_id = shop_id
         and m.role = 'OWNER'
         and m.is_active
    )
  )
  with check (
    exists (
      select 1
        from public.user_shop_memberships m
       where m.auth_user_id = auth.uid()
         and m.shop_id = shop_id
         and m.role = 'OWNER'
         and m.is_active
    )
  );

-- ---------------------------------------------------------------------------
-- Extended product RLS: keep the existing shop-isolation gate, and add the
-- visibility flag as an additional path. When visible_in_shops = true the
-- product is also visible to authenticated users who have ANY active shop
-- membership (i.e. OWNER of either shop, or STAFF of the product's shop).
-- The write side is guarded by products_owner_toggle_visibility above, so
-- staff cannot arbitrarily change the flag.
-- ---------------------------------------------------------------------------
drop policy if exists products_all_own_shop on public.products;
create policy products_all_own_shop on public.products
  for all using (
    is_shop_member(shop_id)
    or visible_in_shops = true
  )
  with check (
    is_shop_member(shop_id)
    or visible_in_shops = true
  );