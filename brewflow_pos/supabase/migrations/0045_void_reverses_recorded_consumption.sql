-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0045: void reverses exactly what the sale consumed
--
-- Problem (confirmed against 0044): `void_sale_atomic` restored stock from the
-- CURRENT `product_recipes` mapping (`0044:390-398`), and even multiplied
-- wrong (`0044:397` restored the LINE quantity, not recipe quantity x line
-- quantity). Recipe edits, clears and remaps between a sale and its void
-- silently corrupted stock. `sale_items` records no consumed-ingredient
-- snapshot, and recipe rows do not survive deletion, so the recorded
-- consumption was never recoverable from the server alone.
--
-- What changes (append-only; 0044 is untouched):
--   1. `sale_items.consumed` — a nullable per-line JSON snapshot of what the
--      line consumed at sale time: `[{"ip", "iv"?, "q"}]`. A non-null empty
--      array `[]` = the line consumed no ingredients (its own stock may still
--      be tracked). NULL = unknown/legacy (predates snapshots). Written by the
--      client during create_sale_atomic and stored locally by the mirror.
--   2. `stock_movements.movement_type` CHECK gains 'VOID' — the void's audit
--      rows, one positive delta per restored stock entity per sale.
--   3. `void_sale_atomic` — same 1-arg signature (0015's statement/lock
--      timeouts and the GRANT are RE-ISSUED below, because CREATE OR REPLACE
--      resets proconfig), new restore rule:
--        a. every line carries a snapshot (jsonb array, possibly empty) ->
--           restore exactly it, aggregated per stock entity for the whole
--           sale. A non-empty entry restores its ingredient (q x line qty);
--           `[]` restores the line's OWN stock when `products.stock_unit`
--           <> 'NONE' (never from current recipes);
--        b. every line is NULL (legacy) but the sale has recorded SALE
--           movements -> reverse those, aggregated per stock entity, ONCE for
--           the sale (never inside the per-line loop);
--        c. lines are mixed snapshot/NULL, or a legacy sale has a tracked line
--           with no recorded movement -> raise, so the whole transaction rolls
--           back before anything is mutated. The caller surfaces
--           VoidHistoryPrunedFailure and offers the no-restore path.
--      Restores use a deterministic (product_id, variant_id) lock order, skip
--      deleted stock rows (no phantom credit), and run in the SAME transaction
--      as the sale status and payment reversal (the `voided` flag gates the
--      whole thing, so nothing is restored twice).
--   4. `void_sale_without_restore_atomic` — the distinct no-restore contract
--      (decision: server + repository only, no UI). Same guards; reverses
--      payments and voids the sale, and NEVER touches stock or movements.
--
-- No migration is applied here; this file is reviewed for a later staged
-- (non-production) Supabase deployment.
-- ---------------------------------------------------------------------------

-- 1. Consumption snapshot per line. Purely additive: every existing row reads
--    back NULL, which is exactly "unmapped or predates snapshots" for the
--    restore rule above.
ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS consumed jsonb NULL;

-- 2. VOID audit movement type. Postgres cannot ALTER a CHECK constraint, so
--    the constraint is dropped and re-created with the same definition plus
--    'VOID' (0011:66 defined the original list).
ALTER TABLE public.stock_movements
  DROP CONSTRAINT IF EXISTS stock_movements_movement_type_check;

ALTER TABLE public.stock_movements
  ADD CONSTRAINT stock_movements_movement_type_check
  CHECK (movement_type IN ('OPENING','SALE','PURCHASE','ADJUSTMENT_IN','ADJUSTMENT_OUT','VOID'));

