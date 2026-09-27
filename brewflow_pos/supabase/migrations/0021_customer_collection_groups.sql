-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0021: Customer Collections (grouped partial due payments)
-- Online-only authoritative write for the customer-level "Collect Payment"
-- flow: one submission allocates across the oldest open bills first, splits
-- into one row per touched bill, stamps every row with a shared
-- payment_group_id, and is safely replayable (idempotent).
-- Does not reset sequences or mutate existing rows.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Schema: payment group column + idempotency backstop index
-- ---------------------------------------------------------------------------
alter table public.customer_payments
  add column if not exists payment_group_id uuid;

create index if not exists idx_customer_payments_group
  on public.customer_payments (payment_group_id, sale_id);

-- ---------------------------------------------------------------------------
-- B. Collection atomic RPC
--
-- Semantics (kept exactly in lock-step with the drift offline core):
--   * p_group_id identifies the whole submission. When rows already exist for
--     the group (and are not reversed) the call is a no-op replay that simply
--     returns those rows — it can never double-credit the customer.
--   * Only open credit sales generate due: NOT_PAID, non-voided, customer
--     belonging to the shop, with remaining > 0.
--   * Allocation walks those sales oldest-first (created_at, then id) and
--     splits p_amount_paise into one payment row per touched bill.
--   * Selling a bill fully settles it to PAID (payment_status + method).
--   * Overpayments are rejected with PAYMENT_EXCEEDS_DUE; the walk's leftover
--     guard re-checks under the row lock even if the fast reject raced.
-- ---------------------------------------------------------------------------
create or replace function public.collect_customer_payment_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_group_id uuid,
  p_amount_paise integer,
  p_payment_method text,
  p_note text
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_now timestamptz := now();
  v_customer_active boolean;
  v_total_outstanding int;
  v_payments jsonb := '[]'::jsonb;
  v_amount_left int;
  v_sale record;
  v_paid_on_sale int;
  v_remaining_on_sale int;
  v_alloc int;
  v_sale_status text;
  v_replay jsonb;
  v_payment_id uuid;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  if p_group_id is null then
    raise exception 'INVALID_GROUP';
  end if;

  if p_amount_paise <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  if p_payment_method not in ('CASH','UPI','BANK') then
    raise exception 'INVALID_PAYMENT_METHOD';
  end if;

  -- Validate customer belongs to shop and is active
  select is_active into v_customer_active
  from public.customers where id = p_customer_id and shop_id = p_shop_id;
  if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
  if v_customer_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;

  -- Idempotent replay: this submission already landed (retry after a lost
  -- response). Return the stored rows verbatim — nothing is written again.
  select jsonb_build_object('payments', coalesce(jsonb_agg(jsonb_build_object(
    'id', cp.id,
    'sale_id', cp.sale_id,
    'amount_paise', cp.amount_paise,
    'paid_at', cp.paid_at,
    'sale_payment_status', (
      select s.payment_status from public.sales s where s.id = cp.sale_id
    )
  ) order by cp.created_at asc), '[]'::jsonb))
  into v_replay
  from public.customer_payments cp
  where cp.shop_id = p_shop_id
    and cp.customer_id = p_customer_id
    and cp.payment_group_id = p_group_id
    and cp.reversed = false;
  if v_replay is not null then
    return v_replay;
  end if;

  -- Fast reject for clear overpayments (the locked walk re-checks too).
  select coalesce(sum(o.total_paise - o.paid), 0) into v_total_outstanding
  from (
    select s.total_paise,
      coalesce((
        select sum(cp.amount_paise) from public.customer_payments cp
        where cp.sale_id = s.id and cp.reversed = false
      ), 0) as paid
    from public.sales s
    where s.shop_id = p_shop_id
      and s.customer_id = p_customer_id
      and s.voided = false
      and s.payment_status <> 'PAID'
  ) o;
  if p_amount_paise > v_total_outstanding then
    raise exception 'PAYMENT_EXCEEDS_DUE';
  end if;

  -- Walk the customer's open bills oldest-first; the sales row-level locks
  -- serialize concurrent collections for the same customer.
  v_amount_left := p_amount_paise;
  for v_sale in
    select s.id, s.total_paise
    from public.sales s
    where s.shop_id = p_shop_id
      and s.customer_id = p_customer_id
      and s.voided = false
      and s.payment_status <> 'PAID'
      and (
        select coalesce(sum(cp.amount_paise), 0) from public.customer_payments cp
        where cp.sale_id = s.id and cp.reversed = false
      ) < s.total_paise
    order by s.created_at asc, s.id asc
    for update
  loop
    select coalesce(sum(amount_paise), 0) into v_paid_on_sale
    from public.customer_payments
    where sale_id = v_sale.id and reversed = false;

    v_remaining_on_sale := v_sale.total_paise - v_paid_on_sale;
    v_alloc := least(v_amount_left, v_remaining_on_sale);
    if v_alloc > 0 then
      v_payment_id := gen_random_uuid();
      insert into public.customer_payments (
        id, shop_id, customer_id, sale_id, payment_group_id, amount_paise,
        payment_method, note, paid_at, reversed, reversed_at,
        client_created_at, created_at, updated_at
      ) values (
        v_payment_id, p_shop_id, p_customer_id, v_sale.id, p_group_id,
        v_alloc, p_payment_method, nullif(p_note,''), v_now, false, null,
        v_now, v_now, v_now
      );

      -- Settle the bill as soon as it is fully covered.
      if v_paid_on_sale + v_alloc >= v_sale.total_paise then
        update public.sales
        set payment_status = 'PAID',
            payment_method = p_payment_method,
            updated_at = v_now
        where id = v_sale.id;
        v_sale_status := 'PAID';
      else
        v_sale_status := 'NOT_PAID';
      end if;

      v_payments := v_payments || jsonb_build_object(
        'id', v_payment_id,
        'sale_id', v_sale.id,
        'amount_paise', v_alloc,
        'paid_at', v_now,
        'sale_payment_status', v_sale_status
      );

      v_amount_left := v_amount_left - v_alloc;
      if v_amount_left = 0 then
        exit;
      end if;
    end if;
  end loop;

  -- Under-lock re-check: any leftover means the outstanding shrank while we
  -- waited (another collection covered part of the dues) — reject, write nothing.
  if v_amount_left > 0 then
    raise exception 'PAYMENT_EXCEEDS_DUE';
  end if;

  return jsonb_build_object('payments', v_payments);
end; $$;

grant execute on function public.collect_customer_payment_atomic(uuid, uuid, uuid, integer, text, text) to authenticated;