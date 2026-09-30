-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0036: Split-payment RPC contract fix
--
-- 0035 shipped a `create_sale_atomic` that cannot run. Every Cloud sale failed
-- with `column "id" of relation "sale_sequences" does not exist` (42703). This
-- migration is the forward fix; 0035 is left untouched because it is already
-- applied in production.
--
-- 1. THE REPORTED CRASH — sale_sequences has no `id`
--    0011 creates sale_sequences with `shop_id` as the SOLE primary key. There
--    has never been an `id` column. 0035 assumed a two-column key
--    (`insert ... (id, shop_id, next_value) ... on conflict (id, shop_id)`),
--    which is the shape of a global GENERATED-ALWAYS sequence, not the
--    per-shop counter this schema actually uses. The receipt allocator is
--    restored to the 0011/0034 per-shop, row-locked form: one counter row per
--    shop, `for update`, increment-and-return. Per-shop isolation and the
--    gapless guarantee are therefore unchanged — Cafe and Food Truck keep
--    independent numbering.
--
-- 2. 0035 DROPPED THE AUTHORIZATION AND THE STOCK LEDGER (worse than the crash)
--    Re-reading 0035 against 0034, the replacement body also lost:
--      * `is_shop_member(p_shop_id)` — a SECURITY DEFINER function with no
--        membership check lets ANY authenticated user sell into ANY shop.
--      * `set search_path = public`.
--      * negative-money, EMPTY_CART and customer active/exists validation.
--      * the entire stock block: row locks, per-variant and per-product
--        deduction, and the `stock_movements` audit rows. A sale through 0035
--        would have sold stock without decrementing it or recording it.
--      * `client_created_at` / `voided` on the sales header.
--      * the per-shop receipt PREFIX from 0034 — 0035 hardcoded 'BF-', so a
--        Food Truck sale would be stamped BF- and be indistinguishable from a
--        Cafe receipt.
--    All of it is restored here. The body below is 0034's, verified against the
--    live schema, plus the split-payment parameters.
--
-- 3. ONE SIGNATURE, NOT TWO
--    Adding a defaulted parameter makes a new OVERLOAD, not a replacement:
--    after 0035 the 8-arg (0034) and 9-arg (0035) variants both existed, so
--    PostgREST had to pick. Both are dropped and a single 9-parameter function
--    is created, with `p_payments` defaulting to null so a client that omits
--    the split key (every pre-0035 build) still resolves to exactly one
--    candidate. DROP and CREATE run in one transaction, so the function is
--    never absent to a concurrent call.
--
-- 4. sale_payments HAD NO RLS
--    0035 created the table and stopped. With RLS disabled and Supabase's
--    default table grants, every authenticated user could read and write every
--    shop's payment legs. Isolation is added here as read-through-the-parent
--    shop: a leg is visible only to a member of the shop that owns the sale it
--    belongs to. The table has no shop_id of its own and one is NOT added — the
--    sale is the authority, so a leg can never disagree with its sale's shop.
--
-- 5. SPLIT-SPECIFIC RULES
--    * Legs must be CASH or UPI only. The table check already enforces it;
--      the RPC rejects it explicitly with a precise error instead of letting a
--      leg abort the whole transaction deep inside the insert loop, which
--      would surface as an opaque constraint violation.
--    * Every leg must be strictly positive, so a zero-value BANK-style leg
--      can never be persisted.
--    * The legs must sum to the charged total, and a split sale stores NULL in
--      `sales.payment_method` — the header has no single method, and the legs
--      in sale_payments are the record. This keeps a split sale out of
--      single-method reports instead of double counting it.
--    * A single-method PAID sale is unchanged: `p_payments` null keeps the
--      0034 path, including historical BANK sales, which stay readable and
--      remain valid.
--
-- 6. RE-APPLYING 0015's TIMEOUTS (invisible, but load-bearing)
--    0015's statement/lock/idle timeouts were attached to the EIGHT-argument
--    signature. 0035's nine-argument overload and this migration's DROP+CREATE
--    both produce a fresh function object with default settings, so the guards
--    are re-applied explicitly to the nine-argument signature at the end of
--    this file. Without them the row-locked body below has no server-side
--    bound and a hung request can wedge a shop's writes. See section C.
--
-- Append-only: never edits a released migration. Idempotent.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. sale_payments: shop isolation (0035 omitted RLS entirely)
-- ---------------------------------------------------------------------------
alter table public.sale_payments enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
     where policyname = 'sale_payments_all_own_shop'
       and tablename = 'sale_payments'
  ) then
    create policy sale_payments_all_own_shop on public.sale_payments
      for all
      using (
        exists (
          select 1
            from public.sales s
           where s.id = sale_payments.sale_id
             and public.is_shop_member(s.shop_id)
        )
      )
      with check (
        exists (
          select 1
            from public.sales s
           where s.id = sale_payments.sale_id
             and public.is_shop_member(s.shop_id)
        )
      );
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- B. One create_sale_atomic: 0034's verified body + split payments
-- ---------------------------------------------------------------------------
-- Drop both overloads so exactly one candidate remains for PostgREST.
drop function if exists public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb
);
drop function if exists public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
);

create function public.create_sale_atomic(
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

    -- Stock deduction only for tracked units (stock_unit != 'NONE')
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

-- ---------------------------------------------------------------------------
-- C. Re-apply 0015's per-function guards to the 9-argument signature
-- ---------------------------------------------------------------------------
-- 0015 attached statement/lock/idle timeouts to the EIGHT-argument
-- create_sale_atomic, which is where the row-lock wedge was first observed. Two
-- later events silently dropped them from the signature actually being called:
--
--   * 0035 created the nine-argument overload with CREATE OR REPLACE. That is a
--     NEW function object, so it started from default settings -- proconfig is
--     per-signature and is not inherited from the 8-arg version.
--   * This migration ends with DROP + CREATE (required, to collapse the two
--     overloads into one). DROP discards proconfig outright, so recreating
--     without these statements leaves the function with no server-side bound.
--
-- That matters because the body below holds FOR UPDATE row locks on
-- sale_sequences, products and product_variants for the whole transaction
-- (see the receipt allocator and the per-line stock lock). A client request
-- that hangs holds those locks, and every later write for that shop then queues
-- on them indefinitely -- a queue that never drains, not a deadlock, so
-- Postgres will not break it for us. The client-side timeout in
-- lib/core/network/rpc_timeout.dart does NOT cancel the underlying HTTP socket,
-- which is exactly why 0015 added these server-side settings in the first place.
--
-- Values are unchanged from 0015: statement 20s > lock 10s (a healthy call
-- finishes in well under a second). PostgreSQL permits only one SET clause per
-- ALTER FUNCTION, so each is applied as its own statement. The 8-argument
-- signature is intentionally left unconfigured -- it no longer exists after
-- the drops above, and nothing calls it.
-- ---------------------------------------------------------------------------
alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb)
  set statement_timeout = '20s';

alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb)
  set lock_timeout = '10s';

alter function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb)
  set idle_in_transaction_session_timeout = '30s';

grant execute on function public.create_sale_atomic(
  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb
) to authenticated;
