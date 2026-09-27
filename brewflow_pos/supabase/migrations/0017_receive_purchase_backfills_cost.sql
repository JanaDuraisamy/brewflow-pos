-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0017: receive_purchase_atomic backfills cost price
--
-- BUG: receiving a purchase only increased stock. products.variant cost
-- prices never updated, so profit reports kept showing "Add cost prices"
-- even after re-ordering stock at a new cost.
--
-- Fix: when a received line carries a unit cost, backfill the product (or
-- variant) cost_price_paise with the newest purchase cost within the same
-- atomic transaction. The most recent received cost is the natural "latest
-- cost" heuristic the app's profit reporting already expects.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

create or replace function public.receive_purchase_atomic(
  p_shop_id uuid,
  p_supplier_id uuid,
  p_notes text,
  p_lines jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_purchase_id uuid := gen_random_uuid();
  v_purchase_number text;
  v_now timestamptz := now();
  v_subtotal integer := 0;
  v_line jsonb;
  v_product_id uuid;
  v_variant_id uuid;
  v_quantity int;
  v_unit_cost int;
  v_line_total int;
  v_is_active boolean;
  v_stock_before int;
  v_stock_after int;
  v_next int;
begin
  if not public.is_shop_member(p_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if p_lines is null or jsonb_array_length(p_lines)=0 then raise exception 'EMPTY_PURCHASE'; end if;
  if p_supplier_id is not null then
    select is_active into v_is_active from public.suppliers where id = p_supplier_id and shop_id = p_shop_id;
    if not found then raise exception 'UNKNOWN_SUPPLIER'; end if;
    if v_is_active = false then raise exception 'INACTIVE_SUPPLIER'; end if;
  end if;

  -- Validate lines & compute subtotal, lock stock rows
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    v_unit_cost := (v_line->>'unit_cost_paise')::int;
    if v_quantity <= 0 then raise exception 'INVALID_QUANTITY'; end if;
    if v_unit_cost < 0 then raise exception 'INVALID_COST'; end if;
    select is_active into v_is_active from public.products where id = v_product_id and shop_id = p_shop_id for update;
    if not found then raise exception 'UNKNOWN_PRODUCT: %', v_product_id; end if;
    if v_is_active = false then raise exception 'INACTIVE_PRODUCT'; end if;
    if v_variant_id is not null then
      select is_active into v_is_active from public.product_variants where id = v_variant_id and shop_id = p_shop_id for update;
      if not found then raise exception 'UNKNOWN_PRODUCT: %', v_variant_id; end if;
      if v_is_active = false then raise exception 'INACTIVE_PRODUCT'; end if;
    end if;
    v_line_total := v_unit_cost * v_quantity;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  -- Allocate purchase number (row-locked)
  insert into public.purchase_sequences (shop_id, next_value) values (p_shop_id, 0) on conflict (shop_id) do nothing;
  select next_value into v_next from public.purchase_sequences where shop_id = p_shop_id for update;
  update public.purchase_sequences set next_value = v_next + 1 where shop_id = p_shop_id returning next_value into v_next;
  v_purchase_number := 'PUR-' || lpad(v_next::text, 6, '0');

  -- Increase stock & record movements
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    if v_variant_id is not null then
      select stock_quantity into v_stock_before from public.product_variants where id = v_variant_id;
      update public.product_variants set
        stock_quantity = stock_quantity + v_quantity,
        cost_price_paise = case
          -- Only upgrade when a real cost was supplied (0 = free/unknown keep existing)
          when v_unit_cost > 0 then v_unit_cost
          else cost_price_paise
        end,
        updated_at = v_now
      where id = v_variant_id returning stock_quantity into v_stock_after;
      insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
        values (gen_random_uuid(), p_shop_id, v_product_id, v_variant_id, 'PURCHASE', v_quantity, v_stock_before, v_stock_after, 'PURCHASE', v_purchase_id, v_now, v_now);
    else
      select stock_quantity into v_stock_before from public.products where id = v_product_id;
      update public.products set
        stock_quantity = stock_quantity + v_quantity,
        cost_price_paise = case
          when v_unit_cost > 0 then v_unit_cost
          else cost_price_paise
        end,
        updated_at = v_now
      where id = v_product_id returning stock_quantity into v_stock_after;
      insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
        values (gen_random_uuid(), p_shop_id, v_product_id, null, 'PURCHASE', v_quantity, v_stock_before, v_stock_after, 'PURCHASE', v_purchase_id, v_now, v_now);
    end if;
  end loop;

  -- Insert purchase header
  insert into public.purchases (id, shop_id, supplier_id, purchase_number, subtotal_paise, total_paise, notes, created_at, updated_at)
  values (v_purchase_id, p_shop_id, p_supplier_id, v_purchase_number, v_subtotal, v_subtotal, p_notes, v_now, v_now);

  -- Insert purchase items (snapshot product names)
  for v_line in select * from jsonb_array_elements(p_lines)
  loop
    v_product_id := (v_line->>'product_id')::uuid;
    v_variant_id := nullif(v_line->>'variant_id','')::uuid;
    v_quantity := (v_line->>'quantity')::int;
    v_unit_cost := (v_line->>'unit_cost_paise')::int;
    v_line_total := v_unit_cost * v_quantity;
    -- snapshot name/sku
    declare v_p_name text; v_p_sku text; v_v_name text; v_v_sku text;
    begin
      select name, sku into v_p_name, v_p_sku from public.products where id = v_product_id;
      if v_variant_id is not null then select name, sku into v_v_name, v_v_sku from public.product_variants where id = v_variant_id; end if;
      insert into public.purchase_items (id, shop_id, purchase_id, product_id, variant_id, product_name, variant_name, sku, unit_cost_paise, quantity, line_total_paise, created_at, updated_at)
      values (gen_random_uuid(), p_shop_id, v_purchase_id, v_product_id, v_variant_id, v_p_name, v_v_name, coalesce(v_v_sku, v_p_sku), v_unit_cost, v_quantity, v_line_total, v_now, v_now);
    end;
  end loop;

  return jsonb_build_object('id', v_purchase_id, 'purchase_number', v_purchase_number, 'subtotal', v_subtotal, 'created_at', v_now);
end; $$;

grant execute on function public.receive_purchase_atomic(uuid, uuid, text, jsonb) to authenticated;