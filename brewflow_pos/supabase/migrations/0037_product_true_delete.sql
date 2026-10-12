-- ---------------------------------------------------------------------------
-- 0036 -> 0037: product true-delete
--
-- `product_variants.product_id` carried a plain `references public.products
-- (id)` — i.e. `ON DELETE NO ACTION`. That single constraint is why a product
-- with any variant could never really be deleted: the app had to fake it with a
-- hidden/deactivated master row, which left a zombie product on every device
-- (invisible only because of the is_active filter) while it still held its
-- shop-unique SKU and blocked re-creating the same product.
--
-- The six historical ledger columns — `sale_items.product_id` /
-- `.variant_id`, `purchase_items.product_id` / `.variant_id` and
-- `stock_movements.product_id` / `.variant_id` — already carry no foreign key
-- (verified: `0003_master_data_sync.sql` is the only place that ever
-- referenced `products`, and it did so for `product_variants` alone). They are
-- deliberately left alone here: nothing is nulled and no historical row is
-- touched, so the ledger keeps its attribution exactly as local schema v31 does.
--
-- This mirrors the customer fix in 0030, with the operational half added:
-- `product_variants` is product *definition*, not history, so a deleted product
-- must take its variants with it rather than orphan them. `ON DELETE CASCADE`
-- does that.
--
-- RLS, policies, grants and indexes are untouched: this only retargets one
-- constraint's delete action, so it cannot widen who can read or write
-- anything. Deleting a row is still authorised by the existing `products` RLS.
-- ---------------------------------------------------------------------------

do $$
declare
  con record;
begin
  -- Drop whatever delete action the variant FK currently has (NO ACTION on a
  -- fresh install, possibly already CASCADE if this is replayed).
  for con in
    select conname
    from pg_constraint
    where conrelid = 'public.product_variants'::regclass
      and contype = 'f'
      and confrelid = 'public.products'::regclass
  loop
    execute format(
      'alter table public.product_variants drop constraint %I', con.conname
    );
  end loop;

  execute 'alter table public.product_variants
    add constraint product_variants_product_id_fkey
    foreign key (product_id) references public.products (id)
    on delete cascade';
end
$$;

comment on column public.product_variants.product_id is
  'Owning product. ON DELETE CASCADE (0037): a variant is product definition '
  'rather than history, so deleting the product removes its variants with it '
  'instead of raising a foreign-key violation or orphaning them.';

comment on column public.sale_items.product_id is
  'Product at the time of sale. Not a foreign key: a product with history must '
  'still be deletable, and the id is preserved so the ledger keeps its '
  'attribution. product_name / variant_name on this row are the receipt '
  'snapshot and are what the UI renders.';
