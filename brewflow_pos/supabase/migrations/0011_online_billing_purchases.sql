-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0011: Online-Only Billing & Purchases Atomic RPCs
--
-- Goal: make checkout / void / purchase receive cloud-authoritative while
-- keeping local Drift as cache. Adds server-side sequences, stock_movements
-- mirror, and SECURITY DEFINER RPCs that enforce:
--   shop isolation via is_shop_member(shop_id)
--   negative-stock prevention via FOR UPDATE locks + conditional deduction
--   gapless receipt/purchase numbers via per-shop counters (no max()+1)
--   atomic sale+items+moves+receipt and purchase+items+moves+number
--
-- Preservation: existing RLS/is_shop_member untouched, no service-role exposure.
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- A. Server sequences (gapless, per-shop, row-locked)
-- ---------------------------------------------------------------------------
create table if not exists public.sale_sequences (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  next_value integer not null default 0 check (next_value >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchase_sequences (
  shop_id uuid primary key references public.shops(id) on delete cascade,
  next_value integer not null default 0 check (next_value >= 0),
  updated_at timestamptz not null default now()
);

-- RLS on sequences: owner via is_shop_member, touched only by RPC (SECURITY DEFINER bypasses)
alter table public.sale_sequences enable row level security;
alter table public.purchase_sequences enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname='sale_sequences_all_own_shop' and tablename='sale_sequences') then
    create policy sale_sequences_all_own_shop on public.sale_sequences
      for all using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));
  end if;
  if not exists (select 1 from pg_policies where policyname='purchase_sequences_all_own_shop' and tablename='purchase_sequences') then
    create policy purchase_sequences_all_own_shop on public.purchase_sequences
      for all using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));
  end if;
end $$;

create or replace function public.touch_sequence_updated_at() returns trigger
language plpgsql as $$
begin new.updated_at := now(); return new; end; $$;

drop trigger if exists trg_sale_sequences_touch on public.sale_sequences;
create trigger trg_sale_sequences_touch before update on public.sale_sequences
  for each row execute function public.touch_sequence_updated_at();

drop trigger if exists trg_purchase_sequences_touch on public.purchase_sequences;
create trigger trg_purchase_sequences_touch before update on public.purchase_sequences
  for each row execute function public.touch_sequence_updated_at();

-- ---------------------------------------------------------------------------
-- B. Server stock_movements mirror (audit log)
-- ---------------------------------------------------------------------------
create table if not exists public.stock_movements (
  id uuid primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  product_id uuid not null,
  variant_id uuid,
  movement_type text not null check (movement_type in ('OPENING','SALE','PURCHASE','ADJUSTMENT_IN','ADJUSTMENT_OUT')),
  quantity integer not null,
  stock_before integer not null check (stock_before >= 0),
  stock_after integer not null check (stock_after >= 0),
  reason text,
  note text,
  reference_type text,
  reference_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.stock_movements enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname='stock_movements_all_own_shop' and tablename='stock_movements') then
    create policy stock_movements_all_own_shop on public.stock_movements
      for all using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));
  end if;
end $$;

create index if not exists idx_stock_movements_pull on public.stock_movements (shop_id, updated_at);
create index if not exists idx_stock_movements_product on public.stock_movements (product_id);
create index if not exists idx_stock_movements_reference on public.stock_movements (reference_id);

drop trigger if exists trg_stock_movements_touch on public.stock_movements;
create trigger trg_stock_movements_touch before update on public.stock_movements
  for each row execute function public.touch_row_updated_at();

-- Backfill sale sequences from existing sales (preserve history)
insert into public.sale_sequences (shop_id, next_value)
select shop_id, coalesce(max(cast(substring(receipt_number from 4) as integer)), 0)
from public.sales where receipt_number ~ '^BF-[0-9]+$' group by shop_id
on conflict (shop_id) do update set next_value = greatest(sale_sequences.next_value, excluded.next_value);

