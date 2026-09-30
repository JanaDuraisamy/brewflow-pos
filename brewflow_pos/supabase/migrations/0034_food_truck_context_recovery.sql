-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0034: Food Truck context recovery + per-shop receipt prefix
-- ---------------------------------------------------------------------------
-- Fixes three defects that together made Food Truck behave unlike Cafe, plus
-- one RLS hole introduced by 0033. Nothing here changes Cafe behaviour.
--
-- 1. RECEIPT PREFIX IS NOW PER SHOP
--    `next_receipt_number()` and `create_sale_atomic()` hardcoded 'BF-', so a
--    Food Truck sale minted `BF-000123` — indistinguishable from a Cafe receipt
--    and consuming the Cafe numbering. The per-shop SEQUENCE was already
--    correct and isolated (sale_sequences PK is (shop_id)); only the label was
--    wrong. The prefix now lives on the shop row, so the two businesses are
--    independent by construction rather than by a hardcoded branch.
--    Existing shops keep 'BF-' via the column default, so every Cafe receipt
--    number issued to date stays valid and continues unbroken.
--
-- 2. `list_my_managed_shops()` — the device can recover its Food Truck id
--    after a clear-data reinstall. The Food Truck shop id was only ever stored
--    in SharedPreferences, which "Clear app data" destroys; the app then minted
--    a BRAND NEW uuid locally and pointed at an empty phantom shop while the
--    real Food Truck sat unreachable in the cloud. There is deliberately no
--    direct client read of `user_shop_memberships` (it is RLS-enabled with zero
--    policies, reachable only through security-definer RPCs), so this RPC is
--    the recovery surface. It returns ONLY the caller's own memberships.
--
-- 3. `master_deletions` SELECT is no longer pinned to the primary shop.
--    0032 widened the INSERT/UPDATE/DELETE policies for STAFF_PROFILE to Food
--    Truck but left the inherited `for all` SELECT on `current_shop_id()`, so
--    a Food Truck tombstone could be written yet never read back — deletions
--    never propagated off the deleting device. Postgres ORs permissive
--    policies, so an ADDITIONAL `for select` policy widens reads for every shop
--    the caller is an active member of, while all write policies are untouched.
--
-- 4. RLS HOLE FROM 0033 — `products_all_own_shop` was `for all using
--    (is_shop_member(shop_id) or visible_in_shops = true)`. Because permissive
--    policies are OR-combined, `visible_in_shops = true` granted ANY
--    authenticated user of ANY shop UPDATE/DELETE on the whole row: price, cost
--    and `stock_quantity`, not just visibility. The visibility flag is a READ
--    gate, so it is now expressed as a `for select` policy and the `for all`
--    policy is reverted to 0033's membership-only term, dropping the visibility
--    escape. A shared product is readable by the Food Truck (so it can be sold)
--    but writable only by the shop that owns it. Food Truck stock lives in its
--    own per-shop table, never in the owner's `products` row.
--
-- Idempotent and append-only: never edits a released migration.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Per-shop receipt prefix
-- ---------------------------------------------------------------------------
alter table public.shops
  add column if not exists receipt_prefix text not null default 'BF-';

-- Give the Food Truck its own numbering. Matched on the name the client itself
-- writes when it lazily creates the second business
-- (BusinessSwitcherController -> ensureShopWithId(name: 'Food Truck')), so this
-- is a no-op on a project that has no such shop. The owner can change it later;
-- nothing hardcodes the value.
update public.shops
   set receipt_prefix = 'FT-'
 where lower(btrim(name)) = 'food truck'
   and receipt_prefix = 'BF-';

-- Resolver used by the receipt allocators. `shops` is an identity table with no
-- RLS by design (see 0007), so a plain invoker function is sufficient and keeps
-- the read auditable. Falls back to the historical 'BF-' if the row is missing
-- or the column was blanked, so a receipt number is never produced unprefixed.
create or replace function public.shop_receipt_prefix(p_shop_id uuid)
returns text
language sql stable set search_path = public as $$
  select coalesce(
    (select nullif(btrim(s.receipt_prefix), '') from public.shops s where s.id = p_shop_id),
    'BF-'
  );
$$;

grant execute on function public.shop_receipt_prefix(uuid) to authenticated;

