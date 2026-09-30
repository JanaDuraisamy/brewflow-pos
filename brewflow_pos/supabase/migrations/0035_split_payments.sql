-- Split payment support: sale_payments table + RPC extension

create table if not exists public.sale_payments (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references public.sales(id) on delete cascade,
  payment_method text not null check (payment_method in ('CASH', 'UPI')),
  amount_paise integer not null check (amount_paise > 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_sale_payments_sale on public.sale_payments(sale_id);

-- Extend create_sale_atomic to accept split payments
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
language plpgsql
security definer
as $$
declare
  v_sale_id uuid;
  v_receipt_number text;
  v_line record;
  v_payment record;
  v_payment_sum integer;
begin
  if p_payment_status not in ('PAID', 'NOT_PAID') then
    raise exception 'INVALID_PAYMENT_STATUS';
  end if;
  if p_payment_status = 'NOT_PAID' and p_customer_id is null then
    raise exception 'MISSING_CUSTOMER';
  end if;
  if p_payment_status = 'PAID' and p_payment_method is null and p_payments is null then
    raise exception 'INVALID_PAYMENT';
  end if;
  if p_payment_method is not null and p_payment_method not in ('CASH', 'UPI', 'BANK') then
    raise exception 'INVALID_PAYMENT';
  end if;

  -- Validate split payments sum to total
  if p_payments is not null then
    select coalesce(sum((p->>'amount_paise')::integer), 0) into v_payment_sum
    from jsonb_array_elements(p_payments) as p;
    if v_payment_sum != p_total_paise then
      raise exception 'SPLIT_PAYMENT_MISMATCH';
    end if;
  end if;

  -- Allocate receipt number
  insert into public.sale_sequences (id, shop_id, next_value)
  values ('receipt', p_shop_id, 0)
  on conflict (id, shop_id) do nothing;

  select 'BF-' || lpad((next_value + 1)::text, 6, '0')
  into v_receipt_number
  from public.sale_sequences
  where id = 'receipt' and shop_id = p_shop_id
  for update;

  update public.sale_sequences
  set next_value = next_value + 1
  where id = 'receipt' and shop_id = p_shop_id;

  -- Insert sale
  insert into public.sales (
    id, shop_id, customer_id, receipt_number,
    subtotal_paise, total_paise, offer_discount_paise,
    payment_method, payment_status, created_at, updated_at
  ) values (
    gen_random_uuid(), p_shop_id, p_customer_id, v_receipt_number,
    p_subtotal_paise, p_total_paise, p_offer_discount_paise,
    case when p_payments is not null then null else p_payment_method end,
    p_payment_status, now(), now()
  ) returning id into v_sale_id;

  -- Insert sale items
  for v_line in select * from jsonb_to_recordset(p_lines) as x(
    product_id uuid, variant_id uuid, product_name text,
    variant_name text, sku text, unit_price_paise integer,
    quantity integer, line_total_paise integer,
    offer_discount_paise integer, applied_offer_id uuid,
    applied_offer_name text, applied_offer_type text
  )
  loop
    insert into public.sale_items (
      id, shop_id, sale_id, product_id, variant_id,
      product_name, variant_name, sku, unit_price_paise,
      quantity, line_total_paise, offer_discount_paise,
      applied_offer_id, applied_offer_name, applied_offer_type
    ) values (
      gen_random_uuid(), p_shop_id, v_sale_id, v_line.product_id, v_line.variant_id,
      v_line.product_name, v_line.variant_name, v_line.sku, v_line.unit_price_paise,
      v_line.quantity, v_line.line_total_paise, v_line.offer_discount_paise,
      v_line.applied_offer_id, v_line.applied_offer_name, v_line.applied_offer_type
    );
  end loop;

  -- Insert split payment legs
  if p_payments is not null then
    for v_payment in select * from jsonb_to_recordset(p_payments) as p(
      payment_method text, amount_paise integer
    )
    loop
      insert into public.sale_payments (sale_id, payment_method, amount_paise)
      values (v_sale_id, v_payment.payment_method, v_payment.amount_paise);
    end loop;
  end if;

  return jsonb_build_object(
    'id', v_sale_id,
    'receipt_number', v_receipt_number,
    'created_at', now()
  );
end;
$$;
