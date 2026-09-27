-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0022: Fix collect_customer_payment_atomic replay guard
--
-- ROOT CAUSE (Rin / ₹910 bill / ₹20 partial rejected with
-- "This payment is more than the remaining balance."):
--   The idempotent-replay block used
--     SELECT jsonb_build_object('payments', coalesce(jsonb_agg(...), '[]'))
--     INTO v_replay ... ;
--     IF v_replay IS NOT NULL THEN RETURN v_replay; END IF;
--   An aggregate SELECT without GROUP BY ALWAYS returns exactly one row
--   (jsonb_agg over an empty set is NULL, coalesced to '[]'), so
--   `v_replay IS NOT NULL` was ALWAYS true. Every FIRST collection returned
--   `{"payments": []}` without ever reaching the fast-reject / walk, and the
--   Flutter client maps an empty payments array to PaymentExceedsDueFailure
--   (drift_customer_ledger_repository.dart:430-433) — hence the exact
--   user-visible message for ANY amount, even ₹20 against ₹910 outstanding.
--
-- FIX: only take the replay path when the group actually has stored rows
-- (payments array length > 0). True replays still return verbatim; fresh
-- groups fall through to the fast-reject + oldest-first walk.
--
-- 0021 is left untouched (immutable history); this file re-declares the
-- function with the single guard corrected, everything else byte-identical.
-- Does not reset sequences or mutate existing rows.
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
  -- 0022 FIX: the aggregate query below always yields one row (empty group
  -- aggregates to '{"payments": []}'), so the old `IS NOT NULL` test fired
  -- on every fresh group. Gate on the stored array length instead.
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
  if v_replay is not null
     and jsonb_array_length(v_replay -> 'payments') > 0 then
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

-- ---------------------------------------------------------------------------
-- Regression gate (runs at deploy time): fail `db push` if the replay guard
-- ever regresses to the always-true `IS NOT NULL`-only check again.
-- ---------------------------------------------------------------------------
do $$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid) into v_def
  from pg_proc p
  where p.proname = 'collect_customer_payment_atomic'
    and p.pronamespace = 'public'::regnamespace;
  if v_def is null then
    raise exception 'REGRESSION 0022: collect_customer_payment_atomic is missing';
  end if;
  if v_def not like '%jsonb_array_length%' then
    raise exception 'REGRESSION 0022: replay guard must check the stored payments array length';
  end if;
end $$;
