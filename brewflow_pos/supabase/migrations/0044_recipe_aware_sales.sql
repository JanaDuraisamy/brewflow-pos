-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0044: Recipe-aware sales (shared stock on the cloud path)
--
-- Business requirement: several menu products (Plain / Cheese / Egg / Veg /
-- Masala Maggi) consume one underlying stock source (Maggi Packet). 0039
-- created the `product_recipes` mapping table and its sync, and the local
-- checkout (`DriftBillingRepository._checkoutCore`) deducts ONLY the mapped
-- ingredients — but NEITHER cloud RPC consults the mapping to this day:
--
--   * create_sale_atomic (0036) deducts each line's OWN product/variant row
--     (or nothing for NONE units) and never reads product_recipes;
--   * void_sale_atomic (0011) restores each line's OWN row the same way.
--
-- The moment any dish is mapped, the paths diverge: a cloud sale of a mapped
-- tracked dish decrements the dish on the server while the local checkout
-- decrements the packet, and a cloud void restores the dish on the server
-- while the local mirror restores the packet. For NONE (made-to-order)
-- dishes it is worse: the server moves nothing while the local void mirror
-- conjures packet stock out of thin air. Enabling mappings without this fix
-- would silently split every device from the cloud — hence this gate.
--
-- What changes (both functions keep their exact signatures, so no client,
-- grant or timeout re-wiring is needed; 0015's per-function guards persist
-- across CREATE OR REPLACE):
--
--   create_sale_atomic:
--     - per line, after the existing existence/active checks: when recipe
--       rows exist for (shop, product, variant-or-every-variant), the line's
--       OWN stock check, deduction and movement are SKIPPED and its needs are
--       accumulated per ingredient across ALL lines (one row per
--       line-ingredient; the GROUP BY below collapses NULL variant ids, which
--       a PRIMARY KEY could not hold);
--     - after the line loop: one row-locked, guarded deduction per
--       aggregated ingredient (existence/active/stock, named after the MENU
--       product exactly like the local repository, so the client's
--       INSUFFICIENT_STOCK/UNAVAILABLE_PRODUCT mapping is unchanged);
--     - one SALE movement per aggregated ingredient (negative quantity, exact
--       before/after, reference SALE/sale id), mirroring the local leg.
--     - lines WITHOUT rows behave byte-identically to 0036 (same checks,
--       same deduction, same movements, same receipt consumption on failure).
--
--   void_sale_atomic:
--     - per sale_items line, when recipe rows exist for the sale's shop, the
--       OWN restore is SKIPPED and the restore is accumulated per ingredient;
--     - after the loop the ingredients are restored (+qty, unconditional like
--       the existing restore). Unmapped lines restore exactly as in 0011.
--
-- Locking: ingredient rows are locked (FOR UPDATE) in aggregation order
-- inside the same single transaction, so concurrent sales serialize and the
-- loser fails with INSUFFICIENT_STOCK — the server twin of the local
-- conditional-update guard. 0015's statement/lock timeouts turn a pathological
-- lock ordering into an error, never a wedge; atomicity is unchanged (a
-- failed sale writes nothing but still consumes a receipt number, exactly as
-- before — receipt allocation order is untouched).
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Recipe-aware create_sale_atomic (same 9-arg signature as 0036)
-- ---------------------------------------------------------------------------
create or replace function public.create_sale_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_subtotal_paise integer,
  p_total_paise integer,
  p_offer_discount_paise integer,
  p_payment_method text,
  p_payment_status text,
  p_lines jsonb,
  p_payments jsonb default null
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
  v_payment jsonb;
  v_leg_method text;
  v_leg_paise int;
  v_leg_sum int := 0;
  v_recipe record;
  v_recipe_id uuid;
  v_ing_stock int;
  v_ing_active boolean;
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
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_CART';
  end if;

  -- A NOT_PAID (credit) sale has no payment instrument at all.
  if p_payment_status = 'NOT_PAID' and p_payments is not null then
    raise exception 'INVALID_PAYMENT: credit sale cannot carry payment legs';
  end if;

  -- Split legs: validate every leg and the sum BEFORE any write, so a bad
  -- split can never consume a receipt number or touch stock.
  if p_payments is not null then
    if jsonb_typeof(p_payments) <> 'array' or jsonb_array_length(p_payments) = 0 then
      raise exception 'INVALID_PAYMENT: no payment legs';
    end if;
    for v_payment in select * from jsonb_array_elements(p_payments)
    loop
      v_leg_method := v_payment->>'payment_method';
      v_leg_paise := (v_payment->>'amount_paise')::int;
      -- BANK is deliberately absent: it is not a user-facing option, and a
      -- zero-value leg is not a payment.
      if v_leg_method not in ('CASH','UPI') then
        raise exception 'INVALID_PAYMENT: unsupported split method %', v_leg_method;
      end if;
      if v_leg_paise is null or v_leg_paise <= 0 then
        raise exception 'INVALID_PAYMENT: non-positive split leg';
      end if;
      v_leg_sum := v_leg_sum + v_leg_paise;
    end loop;
    if v_leg_sum <> p_total_paise then
      raise exception 'SPLIT_PAYMENT_MISMATCH';
    end if;
  else
    if p_payment_status = 'PAID' and p_payment_method is null then
      raise exception 'INVALID_PAYMENT';
    end if;
    -- Unchanged from 0034 so historic BANK sales stay valid.
    if p_payment_method is not null and p_payment_method not in ('CASH','UPI','BANK') then
      raise exception 'INVALID_PAYMENT';
    end if;
  end if;

  -- Validate customer when linked
  if p_customer_id is not null then
    select is_active into v_is_active from public.customers where id = p_customer_id and shop_id = p_shop_id;
    if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
    if v_is_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;
  end if;

  -- Allocate receipt atomically (row-locked per-shop counter), labelled with
  -- THIS shop's prefix so the Food Truck never consumes Cafe numbering.
  -- sale_sequences PK is (shop_id): one counter row per shop, no `id` column.
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  select next_value into v_new_stock from public.sale_sequences where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_new_stock + 1 where shop_id = p_shop_id returning next_value into v_new_stock;
  v_prefix := public.shop_receipt_prefix(p_shop_id);
  v_receipt := v_prefix || lpad(v_new_stock::text, 6, '0');

  -- Shared-stock accumulator: one row per line-ingredient; the GROUP BY at
  -- deduction time collapses repeats (including NULL variant ids, which a
  -- PRIMARY KEY could not hold) into a single total per ingredient.
  create temporary table t_recipe_needs (
    ingredient_product_id uuid,
    ingredient_variant_id uuid,
    need integer not null,
    menu_name text not null
  ) on commit drop;

  -- Process each line: lock stock row, check, deduct
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    v_line_total := (v_line->>'line_total_paise')::int;
    v_offer_discount := coalesce((v_line->>'offer_discount_paise')::int, 0);
    v_product_name := v_line->>'product_name';

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

    -- Shared stock: a line WITH recipe rows consumes ONLY its ingredients.
    -- A NULL variant_id row maps every variant of the product; a named one
    -- applies to that variant alone. The menu row's own stock is never
    -- touched for such a line, however tracked it is.
    v_recipe_id := null;
    for v_recipe in select ingredient_product_id, ingredient_variant_id, quantity
      from public.product_recipes
      where shop_id = p_shop_id and product_id = v_product_id
        and (variant_id is null or variant_id = v_variant_id)
    loop
      v_recipe_id := v_recipe.ingredient_product_id;
      insert into t_recipe_needs (ingredient_product_id, ingredient_variant_id, need, menu_name)
        values (v_recipe.ingredient_product_id, v_recipe.ingredient_variant_id, v_recipe.quantity * v_quantity, v_product_name);
    end loop;

    -- Stock deduction only for tracked units (stock_unit != 'NONE'),
    -- and only for lines WITHOUT a recipe mapping.
    if v_recipe_id is null then
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
    end if;
  end loop;

  -- Deduct the aggregated ingredient needs: one row-locked, guarded
  -- deduction per ingredient, so concurrent sales cannot drive a shared
  -- source negative. Failures name the MENU product, exactly like the local
  -- repository, so the client's failure mapping is unchanged.
  for v_recipe in select ingredient_product_id, ingredient_variant_id, sum(need)::int as total, max(menu_name) as menu
    from t_recipe_needs group by ingredient_product_id, ingredient_variant_id
  loop
    if v_recipe.ingredient_variant_id is not null then
      select stock_quantity, is_active into v_ing_stock, v_ing_active
        from public.product_variants where id = v_recipe.ingredient_variant_id for update;
      if not found or v_ing_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_recipe.menu using errcode='P0001'; end if;
      if v_ing_stock < v_recipe.total then raise exception 'INSUFFICIENT_STOCK: %', v_recipe.menu using errcode='P0001'; end if;
      update public.product_variants set stock_quantity = stock_quantity - v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_variant_id;
    else
      select stock_quantity, is_active into v_ing_stock, v_ing_active
        from public.products where id = v_recipe.ingredient_product_id for update;
      if not found or v_ing_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_recipe.menu using errcode='P0001'; end if;
      if v_ing_stock < v_recipe.total then raise exception 'INSUFFICIENT_STOCK: %', v_recipe.menu using errcode='P0001'; end if;
      update public.products set stock_quantity = stock_quantity - v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_product_id;
    end if;
  end loop;

  -- Insert sale header. A split sale stores NULL in payment_method: the header
  -- has no single instrument, and the legs in sale_payments are the record.
  insert into public.sales (id, shop_id, customer_id, receipt_number, subtotal_paise, total_paise, offer_discount_paise, payment_method, payment_status, client_created_at, created_at, updated_at, voided, voided_at)
  values (v_sale_id, p_shop_id, p_customer_id, v_receipt, p_subtotal_paise, p_total_paise, p_offer_discount_paise,
          case when p_payments is not null then null else p_payment_method end,
          p_payment_status, v_now, v_now, v_now, false, null);

  -- Insert sale items + stock movements
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

    -- Movement only for tracked, unmapped lines: a mapped line's audit rows
    -- are the aggregated ingredient movements written below.
    select id into v_recipe_id from public.product_recipes
      where shop_id = p_shop_id and product_id = v_product_id
        and (variant_id is null or variant_id = v_variant_id) limit 1;
    if not found then
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
    end if;
  end loop;

  -- One SALE movement per aggregated ingredient (negative quantity, exact
  -- before/after, reference SALE/sale id) — the audit twin of the local leg.
  for v_recipe in select ingredient_product_id, ingredient_variant_id, sum(need)::int as total
    from t_recipe_needs group by ingredient_product_id, ingredient_variant_id
  loop
    if v_recipe.ingredient_variant_id is not null then
      select stock_quantity into v_stock from public.product_variants where id = v_recipe.ingredient_variant_id;
      insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
      values (gen_random_uuid(), p_shop_id, v_recipe.ingredient_product_id, v_recipe.ingredient_variant_id, 'SALE', -v_recipe.total, v_stock + v_recipe.total, v_stock, 'SALE', v_sale_id, v_now, v_now);
    else
      select stock_quantity into v_stock from public.products where id = v_recipe.ingredient_product_id;
      insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
      values (gen_random_uuid(), p_shop_id, v_recipe.ingredient_product_id, null, 'SALE', -v_recipe.total, v_stock + v_recipe.total, v_stock, 'SALE', v_sale_id, v_now, v_now);
    end if;
  end loop;

  -- Persist the split legs. Already validated above, so these cannot fail.
  if p_payments is not null then
    for v_payment in select * from jsonb_array_elements(p_payments)
    loop
      insert into public.sale_payments (sale_id, payment_method, amount_paise)
      values (v_sale_id, v_payment->>'payment_method', (v_payment->>'amount_paise')::int);
    end loop;
  end if;

  return jsonb_build_object('id', v_sale_id, 'receipt_number', v_receipt, 'created_at', v_now);
