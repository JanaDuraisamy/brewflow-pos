-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0040: Monthly storage ledger + report confirmations +
-- month-cleanup markers
--
-- Owner storage dashboard + month-wise cleanup support tables. All three are
-- shop-scoped with the standard owner policy (is_shop_member(shop_id)) and
-- follow the append-only convention: never edit released migrations.
--
-- 1. storage_monthly_snapshots — server-side monthly usage ledger. Written by
--    the `storage-cleanup` Edge Function (service role) when it computes a
--    month's stats, so history survives even if the device that scanned is
--    gone. Counts are exact row counts; byte figures are LOGICAL ESTIMATES
--    (see the function), never physical attribution — Postgres cannot
--    attribute shared-table physical bytes to a calendar month.
-- 2. monthly_report_confirmations — owner-recorded "report generated/saved
--    for this month" markers. Written by owner devices through the normal
--    authenticated sync path (outbox -> engine -> upsert) AND readable by the
--    Edge Function, which refuses month-cleanup for a month with no
--    confirmation row. UNIQUE (shop_id, month): one marker per month.
-- 3. month_cleanup_markers — one row per completed month cleanup, written by
--    the Edge Function inside the SAME transaction as the deletes. Peers pull
--    markers through the normal sync pull and delete their local mirrors, so
--    every device converges without per-row tombstone floods. Markers are
--    never deleted (tiny ledger rows).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.storage_monthly_snapshots (
  id                    uuid PRIMARY KEY,
  shop_id               uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  month                 date NOT NULL,
  counts                jsonb NOT NULL DEFAULT '{}'::jsonb,
  logical_bytes_est     bigint NOT NULL DEFAULT 0,
  db_bytes_total        bigint NULL,
  client_created_at     timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (shop_id, month)
);

CREATE TABLE IF NOT EXISTS public.monthly_report_confirmations (
  id                    uuid PRIMARY KEY,
  shop_id               uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  month                 date NOT NULL,
  confirmed_at          timestamptz NOT NULL DEFAULT now(),
  confirmed_by          text NULL,
  source                text NOT NULL DEFAULT 'management-report',
  client_created_at     timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (shop_id, month)
);

CREATE TABLE IF NOT EXISTS public.month_cleanup_markers (
  id                    uuid PRIMARY KEY,
  shop_id               uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  month                 date NOT NULL,
  tables                jsonb NOT NULL DEFAULT '{}'::jsonb,
  deleted_counts        jsonb NOT NULL DEFAULT '{}'::jsonb,
  completed_at          timestamptz NOT NULL DEFAULT now(),
  client_created_at     timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (shop_id, month)
);
ALTER TABLE public.storage_monthly_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_report_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.month_cleanup_markers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS storage_monthly_snapshots_all_own_shop
  ON public.storage_monthly_snapshots;
CREATE POLICY storage_monthly_snapshots_all_own_shop
  ON public.storage_monthly_snapshots
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

DROP POLICY IF EXISTS monthly_report_confirmations_all_own_shop
  ON public.monthly_report_confirmations;
CREATE POLICY monthly_report_confirmations_all_own_shop
  ON public.monthly_report_confirmations
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

DROP POLICY IF EXISTS month_cleanup_markers_all_own_shop
  ON public.month_cleanup_markers;