-- Same body as 0011, with the hardcoded 'BF-' replaced by the shop's own
-- prefix. The sequence, the row lock and the gapless guarantee are unchanged.
create or replace function public.next_receipt_number(p_shop_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_next int;
  v_prefix text;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  -- Upsert then locked increment — concurrent callers block on row lock, no gaps on rollback
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  -- FOR UPDATE locks the row for this transaction
  select next_value into v_next from public.sale_sequences where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_next + 1 where shop_id = p_shop_id returning next_value into v_next;
  v_prefix := public.shop_receipt_prefix(p_shop_id);
  return v_prefix || lpad(v_next::text, 6, '0');
end; $$;

grant execute on function public.next_receipt_number(uuid) to authenticated;

-- Body preserved verbatim from 0011 except for the prefix lookup; see the
-- header note. Stock handling is deliberately NOT touched here — the
-- per-shop stock overlay is a separate, additive change.
create or replace function public.create_sale_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_subtotal_paise integer,
  p_total_paise integer,
  p_offer_discount_paise integer,
  p_payment_method text,
  p_payment_status text,
  p_lines jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sale_id uuid := gen_random_uuid();
  v_receipt text;
  v_prefix text;
  v_now timestamptz := now();
  v_line jsonb;
  v_product_id uuid;
  v_variant_id uuid;
  v_quantity int;
  v_unit_price int;
  v_line_total int;
  v_offer_discount int;
  v_applied_offer_id uuid;
  v_applied_offer_name text;
  v_applied_offer_type text;
  v_product_name text;
  v_variant_name text;
  v_sku text;
  v_stock int;
  v_stock_unit text;
  v_is_active boolean;
  v_new_stock int;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  -- Basic validation
  if p_subtotal_paise < 0 or p_total_paise < 0 or p_offer_discount_paise < 0 then
    raise exception 'INVALID_INPUT: negative money';
  end if;
  if p_payment_status not in ('PAID','NOT_PAID') then
    raise exception 'INVALID_INPUT: payment_status';
  end if;
  if p_payment_status = 'NOT_PAID' and p_customer_id is null then
    raise exception 'MISSING_CUSTOMER';
  end if;
  if p_payment_status = 'PAID' and p_payment_method is null then
    raise exception 'INVALID_PAYMENT';
  end if;
  if p_payment_method is not null and p_payment_method not in ('CASH','UPI','BANK') then
    raise exception 'INVALID_PAYMENT';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_CART';
  end if;

  -- Validate customer when linked
  if p_customer_id is not null then
    select is_active into v_is_active from public.customers where id = p_customer_id and shop_id = p_shop_id;
    if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
    if v_is_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;
  end if;

  -- Allocate receipt atomically (row-locked sequence), labelled with THIS
  -- shop's prefix so the Food Truck never consumes Cafe numbering.
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  select next_value into v_new_stock from public.sale_sequences where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_new_stock + 1 where shop_id = p_shop_id returning next_value into v_new_stock;
  v_prefix := public.shop_receipt_prefix(p_shop_id);
  v_receipt := v_prefix || lpad(v_new_stock::text, 6, '0');

  -- Process each line: lock stock row, check, deduct, collect movement
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    v_unit_price := (v_line->>'unit_price_paise')::int;
    v_line_total := (v_line->>'line_total_paise')::int;
    v_offer_discount := coalesce((v_line->>'offer_discount_paise')::int, 0);
    v_applied_offer_id := nullif(v_line->>'applied_offer_id','')::uuid;
    v_applied_offer_name := nullif(v_line->>'applied_offer_name','');
    v_applied_offer_type := nullif(v_line->>'applied_offer_type','');
    v_product_name := v_line->>'product_name';
    v_variant_name := nullif(v_line->>'variant_name','');
    v_sku := nullif(v_line->>'sku','');

    if v_quantity <= 0 then raise exception 'INVALID_QUANTITY'; end if;
    if v_product_id is null then raise exception 'INVALID_INPUT: product_id'; end if;

    -- Lock and validate product
    select stock_quantity, stock_unit, is_active into v_stock, v_stock_unit, v_is_active
      from public.products where id = v_product_id and shop_id = p_shop_id for update;
    if not found then raise exception 'UNAVAILABLE_PRODUCT: %', v_product_name using errcode='P0001'; end if;
    if v_is_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_product_name using errcode='P0001'; end if;

    if v_variant_id is not null then
      select stock_quantity, is_active into v_stock, v_is_active
        from public.product_variants where id = v_variant_id and shop_id = p_shop_id for update;
      if not found then raise exception 'UNAVAILABLE_PRODUCT: %', v_product_name using errcode='P0001'; end if;
      if v_is_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_product_name using errcode='P0001'; end if;
    end if;

    -- Stock deduction only for tracked units (stock_unit != 'NONE')
    -- For NONE, skip stock check entirely
    select stock_unit into v_stock_unit from public.products where id = v_product_id;
    if v_stock_unit != 'NONE' then
      if v_stock < v_quantity then
        raise exception 'INSUFFICIENT_STOCK: %', v_product_name using errcode='P0001';
      end if;
      if v_variant_id is not null then
        update public.product_variants set stock_quantity = stock_quantity - v_quantity, updated_at = v_now
          where id = v_variant_id;
      else
        update public.products set stock_quantity = stock_quantity - v_quantity, updated_at = v_now
          where id = v_product_id;
      end if;
    end if;
  end loop;

  -- Insert sale header
  insert into public.sales (id, shop_id, customer_id, receipt_number, subtotal_paise, total_paise, offer_discount_paise, payment_method, payment_status, client_created_at, created_at, updated_at, voided, voided_at)
  values (v_sale_id, p_shop_id, p_customer_id, v_receipt, p_subtotal_paise, p_total_paise, p_offer_discount_paise, p_payment_method, p_payment_status, v_now, v_now, v_now, false, null);

  -- Insert sale items + movements
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    v_unit_price := (v_line->>'unit_price_paise')::int;
    v_line_total := (v_line->>'line_total_paise')::int;
    v_offer_discount := coalesce((v_line->>'offer_discount_paise')::int, 0);
    v_applied_offer_id := nullif(v_line->>'applied_offer_id','')::uuid;
    v_applied_offer_name := nullif(v_line->>'applied_offer_name','');
    v_applied_offer_type := nullif(v_line->>'applied_offer_type','');
    v_product_name := v_line->>'product_name';
    v_variant_name := nullif(v_line->>'variant_name','');
    v_sku := nullif(v_line->>'sku','');

    insert into public.sale_items (id, shop_id, sale_id, product_id, variant_id, product_name, variant_name, sku, unit_price_paise, quantity, line_total_paise, offer_discount_paise, applied_offer_id, applied_offer_name, applied_offer_type, client_created_at, created_at, updated_at)
    values (gen_random_uuid(), p_shop_id, v_sale_id, v_product_id, v_variant_id, v_product_name, v_variant_name, v_sku, v_unit_price, v_quantity, v_line_total, v_offer_discount, v_applied_offer_id, v_applied_offer_name, v_applied_offer_type, v_now, v_now, v_now);

    -- Movement only for tracked
    select stock_unit into v_stock_unit from public.products where id = v_product_id;
    if v_stock_unit != 'NONE' then
      -- stock_before = after + qty, since we already deducted
      if v_variant_id is not null then
        select stock_quantity into v_stock from public.product_variants where id = v_variant_id;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
        values (gen_random_uuid(), p_shop_id, v_product_id, v_variant_id, 'SALE', -v_quantity, v_stock + v_quantity, v_stock, 'SALE', v_sale_id, v_now, v_now);
      else
        select stock_quantity into v_stock from public.products where id = v_product_id;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
        values (gen_random_uuid(), p_shop_id, v_product_id, null, 'SALE', -v_quantity, v_stock + v_quantity, v_stock, 'SALE', v_sale_id, v_now, v_now);
      end if;
    end if;
  end loop;

  return jsonb_build_object('id', v_sale_id, 'receipt_number', v_receipt, 'created_at', v_now);
end; $$;

grant execute on function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Recover the caller's managed shops (clear-data reinstall)
-- ---------------------------------------------------------------------------
-- SECURITY: returns ONLY rows where auth_user_id = auth.uid(). The definer bit
-- is required solely because `user_shop_memberships` has RLS enabled with zero
-- policies (0007) and is otherwise unreachable from a client; it never widens
-- what the caller may see, only how they read their own rows. `is_shop_member()`
-- is the same pattern already used by every billing RPC.
create or replace function public.list_my_managed_shops()
returns table (shop_id uuid, shop_name text, role text, is_active boolean)
language sql stable security definer set search_path = public as $$
  select m.shop_id,
         coalesce(s.name, ''),
         m.role,
         m.is_active
    from public.user_shop_memberships m
    left join public.shops s on s.id = m.shop_id
   where m.auth_user_id = auth.uid()
     and m.is_active
   order by m.shop_id;
$$;

grant execute on function public.list_my_managed_shops() to authenticated;

-- ---------------------------------------------------------------------------
-- C. master_deletions: read tombstones for every shop the caller belongs to
-- ---------------------------------------------------------------------------
-- Additive `for select` policy. Permissive policies are OR-combined, so this
-- widens SELECT to `is_shop_member(shop_id)` while the 0026 `for all` policy
-- still governs INSERT/UPDATE/DELETE exactly as before — a staff member of a
-- secondary shop still cannot write another shop's tombstones.
drop policy if exists master_deletions_select_member on public.master_deletions;
create policy master_deletions_select_member on public.master_deletions
  for select
  using (public.is_shop_member(shop_id));

-- ---------------------------------------------------------------------------
-- D. Close the 0033 RLS hole: visibility is a READ gate, not a write grant
-- ---------------------------------------------------------------------------
-- 0033 made the whole row world-writable to any authenticated user once
-- `visible_in_shops` was true. Restore the membership-only `for all` policy and
-- express cross-shop visibility as a separate read-only policy.
drop policy if exists products_all_own_shop on public.products;
create policy products_all_own_shop on public.products
  for all
  using (public.is_shop_member(shop_id))
  with check (public.is_shop_member(shop_id));

drop policy if exists products_select_shared_visible on public.products;
create policy products_select_shared_visible on public.products
  for select
  using (visible_in_shops = true);

-- 0033 gave `products` a visibility escape but left `product_variants` on the
-- 0003 `for all using (current_shop_id())` policy, so a shared product's
-- variants (sizes, weights) were invisible to the Food Truck even though the
-- product itself was visible — the truck could sell "Latte" but not "Large
-- Latte". Derive the read gate from the PARENT product's flag; the column does
-- not exist on product_variants and must not be referenced. Same additive
-- `for select` shape, so writes stay pinned exactly as 0003 left them.
drop policy if exists product_variants_select_shared_visible
  on public.product_variants;
create policy product_variants_select_shared_visible on public.product_variants
  for select
  using (
    exists (
      select 1
        from public.products p
       where p.id = product_variants.product_id
         and p.visible_in_shops = true
    )
  );