end; $$;

-- The signature is unchanged, so 0015's per-function guards, the RLS-adjacent
-- grants and the PostgREST candidate set all carry over untouched.
grant execute on function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Recipe-aware void_sale_atomic (same 1-arg signature as 0011)
-- ---------------------------------------------------------------------------
create or replace function public.void_sale_atomic(p_sale_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_shop_id uuid;
  v_voided boolean;
  v_now timestamptz := now();
  v_item record;
  v_stock_unit text;
  v_recipe record;
  v_mapped uuid;
begin
  select shop_id, voided into v_shop_id, v_voided from public.sales where id = p_sale_id for update;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;
  if not public.is_shop_member(v_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_voided = true then raise exception 'ALREADY_VOIDED'; end if;

  -- Shared-stock accumulator: one row per line-ingredient restore.
  create temporary table t_recipe_restore (
    ingredient_product_id uuid,
    ingredient_variant_id uuid,
    qty integer not null
  ) on commit drop;

  -- Restore stock per item
  for v_item in select product_id, variant_id, quantity from public.sale_items where sale_id = p_sale_id
  loop
    -- A line that was sold through a recipe restores ONLY its ingredients;
    -- the menu row's own stock was never touched by the sale, so restoring
    -- it here would conjure units that were never lost. Current mappings
    -- apply, exactly like the local void path.
    v_mapped := null;
    for v_recipe in select ingredient_product_id, ingredient_variant_id
      from public.product_recipes
      where shop_id = v_shop_id and product_id = v_item.product_id
        and (variant_id is null or variant_id = v_item.variant_id)
    loop
      v_mapped := v_recipe.ingredient_product_id;
      insert into t_recipe_restore (ingredient_product_id, ingredient_variant_id, qty)
        values (v_recipe.ingredient_product_id, v_recipe.ingredient_variant_id, v_item.quantity);
    end loop;
    if v_mapped is null then
      select stock_unit into v_stock_unit from public.products where id = v_item.product_id;
      if v_stock_unit != 'NONE' then
        if v_item.variant_id is not null then
          update public.product_variants set stock_quantity = stock_quantity + v_item.quantity, updated_at = v_now where id = v_item.variant_id;
        else
          update public.products set stock_quantity = stock_quantity + v_item.quantity, updated_at = v_now where id = v_item.product_id;
        end if;
      end if;
    end if;
  end loop;

  -- Restore the aggregated ingredient totals.
  for v_recipe in select ingredient_product_id, ingredient_variant_id, sum(qty)::int as total
    from t_recipe_restore group by ingredient_product_id, ingredient_variant_id
  loop
    if v_recipe.ingredient_variant_id is not null then
      update public.product_variants set stock_quantity = stock_quantity + v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_variant_id;
    else
      update public.products set stock_quantity = stock_quantity + v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_product_id;
    end if;
  end loop;

  -- Reverse customer payments linked to this sale
  update public.customer_payments set reversed = true, reversed_at = v_now, updated_at = v_now
    where sale_id = p_sale_id and reversed = false;

  -- Mark sale voided
  update public.sales set voided = true, voided_at = v_now, updated_at = v_now where id = p_sale_id;

  return jsonb_build_object('id', p_sale_id, 'voided_at', v_now);
end; $$;

grant execute on function public.void_sale_atomic(uuid) to authenticated;