CREATE POLICY month_cleanup_markers_all_own_shop
  ON public.month_cleanup_markers
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_storage_monthly_snapshots_pull
  ON public.storage_monthly_snapshots (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_monthly_report_confirmations_pull
  ON public.monthly_report_confirmations (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_month_cleanup_markers_pull
  ON public.month_cleanup_markers (shop_id, updated_at);

DROP TRIGGER IF EXISTS trg_storage_monthly_snapshots_touch
  ON public.storage_monthly_snapshots;
CREATE TRIGGER trg_storage_monthly_snapshots_touch
  BEFORE UPDATE ON public.storage_monthly_snapshots
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();

DROP TRIGGER IF EXISTS trg_monthly_report_confirmations_touch
  ON public.monthly_report_confirmations;
CREATE TRIGGER trg_monthly_report_confirmations_touch
  BEFORE UPDATE ON public.monthly_report_confirmations
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();

DROP TRIGGER IF EXISTS trg_month_cleanup_markers_touch
  ON public.month_cleanup_markers;
CREATE TRIGGER trg_month_cleanup_markers_touch
  BEFORE UPDATE ON public.month_cleanup_markers
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();

DROP TRIGGER IF EXISTS trg_month_cleanup_markers_touch
  ON public.month_cleanup_markers;
CREATE TRIGGER trg_month_cleanup_markers_touch
  BEFORE UPDATE ON public.month_cleanup_markers
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();

-- ---------------------------------------------------------------------------
-- month_preview_counts: read-only per-month counts for the cleanup preview.
--
-- Same WHERE clauses as month_cleanup_atomic below, so the preview the owner
-- confirms is exactly what the cleanup deletes. Orphan images are objects
-- created in the month that match NO live product cloud_image_path.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.month_preview_counts(
  p_shop_id uuid,
  p_month date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_prefix text;
  v_result jsonb;
BEGIN
  IF NOT public.owns_shop(p_shop_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  v_prefix := p_shop_id::text || '/products/';

  SELECT jsonb_build_object(
    'sales', (SELECT count(*) FROM public.sales
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'saleItems', (SELECT count(*) FROM public.sale_items si
      WHERE si.shop_id = p_shop_id AND si.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= v_start AND s.created_at < v_end)),
    'salePayments', (SELECT count(*) FROM public.sale_payments sp
      WHERE sp.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= v_start AND s.created_at < v_end)),
    'customerPayments', (SELECT count(*) FROM public.customer_payments cp
      WHERE cp.shop_id = p_shop_id AND cp.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= v_start AND s.created_at < v_end)),
    'purchases', (SELECT count(*) FROM public.purchases
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'purchaseItems', (SELECT count(*) FROM public.purchase_items pi
      WHERE pi.shop_id = p_shop_id AND pi.purchase_id IN (
        SELECT p.id FROM public.purchases p
        WHERE p.shop_id = p_shop_id AND p.created_at >= v_start AND p.created_at < v_end)),
    'expenses', (SELECT count(*) FROM public.expenses
      WHERE shop_id = p_shop_id AND expense_date >= v_start AND expense_date < v_end),
    'stockMovements', (SELECT count(*) FROM public.stock_movements
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'dailyClosings', (SELECT count(*) FROM public.daily_closings
      WHERE shop_id = p_shop_id AND business_date >= v_start AND business_date < v_end),
    'staffAttendance', (SELECT count(*) FROM public.staff_attendance
      WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end),
    'staffAdvances', (SELECT count(*) FROM public.staff_advances
      WHERE shop_id = p_shop_id AND advance_date >= v_start AND advance_date < v_end),
    'staffDailySalaries', (SELECT count(*) FROM public.staff_daily_salaries
      WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end),
    'staffMonthlySalaries', (SELECT count(*) FROM public.staff_monthly_salaries
      WHERE shop_id = p_shop_id AND month_date >= v_start AND month_date < v_end),
    'orphanImages', (SELECT count(*) FROM storage.objects o
      WHERE o.bucket_id = 'product-images' AND o.name LIKE v_prefix || '%'
        AND o.created_at >= v_start AND o.created_at < v_end
        AND NOT EXISTS (SELECT 1 FROM public.products p
          WHERE p.shop_id = p_shop_id AND p.cloud_image_path = o.name)),
    'confirmed', (SELECT count(*) FROM public.monthly_report_confirmations
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end),
    'alreadyCleaned', (SELECT count(*) FROM public.month_cleanup_markers
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end)
  ) INTO v_result;
  RETURN v_result;
END; $$;

GRANT EXECUTE ON FUNCTION public.month_preview_counts(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- month_cleanup_atomic: month-scoped HARD DELETE in dependency order.
--
-- Requires a monthly_report_confirmations row for (shop, month): destructive
-- cleanup only ever runs after the owner generated/saved the month's report.
-- Re-running a cleaned month returns zero counts (idempotent, retry-safe)
-- instead of deleting again. Writes the month_cleanup_markers row in the SAME
-- transaction, so peers pulling the marker converge by deleting their local
-- mirrors through the normal sync pull.
--
-- Out of scope by design (documented, never silently touched):
--   products/variants/categories/suppliers/customers/offers/recipes (master
--   data, no month key), expense_payments (payee-keyed, not month-scoped),
--   sync_outbox (durable queue — only the engine drains it), sequences and
--   device-local bookkeeping.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.month_cleanup_atomic(
  p_shop_id uuid,
  p_month date,
  p_marker_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_counts jsonb;
  v_n bigint;
  v_deleted jsonb := '{}'::jsonb;
BEGIN
  IF NOT public.owns_shop(p_shop_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.monthly_report_confirmations
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end) THEN
    RAISE EXCEPTION 'NEEDS_REPORT';
  END IF;

  IF EXISTS (SELECT 1 FROM public.month_cleanup_markers
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end) THEN
    RETURN jsonb_build_object('alreadyCleaned', true, 'deleted', v_deleted);
  END IF;

  -- Children before parents (RESTRICT FKs), month window on the owning row.
  DELETE FROM public.sale_payments sp USING public.sales s
    WHERE sp.sale_id = s.id AND s.shop_id = p_shop_id
      AND s.created_at >= v_start AND s.created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('salePayments', v_n);

  DELETE FROM public.sale_items si USING public.sales s
    WHERE si.sale_id = s.id AND s.shop_id = p_shop_id
      AND s.created_at >= v_start AND s.created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('saleItems', v_n);

  DELETE FROM public.customer_payments
    WHERE shop_id = p_shop_id AND sale_id IN (
      SELECT s.id FROM public.sales s
      WHERE s.shop_id = p_shop_id AND s.created_at >= v_start AND s.created_at < v_end);
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('customerPayments', v_n);

  DELETE FROM public.sales
    WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('sales', v_n);

  DELETE FROM public.purchase_items pi USING public.purchases p
    WHERE pi.purchase_id = p.id AND p.shop_id = p_shop_id
      AND p.created_at >= v_start AND p.created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('purchaseItems', v_n);

  DELETE FROM public.purchases
    WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('purchases', v_n);

  DELETE FROM public.expenses
    WHERE shop_id = p_shop_id AND expense_date >= v_start AND expense_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('expenses', v_n);

  DELETE FROM public.stock_movements
    WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('stockMovements', v_n);

  DELETE FROM public.daily_closings
    WHERE shop_id = p_shop_id AND business_date >= v_start AND business_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('dailyClosings', v_n);

  DELETE FROM public.staff_attendance
    WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('staffAttendance', v_n);

  DELETE FROM public.staff_advances
    WHERE shop_id = p_shop_id AND advance_date >= v_start AND advance_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('staffAdvances', v_n);

  DELETE FROM public.staff_daily_salaries
    WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('staffDailySalaries', v_n);

  DELETE FROM public.staff_monthly_salaries
    WHERE shop_id = p_shop_id AND month_date >= v_start AND month_date < v_end;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_deleted := v_deleted || jsonb_build_object('staffMonthlySalaries', v_n);

  INSERT INTO public.month_cleanup_markers (
    id, shop_id, month, tables, deleted_counts,
    completed_at, client_created_at, created_at, updated_at
  ) VALUES (
    p_marker_id, p_shop_id, v_start,
    (SELECT COALESCE(jsonb_object_agg(key, TRUE), '{}'::jsonb)
       FROM jsonb_object_keys(v_deleted) AS key),
    v_deleted, now(), now(), now(), now()
  )
  ON CONFLICT (shop_id, month) DO NOTHING;

  RETURN jsonb_build_object('alreadyCleaned', false, 'deleted', v_deleted);
END; $$;

GRANT EXECUTE ON FUNCTION public.month_cleanup_atomic(uuid, date, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.month_preview_counts(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- storage_db_metrics: physical database size + per-table physical sizes.
--
-- These are DATABASE-wide figures: Postgres shares physical table/index
-- storage across shops, so per-table bytes can never be attributed to one
-- shop. The client labels them exactly that way and pairs them with the
-- shop's own logical counts. Read-only.
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
    'sync_outbox', 'master_deletions'
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

GRANT EXECUTE ON FUNCTION public.storage_db_metrics(uuid) TO authenticated;

-- ---------------------------------------------------------------------------
-- month_size_estimate: one month's logical stats + estimated logical bytes.
--
-- Counts are EXACT row counts in the month window. Byte figures are honest
-- estimates: per-table average row width (physical table size / total rows,
-- database-wide) multiplied by the month's row count. Postgres cannot
-- attribute shared-table physical bytes to a calendar month, so the client
-- must label these logical/estimated — never exact physical usage.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.month_size_estimate(
  p_shop_id uuid,
  p_month date
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start date := date_trunc('month', p_month)::date;
  v_end date := (date_trunc('month', p_month) + interval '1 month')::date;
  v_counts jsonb;
  v_avg jsonb := '{}'::jsonb;
  v_logical bigint := 0;
  v_key text;
  v_n bigint;
  v_avg_n bigint;
BEGIN
  IF NOT public.owns_shop(p_shop_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'sales', (SELECT count(*) FROM public.sales
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'saleItems', (SELECT count(*) FROM public.sale_items si
      WHERE si.shop_id = p_shop_id AND si.sale_id IN (
        SELECT s.id FROM public.sales s
        WHERE s.shop_id = p_shop_id AND s.created_at >= v_start AND s.created_at < v_end)),
    'purchases', (SELECT count(*) FROM public.purchases
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'purchaseItems', (SELECT count(*) FROM public.purchase_items pi
      WHERE pi.shop_id = p_shop_id AND pi.purchase_id IN (
        SELECT p.id FROM public.purchases p
        WHERE p.shop_id = p_shop_id AND p.created_at >= v_start AND p.created_at < v_end)),
    'expenses', (SELECT count(*) FROM public.expenses
      WHERE shop_id = p_shop_id AND expense_date >= v_start AND expense_date < v_end),
    'stockMovements', (SELECT count(*) FROM public.stock_movements
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'dailyClosings', (SELECT count(*) FROM public.daily_closings
      WHERE shop_id = p_shop_id AND business_date >= v_start AND business_date < v_end),
    'staffAttendance', (SELECT count(*) FROM public.staff_attendance
      WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end),
    'customers', (SELECT count(*) FROM public.customers
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end),
    'products', (SELECT count(*) FROM public.products
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end)
  ) INTO v_counts;

  FOR v_key IN SELECT * FROM jsonb_object_keys(v_counts) LOOP
    v_n := (v_counts ->> v_key)::bigint;
    v_avg_n := 0;
    CASE v_key
      WHEN 'sales' THEN SELECT COALESCE(pg_total_relation_size('public.sales') / NULLIF((SELECT count(*) FROM public.sales), 0), 0) INTO v_avg_n;
      WHEN 'saleItems' THEN SELECT COALESCE(pg_total_relation_size('public.sale_items') / NULLIF((SELECT count(*) FROM public.sale_items), 0), 0) INTO v_avg_n;
      WHEN 'purchases' THEN SELECT COALESCE(pg_total_relation_size('public.purchases') / NULLIF((SELECT count(*) FROM public.purchases), 0), 0) INTO v_avg_n;
      WHEN 'purchaseItems' THEN SELECT COALESCE(pg_total_relation_size('public.purchase_items') / NULLIF((SELECT count(*) FROM public.purchase_items), 0), 0) INTO v_avg_n;
      WHEN 'expenses' THEN SELECT COALESCE(pg_total_relation_size('public.expenses') / NULLIF((SELECT count(*) FROM public.expenses), 0), 0) INTO v_avg_n;
      WHEN 'stockMovements' THEN SELECT COALESCE(pg_total_relation_size('public.stock_movements') / NULLIF((SELECT count(*) FROM public.stock_movements), 0), 0) INTO v_avg_n;
      WHEN 'dailyClosings' THEN SELECT COALESCE(pg_total_relation_size('public.daily_closings') / NULLIF((SELECT count(*) FROM public.daily_closings), 0), 0) INTO v_avg_n;
      WHEN 'staffAttendance' THEN SELECT COALESCE(pg_total_relation_size('public.staff_attendance') / NULLIF((SELECT count(*) FROM public.staff_attendance), 0), 0) INTO v_avg_n;
      WHEN 'customers' THEN SELECT COALESCE(pg_total_relation_size('public.customers') / NULLIF((SELECT count(*) FROM public.customers), 0), 0) INTO v_avg_n;
      WHEN 'products' THEN SELECT COALESCE(pg_total_relation_size('public.products') / NULLIF((SELECT count(*) FROM public.products), 0), 0) INTO v_avg_n;
      ELSE v_avg_n := 0;
    END CASE;
    v_avg := v_avg || jsonb_build_object(v_key, v_avg_n);
    v_logical := v_logical + v_n * v_avg_n;
  END LOOP;

  RETURN jsonb_build_object(
    'counts', v_counts,
    'avgBytes', v_avg,
    'logicalBytesEst', v_logical,
    'dbBytesTotal', (SELECT pg_database_size(current_database())));
END; $$;

GRANT EXECUTE ON FUNCTION public.month_size_estimate(uuid, date) TO authenticated;
