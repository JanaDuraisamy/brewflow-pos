-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0018: extend adjust_stock_atomic reason whitelist
--
-- BUG: the RPC whitelist only accepted OPENING / ADJUSTMENT_IN /
-- ADJUSTMENT_OUT / DAMAGE / EXPIRED / CORRECTION. The client's stock
-- adjustment reasons include WASTAGE, MISSING, OTHER and PURCHASE (see
-- StockAdjustmentReason), which were silently coerced to NULL, so the
-- recorded history lost *why* an adjustment happened.
--
-- Fix: accept the full stable client set. The reason column is plain text
-- on the server (no CHECK), so this is a pure whitelist enlargement —
-- existing rows are untouched.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

create or replace function public.adjust_stock_atomic(
  p_shop_id uuid,
  p_product_id uuid,
  p_variant_id uuid,
  p_delta integer,
  p_reason text,
  p_note text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_movement_id uuid := gen_random_uuid();
  v_stock_before int;
  v_stock_after int;
  v_movement_type text;
  v_product_shop uuid;
  v_variant_shop uuid;
  v_product_active boolean;
  v_variant_active boolean;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if p_delta = 0 then
    raise exception 'INVALID_QUANTITY';
  end if;

  if p_reason is not null and p_reason not in ('OPENING','ADJUSTMENT_IN','ADJUSTMENT_OUT','DAMAGE','EXPIRED','CORRECTION','WASTAGE','MISSING','OTHER','PURCHASE') then
    p_reason := null;
  end if;

  v_movement_type := case when p_delta > 0 then 'ADJUSTMENT_IN' else 'ADJUSTMENT_OUT' end;
  -- Allow explicit OPENING when stock_before =0 and delta>0 and reason OPENING
  if p_reason = 'OPENING' then
    v_movement_type := 'OPENING';
  end if;

  if p_variant_id is not null then
    -- Lock variant and validate shop
    select shop_id, stock_quantity, is_active into v_variant_shop, v_stock_before, v_variant_active
    from public.product_variants where id = p_variant_id for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if v_variant_shop != p_shop_id then raise exception 'FORBIDDEN' using errcode='42501'; end if;
    if v_variant_active = false then raise exception 'INACTIVE_PRODUCT'; end if;
    -- Ensure parent product also belongs to shop (optional check)
    select shop_id into v_product_shop from public.products where id = p_product_id;
    if not found or v_product_shop != p_shop_id then raise exception 'PRODUCT_NOT_FOUND'; end if;
    v_stock_after := v_stock_before + p_delta;
    if v_stock_after < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
    update public.product_variants set stock_quantity = v_stock_after, updated_at = v_now where id = p_variant_id;
  else
    -- Lock product
    select shop_id, stock_quantity, is_active into v_product_shop, v_stock_before, v_product_active
    from public.products where id = p_product_id for update;
    if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;
    if v_product_shop != p_shop_id then raise exception 'FORBIDDEN' using errcode='42501'; end if;
    if v_product_active = false then raise exception 'INACTIVE_PRODUCT'; end if;
    v_stock_after := v_stock_before + p_delta;
    if v_stock_after < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;
    update public.products set stock_quantity = v_stock_after, updated_at = v_now where id = p_product_id;
  end if;

  insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reason, note, reference_type, reference_id, created_at, updated_at)
  values (v_movement_id, p_shop_id, p_product_id, p_variant_id, v_movement_type, p_delta, v_stock_before, v_stock_after, p_reason, p_note, null, null, v_now, v_now);

  return jsonb_build_object('id', v_movement_id, 'stock_before', v_stock_before, 'stock_after', v_stock_after, 'created_at', v_now);
end; $$;

grant execute on function public.adjust_stock_atomic(uuid, uuid, uuid, integer, text, text) to authenticated;