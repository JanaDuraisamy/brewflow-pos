-- ---------------------------------------------------------------------------
-- 0029 -> 0030: customer true-delete
--
-- `sales.customer_id` and `customer_payments.customer_id` both carried
-- `ON DELETE RESTRICT`, so a customer with any billing history could never be
-- deleted. The app had to fake it with a hidden/deactivated master row.
--
-- Both foreign keys are dropped and the id is KEPT as a plain uuid column, so
-- the ledger keeps its attribution: a deleted customer simply leaves a
-- dangling `customer_id` that the UI renders defensively. Nothing is nulled
-- and no historical row is touched.
--
-- `customer_payments.sale_id` keeps its RESTRICT foreign key to `sales` — a
-- payment must never outlive the sale it was allocated to.
--
-- RLS, policies, grants and indexes are untouched: this only relaxes two
-- constraints, so it cannot widen who can read or write anything.
-- ---------------------------------------------------------------------------

do $$
declare
  con record;
begin
  -- sales.customer_id -> customers
  for con in
    select conname
    from pg_constraint
    where conrelid = 'public.sales'::regclass
      and contype = 'f'
      and confrelid = 'public.customers'::regclass
  loop
    execute format(
      'alter table public.sales drop constraint %I', con.conname
    );
  end loop;

  -- customer_payments.customer_id -> customers
  for con in
    select conname
    from pg_constraint
    where conrelid = 'public.customer_payments'::regclass
      and contype = 'f'
      and confrelid = 'public.customers'::regclass
  loop
    execute format(
      'alter table public.customer_payments drop constraint %I', con.conname
    );
  end loop;
end
$$;

comment on column public.sales.customer_id is
  'Owning customer for customer-linked sales; NULL for walk-ins. Not a foreign '
  'key (0030): a customer with history must still be deletable, and the id is '
  'preserved so the ledger keeps its attribution.';

comment on column public.customer_payments.customer_id is
  'Owning customer. Not a foreign key (0030) for the same reason as '
  'sales.customer_id. sale_id keeps its foreign key to sales.';
