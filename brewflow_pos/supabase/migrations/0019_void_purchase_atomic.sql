-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0019: void_purchase_atomic RPC
--
-- BUG: purchase void was client-local only. A voided purchase was deleted
-- from the local database but never reached the cloud, so the next sync pull
-- re-imported the purchase (and its stock) on every device, silently
-- "un-voiding" it. Purchases are cloud-authoritative (receive_purchase_atomic),
-- so voiding must be cloud-authoritative too.
--
-- Fix: void_purchase_atomic reverses exactly the stock each received line
-- added (mirroring the client's local reversal), then removes the purchase,
-- its items and its PURCHASE stock movements in one transaction. The client
-- mirrors the deletion locally after the RPC commits.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

create or replace function public.void_purchase_atomic(
  p_purchase_id uuid
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_shop_id uuid;
  v_item record;
  v_now timestamptz := now();
  v_purchase_number text;
begin
  select shop_id, purchase_number into v_shop_id, v_purchase_number
    from public.purchases where id = p_purchase_id;
  if not found then raise exception 'PURCHASE_NOT_FOUND'; end if;
  if not public.is_shop_member(v_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;

  -- Reverse exactly the stock each received line added, targeting the same
  -- stock entity (product or variant) the line was received into. Stock can
  -- already have been consumed by sales; the reversal is intentionally
  -- analytic (like the prior client-local void) and may drive it negative.
  for v_item in
    select product_id, variant_id, quantity
      from public.purchase_items where purchase_id = p_purchase_id
  loop
    if v_item.variant_id is not null then
      update public.product_variants
        set stock_quantity = stock_quantity - v_item.quantity, updated_at = v_now
      where id = v_item.variant_id;
    else
      update public.products
        set stock_quantity = stock_quantity - v_item.quantity, updated_at = v_now
      where id = v_item.product_id;
    end if;
  end loop;

  -- Remove the purchase with all its history in one transaction.
  delete from public.stock_movements
   where reference_type = 'PURCHASE' and reference_id = p_purchase_id;
  delete from public.purchase_items where purchase_id = p_purchase_id;
  delete from public.purchases where id = p_purchase_id;

  return jsonb_build_object('id', p_purchase_id, 'purchase_number', v_purchase_number, 'voided_at', v_now);
end; $$;

grant execute on function public.void_purchase_atomic(uuid) to authenticated;