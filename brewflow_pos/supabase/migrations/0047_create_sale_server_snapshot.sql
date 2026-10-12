-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0047: create_sale_atomic persists a server-derived snapshot
--
-- Problem (confirmed against 0046): the deduction reads the AUTHORITATIVE
-- `product_recipes` rows inside the transaction, but `sale_items.consumed`
-- is stored VERBATIM from the client-supplied `consumed` key. Any recipe
-- edit/clear/remap between the client's snapshot read and the server's
-- execution — or any stale/forged client payload — persists a snapshot that
-- disagrees with what was actually deducted. `void_sale_atomic` (0045)
-- restores from the stored snapshot, so the void then credits back the wrong
-- ingredients/quantities and silently corrupts stock.
--
-- Two further hardening gaps in the same function:
--   a. the ingredient deduction loop aggregates without ORDER BY, so
--      concurrent sales lock shared ingredients in nondeterministic order
--      (deadlock risk); the void path already orders deterministically.
--   b. the ingredient SELECT ... FOR UPDATE / UPDATE statements filter by id
--      only, without `shop_id = p_shop_id`, unlike the void restores — a
--      recipe row pointing at another shop's product would deduct (and the
--      void would then refuse to credit) across the tenant boundary.
--
-- What changes (append-only; 0044-0046 are untouched): a same-signature
-- `CREATE OR REPLACE FUNCTION public.create_sale_atomic(...)` where:
--   1. the temp accumulator gains the per-line index, and each line's
--      `consumed` is DERIVED server-side from the same temp rows that drove
--      the deduction (per-unit quantities = accumulated need / line qty,
--      exact integer division), aggregated per ingredient and ordered
--      deterministically. Unmapped lines persist `[]` exactly as before.
--      The client `consumed` key is still accepted for backward compatibility
--      but is never read for persistence.
--   2. the ingredient deduction loop carries
--      `order by ingredient_product_id, ingredient_variant_id`, matching the
--      void's lock order.
--   3. every ingredient stock SELECT ... FOR UPDATE and UPDATE is scoped with
--      `and shop_id = p_shop_id`.
-- Everything else is byte-for-byte 0046's function.
--
-- Backward compatible: old clients (no `consumed` key) and new clients (any
-- `consumed` value) get the identical server-derived snapshot; the void
-- contract (0045) is unchanged and keeps working on both old and new rows.
--
-- No migration is applied here; this file is reviewed for a later staged
-- (non-production) Supabase deployment. Static SQL tests are not runtime
-- Postgres validation — staging verification is still required.
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
  v_line_idx int := 0;
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
  v_consumed jsonb;
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

  -- Shared-stock accumulator: one row per line-ingredient, tagged with the
  -- line index so the per-line snapshot below is rebuilt from the SAME rows
  -- that drove the deduction. The GROUP BY at deduction time collapses
  -- repeats (including NULL variant ids, which a PRIMARY KEY could not hold)
  -- into a single total per ingredient.
  create temporary table t_recipe_needs (
    line_idx integer not null,
    ingredient_product_id uuid,
    ingredient_variant_id uuid,
    need integer not null,
    menu_name text not null
  ) on commit drop;

  -- Process each line: lock stock row, check, deduct
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_line_idx := v_line_idx + 1;
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
      insert into t_recipe_needs (line_idx, ingredient_product_id, ingredient_variant_id, need, menu_name)
        values (v_line_idx, v_recipe.ingredient_product_id, v_recipe.ingredient_variant_id, v_recipe.quantity * v_quantity, v_product_name);
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
  -- deduction per ingredient, in a FIXED (product, variant) order matching
  -- the void's lock order, so concurrent sales cannot deadlock while driving
  -- a shared source. Failures name the MENU product, exactly like the local
  -- repository, so the client's failure mapping is unchanged.
  for v_recipe in select ingredient_product_id, ingredient_variant_id, sum(need)::int as total, max(menu_name) as menu
    from t_recipe_needs group by ingredient_product_id, ingredient_variant_id
    order by ingredient_product_id, ingredient_variant_id
  loop
    if v_recipe.ingredient_variant_id is not null then
      select stock_quantity, is_active into v_ing_stock, v_ing_active
        from public.product_variants where id = v_recipe.ingredient_variant_id and shop_id = p_shop_id for update;
      if not found or v_ing_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_recipe.menu using errcode='P0001'; end if;
      if v_ing_stock < v_recipe.total then raise exception 'INSUFFICIENT_STOCK: %', v_recipe.menu using errcode='P0001'; end if;
      update public.product_variants set stock_quantity = stock_quantity - v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_variant_id and shop_id = p_shop_id;
    else
      select stock_quantity, is_active into v_ing_stock, v_ing_active
        from public.products where id = v_recipe.ingredient_product_id and shop_id = p_shop_id for update;
      if not found or v_ing_active = false then raise exception 'UNAVAILABLE_PRODUCT: %', v_recipe.menu using errcode='P0001'; end if;
      if v_ing_stock < v_recipe.total then raise exception 'INSUFFICIENT_STOCK: %', v_recipe.menu using errcode='P0001'; end if;
      update public.products set stock_quantity = stock_quantity - v_recipe.total, updated_at = v_now
        where id = v_recipe.ingredient_product_id and shop_id = p_shop_id;
    end if;
  end loop;

  -- Insert sale header. A split sale stores NULL in payment_method: the header
  -- has no single instrument, and the legs in sale_payments are the record.
  insert into public.sales (id, shop_id, customer_id, receipt_number, subtotal_paise, total_paise, offer_discount_paise, payment_method, payment_status, client_created_at, created_at, updated_at, voided, voided_at)
  values (v_sale_id, p_shop_id, p_customer_id, v_receipt, p_subtotal_paise, p_total_paise, p_offer_discount_paise,
          case when p_payments is not null then null else p_payment_method end,
          p_payment_status, v_now, v_now, v_now, false, null);

  -- Insert sale items + stock movements
  v_line_idx := 0;
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_line_idx := v_line_idx + 1;
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
    -- Server-authoritative snapshot (0047): rebuilt from the same temp rows
    -- that drove the deduction above — per line, per ingredient, per-unit
    -- quantities (need / line quantity; exact, since need was accumulated as
    -- per-unit x quantity), aggregated and ordered deterministically. A line
    -- with no temp rows persists `[]` (known-empty, own stock may be
    -- tracked), exactly as before. The client-supplied `consumed` key is
    -- still accepted for backward compatibility but is never read here, so a
    -- stale or forged snapshot can no longer diverge a later void from what
    -- was actually deducted.
    select coalesce(
      (select jsonb_agg(
                jsonb_build_object(
                  'ip', s.ingredient_product_id,
                  'iv', s.ingredient_variant_id,
                  'q', s.per_unit)
                order by s.ingredient_product_id, s.ingredient_variant_id)
         from (select ingredient_product_id, ingredient_variant_id,
                      sum(need) / v_quantity as per_unit
                 from t_recipe_needs
                where line_idx = v_line_idx
                group by ingredient_product_id, ingredient_variant_id) s),
      '[]'::jsonb)
      into v_consumed;

    insert into public.sale_items (id, shop_id, sale_id, product_id, variant_id, product_name, variant_name, sku, unit_price_paise, quantity, line_total_paise, offer_discount_paise, applied_offer_id, applied_offer_name, applied_offer_type, consumed, client_created_at, created_at, updated_at)
    values (gen_random_uuid(), p_shop_id, v_sale_id, v_product_id, v_variant_id, v_product_name, v_variant_name, v_sku, v_unit_price, v_quantity, v_line_total, v_offer_discount, v_applied_offer_id, v_applied_offer_name, v_applied_offer_type, v_consumed, v_now, v_now, v_now);

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

-- CREATE OR REPLACE resets proconfig, so 0015's guards (copied verbatim from
-- 0015:38-45) are re-issued; the signature is unchanged so the grant and the
-- PostgREST candidate set are restored explicitly too.
grant execute on function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) to authenticated;

alter function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) set statement_timeout = '20s';

alter function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) set lock_timeout = '10s';

alter function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) set idle_in_transaction_session_timeout = '30s';