-- ---------------------------------------------------------------------------
-- C. Helper: next receipt / purchase numbers (gapless, locked)
-- ---------------------------------------------------------------------------
create or replace function public.next_receipt_number(p_shop_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v_next int;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  -- Upsert then locked increment — concurrent callers block on row lock, no gaps on rollback
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  -- FOR UPDATE locks the row for this transaction
  select next_value into v_next from public.sale_sequences where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_next + 1 where shop_id = p_shop_id returning next_value into v_next;
  return 'BF-' || lpad(v_next::text, 6, '0');
end; $$;

create or replace function public.next_purchase_number(p_shop_id uuid)
returns text
language plpgsql security definer set search_path = public as $$
declare v_next int;
begin
  if not public.is_shop_member(p_shop_id) then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;
  insert into public.purchase_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  select next_value into v_next from public.purchase_sequences where shop_id = p_shop_id for update;
  update public.purchase_sequences set next_value = v_next + 1 where shop_id = p_shop_id returning next_value into v_next;
  return 'PUR-' || lpad(v_next::text, 6, '0');
end; $$;

-- ---------------------------------------------------------------------------
-- D. RPC: create_sale_atomic
-- ---------------------------------------------------------------------------
-- p_lines: jsonb array of objects:
--   { product_id uuid, variant_id uuid|null, product_name text, variant_name text|null,
--     sku text|null, unit_price_paise int, quantity int, line_total_paise int,
--     offer_discount_paise int, applied_offer_id uuid|null, applied_offer_name text|null, applied_offer_type text|null }
create or replace function public.create_sale_atomic(
  p_shop_id uuid,
  p_customer_id uuid,
  p_subtotal_paise integer,
  p_total_paise integer,
  p_offer_discount_paise integer,
  p_payment_method text,
  p_payment_status text,
  p_lines jsonb
) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_sale_id uuid := gen_random_uuid();
  v_receipt text;
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
  if p_payment_status = 'PAID' and p_payment_method is null then
    raise exception 'INVALID_PAYMENT';
  end if;
  if p_payment_method is not null and p_payment_method not in ('CASH','UPI','BANK') then
    raise exception 'INVALID_PAYMENT';
  end if;
  if p_lines is null or jsonb_array_length(p_lines) = 0 then
    raise exception 'EMPTY_CART';
  end if;

  -- Validate customer when linked
  if p_customer_id is not null then
    select is_active into v_is_active from public.customers where id = p_customer_id and shop_id = p_shop_id;
    if not found then raise exception 'CUSTOMER_NOT_FOUND'; end if;
    if v_is_active = false then raise exception 'INACTIVE_CUSTOMER'; end if;
  end if;

  -- Allocate receipt atomically (row-locked sequence)
  insert into public.sale_sequences (shop_id, next_value) values (p_shop_id, 0)
    on conflict (shop_id) do nothing;
  select next_value into v_new_stock from public.sale_sequences where shop_id = p_shop_id for update;
  update public.sale_sequences set next_value = v_new_stock + 1 where shop_id = p_shop_id returning next_value into v_new_stock;
  v_receipt := 'BF-' || lpad(v_new_stock::text, 6, '0');

  -- Process each line: lock stock row, check, deduct, collect movement
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
    -- For NONE, skip stock check entirely
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

  -- Insert sale header
  insert into public.sales (id, shop_id, customer_id, receipt_number, subtotal_paise, total_paise, offer_discount_paise, payment_method, payment_status, client_created_at, created_at, updated_at, voided, voided_at)
  values (v_sale_id, p_shop_id, p_customer_id, v_receipt, p_subtotal_paise, p_total_paise, p_offer_discount_paise, p_payment_method, p_payment_status, v_now, v_now, v_now, false, null);

  -- Insert sale items + movements
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

  return jsonb_build_object('id', v_sale_id, 'receipt_number', v_receipt, 'created_at', v_now);
end; $$;

-- ---------------------------------------------------------------------------
-- E. RPC: void_sale_atomic
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
begin
  select shop_id, voided into v_shop_id, v_voided from public.sales where id = p_sale_id for update;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;
  if not public.is_shop_member(v_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_voided = true then raise exception 'ALREADY_VOIDED'; end if;

  -- Restore stock per item
  for v_item in select product_id, variant_id, quantity from public.sale_items where sale_id = p_sale_id
  loop
    select stock_unit into v_stock_unit from public.products where id = v_item.product_id;
    if v_stock_unit != 'NONE' then
      if v_item.variant_id is not null then
        update public.product_variants set stock_quantity = stock_quantity + v_item.quantity, updated_at = v_now where id = v_item.variant_id;
      else
        update public.products set stock_quantity = stock_quantity + v_item.quantity, updated_at = v_now where id = v_item.product_id;
      end if;
    end if;
  end loop;

  -- Reverse customer payments linked to this sale
  update public.customer_payments set reversed = true, reversed_at = v_now, updated_at = v_now
    where sale_id = p_sale_id and reversed = false;

  -- Mark sale voided
  update public.sales set voided = true, voided_at = v_now, updated_at = v_now where id = p_sale_id;

  return jsonb_build_object('id', p_sale_id, 'voided_at', v_now);
end; $$;

-- Ensure purchases/purchase_items tables exist before RPC that writes them
create table if not exists public.purchases (
  id uuid primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  supplier_id uuid references public.suppliers(id),
  purchase_number text not null,
  subtotal_paise integer not null check (subtotal_paise >= 0),
  total_paise integer not null check (total_paise >= 0),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ux_purchases_shop_number unique (shop_id, purchase_number)
);
create table if not exists public.purchase_items (
  id uuid primary key,
  shop_id uuid not null references public.shops(id) on delete cascade,
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null,
  variant_id uuid,
  product_name text not null,
  variant_name text,
  sku text,
  unit_cost_paise integer not null check (unit_cost_paise >= 0),
  quantity integer not null check (quantity > 0),
  line_total_paise integer not null check (line_total_paise >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where policyname='purchases_all_own_shop' and tablename='purchases') then
    create policy purchases_all_own_shop on public.purchases for all using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));
  end if;
  if not exists (select 1 from pg_policies where policyname='purchase_items_all_own_shop' and tablename='purchase_items') then
    create policy purchase_items_all_own_shop on public.purchase_items for all using (public.is_shop_member(shop_id)) with check (public.is_shop_member(shop_id));
  end if;
end $$;

create index if not exists idx_purchases_pull on public.purchases (shop_id, updated_at);
create index if not exists idx_purchase_items_pull on public.purchase_items (shop_id, updated_at);
create index if not exists idx_purchase_items_purchase on public.purchase_items (purchase_id);

-- Backfill purchase sequences from existing purchases (preserve history)
insert into public.purchase_sequences (shop_id, next_value)
select shop_id, coalesce(max(cast(substring(purchase_number from 5) as integer)), 0)
from public.purchases where purchase_number ~ '^PUR-[0-9]+$' group by shop_id
on conflict (shop_id) do update set next_value = greatest(purchase_sequences.next_value, excluded.next_value);

-- ---------------------------------------------------------------------------
-- F. RPC: receive_purchase_atomic
-- ---------------------------------------------------------------------------
-- p_lines: jsonb array of { product_id uuid, variant_id uuid|null, quantity int, unit_cost_paise int }
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
      update public.product_variants set stock_quantity = stock_quantity + v_quantity, updated_at = v_now where id = v_variant_id returning stock_quantity into v_stock_after;
      insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
        values (gen_random_uuid(), p_shop_id, v_product_id, v_variant_id, 'PURCHASE', v_quantity, v_stock_before, v_stock_after, 'PURCHASE', v_purchase_id, v_now, v_now);
    else
      select stock_quantity into v_stock_before from public.products where id = v_product_id;
      update public.products set stock_quantity = stock_quantity + v_quantity, updated_at = v_now where id = v_product_id returning stock_quantity into v_stock_after;
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

-- Stock movements RLS already handled above.

-- Grant execute to authenticated
grant execute on function public.create_sale_atomic(uuid, uuid, integer, integer, integer, text, text, jsonb) to authenticated;
grant execute on function public.void_sale_atomic(uuid) to authenticated;
grant execute on function public.receive_purchase_atomic(uuid, uuid, text, jsonb) to authenticated;
grant execute on function public.next_receipt_number(uuid) to authenticated;
grant execute on function public.next_purchase_number(uuid) to authenticated;

-- Ensure sales columns referenced by RPC exist (offer_discount_paise added in 0010)
alter table public.sales add column if not exists offer_discount_paise integer not null default 0;
alter table public.sales add column if not exists voided boolean not null default false;
alter table public.sales add column if not exists voided_at timestamptz;

-- sale_items offer columns
alter table public.sale_items add column if not exists offer_discount_paise integer not null default 0;
alter table public.sale_items add column if not exists applied_offer_id uuid;
alter table public.sale_items add column if not exists applied_offer_name text;
alter table public.sale_items add column if not exists applied_offer_type text;

-- sales client_created_at if missing
alter table public.sales add column if not exists client_created_at timestamptz not null default now();
alter table public.sale_items add column if not exists client_created_at timestamptz not null default now();