-- 3. Recipe-aware, movement-anchored void (same 1-arg signature as 0011/0044).
create or replace function public.void_sale_atomic(p_sale_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_shop_id uuid;
  v_voided boolean;
  v_now timestamptz := now();
  v_n_snapshot bigint;
  v_n_legacy bigint;
  v_has_movements boolean := false;
  v_row record;
  v_after record;
  v_restore_rows jsonb := '[]'::jsonb;
begin
  select shop_id, voided into v_shop_id, v_voided
    from public.sales where id = p_sale_id for update;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;
  if not public.is_shop_member(v_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_voided = true then raise exception 'ALREADY_VOIDED'; end if;

  -- Classify the lines and prove restorability BEFORE any mutation. The sale
  -- row is already locked FOR UPDATE, so a concurrent void either sees
  -- voided=true here or waits and then raises ALREADY_VOIDED.
  select count(*) filter (where consumed is not null),
         count(*) filter (where consumed is null)
    into v_n_snapshot, v_n_legacy
    from public.sale_items where sale_id = p_sale_id;

  if v_n_snapshot > 0 and v_n_legacy > 0 then
    -- A sale is written by one client in one transaction, so its lines are
    -- all snapshot or all NULL. Mixed means the data is not reconcilable
    -- without double counting the recorded movements: fail safe.
    raise exception 'VOID_SNAPSHOT_MIXED';
  end if;

  if v_n_legacy > 0 then
    select exists(
      select 1 from public.stock_movements sm
       where sm.reference_type = 'SALE'
         and sm.reference_id = p_sale_id
         and sm.movement_type = 'SALE'
    ) into v_has_movements;

    if not v_has_movements then
      -- No snapshot AND no recorded movement. NONE lines provably consumed
      -- nothing; any tracked legacy line has an unprovable impact, so fail
      -- before mutating rather than fabricating from current recipes.
      if exists(
        select 1 from public.sale_items si
          join public.products p on p.id = si.product_id
         where si.sale_id = p_sale_id and p.stock_unit <> 'NONE'
      ) then
        raise exception 'VOID_HISTORY_PRUNED';
      end if;
    end if;
  end if;

  if v_n_legacy > 0 and v_has_movements then
    -- (b) Legacy sale with recorded movements: reverse them once for the whole
    -- sale, aggregated per stock entity, in a fixed (product_id, variant_id)
    -- order. Only SALE movements ever reference a sale (purchases/adjustments
    -- use other references), so this filter is exact.
    for v_row in
      select sm.product_id, sm.variant_id, -sum(sm.quantity) as total
        from public.stock_movements sm
       where sm.reference_type = 'SALE'
         and sm.reference_id = p_sale_id
         and sm.movement_type = 'SALE'
       group by sm.product_id, sm.variant_id
       order by sm.product_id, sm.variant_id
    loop
      if v_row.total is null or v_row.total <= 0 then
        continue;
      end if;
      if v_row.variant_id is not null then
        -- A deleted stock row has nothing to credit back; skip rather than
        -- inventing one. The dedicated v_after record holds the UPDATE result
        -- (v_row is the loop cursor and is never overwritten).
        update public.product_variants set stock_quantity = stock_quantity + v_row.total
          where id = v_row.variant_id and shop_id = v_shop_id
          returning stock_quantity into v_after;
        if not found then continue; end if;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
          values (gen_random_uuid(), v_shop_id, v_row.product_id, v_row.variant_id, 'VOID', v_row.total, v_after.stock_quantity - v_row.total, v_after.stock_quantity, 'SALE', p_sale_id, v_now, v_now);
        v_restore_rows := v_restore_rows || jsonb_build_object(
          'product_id', v_row.product_id,
          'variant_id', v_row.variant_id,
          'quantity', v_row.total);
      else
        update public.products set stock_quantity = stock_quantity + v_row.total
          where id = v_row.product_id and shop_id = v_shop_id
          returning stock_quantity into v_after;
        if not found then continue; end if;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
          values (gen_random_uuid(), v_shop_id, v_row.product_id, null, 'VOID', v_row.total, v_after.stock_quantity - v_row.total, v_after.stock_quantity, 'SALE', p_sale_id, v_now, v_now);
        v_restore_rows := v_restore_rows || jsonb_build_object(
          'product_id', v_row.product_id,
          'quantity', v_row.total);
      end if;
    end loop;
  else
    -- (a) Snapshot path. Build one contribution set for the whole sale:
    -- mapped ingredient entries (q x line qty) plus the own-stock of tracked
    -- lines whose snapshot is the empty array, then aggregate per stock entity
    -- and process in the same fixed order. Never consults product_recipes.
    for v_row in
      with contribution as (
        select (e.value->>'ip')::uuid as product_id,
               nullif(e.value->>'iv', '')::uuid as variant_id,
               ((e.value->>'q')::int * si.quantity) as qty
          from public.sale_items si
          cross join lateral jsonb_array_elements(si.consumed) e
         where si.sale_id = p_sale_id
           and si.consumed is not null
           and jsonb_array_length(si.consumed) > 0
        union all
        select si.product_id, si.variant_id, si.quantity
          from public.sale_items si
          join public.products p on p.id = si.product_id
         where si.sale_id = p_sale_id
           and si.consumed = '[]'::jsonb
           and p.stock_unit <> 'NONE'
      )
      select product_id, variant_id, sum(qty) as total
        from contribution
       group by product_id, variant_id
       order by product_id, variant_id
    loop
      if v_row.total is null or v_row.total <= 0 then
        continue;
      end if;
      if v_row.variant_id is not null then
        update public.product_variants set stock_quantity = stock_quantity + v_row.total
          where id = v_row.variant_id and shop_id = v_shop_id
          returning stock_quantity into v_after;
        if not found then continue; end if;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
          values (gen_random_uuid(), v_shop_id, v_row.product_id, v_row.variant_id, 'VOID', v_row.total, v_after.stock_quantity - v_row.total, v_after.stock_quantity, 'SALE', p_sale_id, v_now, v_now);
        v_restore_rows := v_restore_rows || jsonb_build_object(
          'product_id', v_row.product_id,
          'variant_id', v_row.variant_id,
          'quantity', v_row.total);
      else
        update public.products set stock_quantity = stock_quantity + v_row.total
          where id = v_row.product_id and shop_id = v_shop_id
          returning stock_quantity into v_after;
        if not found then continue; end if;
        insert into public.stock_movements (id, shop_id, product_id, variant_id, movement_type, quantity, stock_before, stock_after, reference_type, reference_id, created_at, updated_at)
          values (gen_random_uuid(), v_shop_id, v_row.product_id, null, 'VOID', v_row.total, v_after.stock_quantity - v_row.total, v_after.stock_quantity, 'SALE', p_sale_id, v_now, v_now);
        v_restore_rows := v_restore_rows || jsonb_build_object(
          'product_id', v_row.product_id,
          'quantity', v_row.total);
      end if;
    end loop;
  end if;

  -- Reverse customer payments linked to this sale (same transaction).
  update public.customer_payments set reversed = true, reversed_at = v_now, updated_at = v_now
    where sale_id = p_sale_id and reversed = false;

  -- Mark sale voided.
  update public.sales set voided = true, voided_at = v_now, updated_at = v_now where id = p_sale_id;

  return jsonb_build_object('id', p_sale_id, 'voided_at', v_now, 'restored', (jsonb_array_length(v_restore_rows) > 0), 'restored_rows', v_restore_rows);
end; $$;

-- 4. No-restore void (decision: server + repository contract only, no UI).
--    Same guards as void_sale_atomic; reverses payments and voids the sale,
--    and NEVER touches products/product_variants/stock_movements. It exists
--    solely for sales whose consumed history is unrecoverable
--    (VOID_HISTORY_PRUNED) that the owner explicitly chooses to void without a
--    stock reversal, so it is a DISTINCT server contract rather than a flag on
--    the restoring function.
create or replace function public.void_sale_without_restore_atomic(p_sale_id uuid)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_shop_id uuid;
  v_voided boolean;
  v_now timestamptz := now();
begin
  select shop_id, voided into v_shop_id, v_voided
    from public.sales where id = p_sale_id for update;
  if not found then raise exception 'SALE_NOT_FOUND'; end if;
  if not public.is_shop_member(v_shop_id) then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v_voided = true then raise exception 'ALREADY_VOIDED'; end if;

  update public.customer_payments set reversed = true, reversed_at = v_now, updated_at = v_now
    where sale_id = p_sale_id and reversed = false;

  update public.sales set voided = true, voided_at = v_now, updated_at = v_now where id = p_sale_id;

  return jsonb_build_object('id', p_sale_id, 'voided_at', v_now, 'restored', false, 'restored_rows', '[]'::jsonb);
end; $$;

-- The void signature is unchanged (1 arg), so 0015's per-function guards would
-- normally carry over untouched — but CREATE OR REPLACE rebuilds the pg_proc
-- row and DROPS its proconfig, so the guards are re-issued here (copied
-- verbatim from 0015:38-45; PostgreSQL allows one SET per ALTER FUNCTION).
grant execute on function public.void_sale_atomic(uuid) to authenticated;

alter function public.void_sale_atomic(uuid)
  set statement_timeout = '20s';

alter function public.void_sale_atomic(uuid)
  set lock_timeout = '10s';

alter function public.void_sale_atomic(uuid)
  set idle_in_transaction_session_timeout = '30s';

grant execute on function public.void_sale_without_restore_atomic(uuid) to authenticated;

alter function public.void_sale_without_restore_atomic(uuid)
  set statement_timeout = '20s';

alter function public.void_sale_without_restore_atomic(uuid)
  set lock_timeout = '10s';

alter function public.void_sale_without_restore_atomic(uuid)
  set idle_in_transaction_session_timeout = '30s';
