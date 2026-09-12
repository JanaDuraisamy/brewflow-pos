-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0012: Customer Payments & Stock Adjustments Atomic RPCs
-- Online-only authoritative writes for remaining gaps.
-- Preserves receipt/purchase sequences, does not reset data.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Customer payment atomic RPC
-- ---------------------------------------------------------------------------
create or replace function public.record_customer_payment_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_sale_id uuid,
  p_amount_paise integer,
  p_payment_method text,
  p_note text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_payment_id uuid := gen_random_uuid();
  v_now timestamptz := now();
  v_sale_total int;
  v_sale_customer uuid;
  v_sale_status text;
  v_sale_shop uuid;
  v_sale_voided boolean;
  v_customer_active boolean;
  v_paid_so_far int;
  v_remaining int;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if p_amount_paise <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  if p_payment_method not in ('CASH','UPI','BANK') then
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;

  -- Validate customer belongs to shop and active
  select is_active into v_customer_active from public.customers where id = p_customer_id and shop_id = p_shop_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if v_customer_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;

  -- Lock sale and validate shop/customer/voided
  select shop_id, customer_id, total_paise, payment_status, voided into v_sale_shop, v_sale_customer, v_sale_total, v_sale_status, v_sale_voided
  from public.sales where id = p_sale_id for update;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;
  if v_sale_shop != p_shop_id then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_sale_customer is not null and v_sale_customer != p_customer_id then raise exception 'SALE_NOT_FOUND'; end if;
  if v_sale_voided = true then raise exception 'SALE_VOIDED'; end if;

  -- Only NOT_PAID sales generate due; but allow payments for any sale where remaining >0 (PAID sales have remaining 0, so will throw)
  select coalesce(sum(amount_paise),0) into v_paid_so_far from public.customer_payments where sale_id = p_sale_id and reversed = false;
  v_remaining := v_sale_total - v_paid_so_far;
  if p_amount_paise > v_remaining then
    raise exception 'PAYMENT_EXCEEDS_DUE';
  end if;

  -- Insert payment
  insert into public.customer_payments (id, shop_id, customer_id, sale_id, amount_paise, payment_method, note, paid_at, reversed, reversed_at, client_created_at, created_at, updated_at)
  values (v_payment_id, p_shop_id, p_customer_id, p_sale_id, p_amount_paise, p_payment_method, nullif(p_note,''), v_now, false, null, v_now, v_now, v_now);

  -- If fully paid, settle sale to PAID
  if v_paid_so_far + p_amount_paise >= v_sale_total and v_sale_status != 'PAID' then
    update public.sales set payment_status = 'PAID', payment_method = p_payment_method, updated_at = v_now where id = p_sale_id;
  end if;

  return jsonb_build_object('id', v_payment_id, 'paid_at', v_now, 'remaining', v_remaining - p_amount_paise);
end; $$;

grant execute on function public.record_customer_payment_atomic(uuid, uuid, uuid, integer, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- B. Stock adjustment / opening atomic RPC
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

  if p_reason is not null and p_reason not in ('OPENING','ADJUSTMENT_IN','ADJUSTMENT_OUT','DAMAGE','EXPIRED','CORRECTION') then
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

-- Ensure stock_movements and customer_payments have correct RLS (already from 0011, but ensure)
alter table public.customer_payments enable row level security;
alter table public.stock_movements enable row level security;

-- No sequence reset; preserve existing data
