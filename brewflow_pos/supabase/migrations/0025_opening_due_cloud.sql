-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0025: Cross-device Customer Opening Due (flagged cloud sale)
--
-- Owner requirement: a customer's OPENING BALANCE (pre-billing debt recorded
-- via the ledger) MUST NOT stay local-device-only. Once recorded on the
-- tablet it must appear on the owner's phone after login (same shop scope),
-- and payments collected against it on either device must keep working.
--
-- Design: an opening balance is stored in `sales` as a FLAGGED row
-- (is_opening_balance = true). It carries no sale items (no stock is ever
-- touched), never appears in Orders/Reports/Sales totals, and yet flows
-- through the exact same NOT_PAID derivation as a credit sale — so the
-- existing record_customer_payment_atomic / collect_customer_payment_atomic
-- RPCs pay it down with zero changes. The existing local filters already
-- exclude is_opening_balance = true rows from business totals, so the flag
-- is purely additive and safe to back-fill as false for every existing sale.
--
-- Record path:
--   online  → record_opening_due_atomic() RPC (validates membership/amount/
--             customer, mints a gapless BF- receipt via the shared
--             sale_sequences counter so it can never collide with a counter
--             receipt, inserts the flagged NOT_PAID row) then mirrors locally
--             on the writing device
--   signed-out / offline → local row + a SALE outbox entry carrying the flag;
--             the sync engine pushes it through the normal sales upsert path
--             (applier + pull preserve the flag).
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS is_opening_balance boolean NOT NULL DEFAULT false;

-- ---------------------------------------------------------------------------
-- RPC: record_opening_due_atomic
-- ---------------------------------------------------------------------------
create or replace function public.record_opening_due_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_amount_paise integer
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sale_id uuid := gen_random_uuid();
  v_receipt text;
  v_now timestamptz := now();
  v_customer_active boolean;
  v_next int;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if p_amount_paise <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  -- Validate customer belongs to shop and is active
  select is_active into v_customer_active
    from public.customers where id = p_customer_id and shop_id = p_shop_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if v_customer_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;

  -- Allocate receipt atomically (row-locked gapless counter, shared with
  -- create_sale_atomic so receipts never collide)
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  select next_value into v_next from public.sale_sequences
    where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_next + 1
    where shop_id = p_shop_id returning next_value into v_next;
  v_receipt := 'BF-' || lpad(v_next::text, 6, '0');

  -- Ledger-only flagged credit row: no items, no payment method, NOT_PAID,
  -- subtotal = total = amount, never voided by definition yet.
  insert into public.sales (id, shop_id, customer_id, receipt_number,
    subtotal_paise, total_paise, offer_discount_paise, payment_method,
    payment_status, client_created_at, created_at, updated_at, voided,
    voided_at, is_opening_balance)
  values (v_sale_id, p_shop_id, p_customer_id, v_receipt,
    p_amount_paise, p_amount_paise, 0, null, 'NOT_PAID',
    v_now, v_now, v_now, false, null, true);

  return jsonb_build_object('id', v_sale_id, 'receipt_number', v_receipt, 'created_at', v_now);
end; $$;

grant execute on function public.record_opening_due_atomic(uuid, uuid, integer)
  to authenticated;