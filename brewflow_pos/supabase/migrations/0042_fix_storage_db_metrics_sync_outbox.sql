-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0042: Remove sync_outbox from storage_db_metrics table list
--
-- The storage_db_metrics function referenced public.sync_outbox, which does
-- not exist in the Supabase/Postgres schema. sync_outbox is a local-only
-- Drift/SQLite table that never gets synced to the cloud.
--
-- This migration removes 'sync_outbox' from the v_tables array in the
-- function body. No logic, authorization, return shape, or cleanup behavior
-- is changed.
--
-- Append-only: never edit released migrations. Apply with:
--   supabase db push
--   or: supabase db execute --file supabase/migrations/0042_fix_storage_db_metrics_sync_outbox.sql
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.storage_db_metrics(
  p_shop_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tables text[] := ARRAY[
    'sales', 'sale_items', 'sale_payments', 'products', 'product_variants',
    'customers', 'customer_payments', 'expenses', 'expense_payments',
    'purchases', 'purchase_items', 'stock_movements', 'staff_attendance',
    'staff_advances', 'staff_daily_salaries', 'staff_monthly_salaries',
    'daily_closings', 'offers', 'product_recipes', 'suppliers',
    'master_deletions'
  ];
  v_t text;
  v_bytes bigint;
  v_rows bigint;
  v_out jsonb := '[]'::jsonb;
  v_limit bigint;
BEGIN
  IF NOT public.owns_shop(p_shop_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT storage_limit_bytes INTO v_limit
    FROM public.shops WHERE id = p_shop_id;

  FOREACH v_t IN ARRAY v_tables LOOP
    EXECUTE format('SELECT pg_total_relation_size(%L)', 'public.' || v_t)
      INTO v_bytes;
    EXECUTE format('SELECT count(*) FROM public.%I', v_t) INTO v_rows;
    v_out := v_out || jsonb_build_object(
      'table', v_t, 'bytes', COALESCE(v_bytes, 0), 'rows', COALESCE(v_rows, 0));
  END LOOP;

  RETURN jsonb_build_object(
    'dbBytesTotal', (SELECT pg_database_size(current_database())),
    'tables', v_out,
    'storageLimitBytes', v_limit);
END; $$;
