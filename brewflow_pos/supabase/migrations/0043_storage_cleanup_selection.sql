-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0043: Month cleanup selection + open-bill protection +
-- per-category logical size estimates.
--
-- Additive safety/UX support for the owner month-cleanup flow. Nothing here
-- changes the default behaviour: called without the new arguments the RPCs
-- behave exactly like 0040.
--
-- 1. month_size_estimate — also report per-category average row widths for
--    the remaining month-scoped tables (sale_payments, customer_payments,
--    staff_advances, staff_daily_salaries, staff_monthly_salaries) so the
--    client can show an honest estimated logical size per cleanup category
--    (count x average row width). The existing categories are unchanged.
-- 2. month_preview_counts — also report openBillCount: the number of
--    NOT_PAID, non-voided in-month sales that still carry a remaining
--    balance after their recorded payments. The client uses it to warn the--    owner before a cleanup that would destroy customer outstanding.
-- 3. month_cleanup_atomic — new optional p_categories text[] (NULL = the
--    full month scope, exactly as before). When 'sales' is in scope, refuse
--    the month while any in-month bill is still unpaid or partially paid:
--    deleting those sales would erase customer outstanding and break the
--    ledger. Raises OPEN_BILLS (409) so the owner settles first.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- month_size_estimate: per-category average row widths for every month-scoped
-- table. Counts are EXACT row counts in the month window; byte figures are
-- honest estimates (per-table average row width x month rows) — Postgres
-- cannot attribute shared-table physical bytes to a calendar month.
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
      WHEN 'salePayments' THEN SELECT COALESCE(pg_total_relation_size('public.sale_payments') / NULLIF((SELECT count(*) FROM public.sale_payments), 0), 0) INTO v_avg_n;
      WHEN 'customerPayments' THEN SELECT COALESCE(pg_total_relation_size('public.customer_payments') / NULLIF((SELECT count(*) FROM public.customer_payments), 0), 0) INTO v_avg_n;
      WHEN 'purchases' THEN SELECT COALESCE(pg_total_relation_size('public.purchases') / NULLIF((SELECT count(*) FROM public.purchases), 0), 0) INTO v_avg_n;
      WHEN 'purchaseItems' THEN SELECT COALESCE(pg_total_relation_size('public.purchase_items') / NULLIF((SELECT count(*) FROM public.purchase_items), 0), 0) INTO v_avg_n;
      WHEN 'expenses' THEN SELECT COALESCE(pg_total_relation_size('public.expenses') / NULLIF((SELECT count(*) FROM public.expenses), 0), 0) INTO v_avg_n;
      WHEN 'stockMovements' THEN SELECT COALESCE(pg_total_relation_size('public.stock_movements') / NULLIF((SELECT count(*) FROM public.stock_movements), 0), 0) INTO v_avg_n;
      WHEN 'dailyClosings' THEN SELECT COALESCE(pg_total_relation_size('public.daily_closings') / NULLIF((SELECT count(*) FROM public.daily_closings), 0), 0) INTO v_avg_n;
      WHEN 'staffAttendance' THEN SELECT COALESCE(pg_total_relation_size('public.staff_attendance') / NULLIF((SELECT count(*) FROM public.staff_attendance), 0), 0) INTO v_avg_n;
      WHEN 'staffAdvances' THEN SELECT COALESCE(pg_total_relation_size('public.staff_advances') / NULLIF((SELECT count(*) FROM public.staff_advances), 0), 0) INTO v_avg_n;
      WHEN 'staffDailySalaries' THEN SELECT COALESCE(pg_total_relation_size('public.staff_daily_salaries') / NULLIF((SELECT count(*) FROM public.staff_daily_salaries), 0), 0) INTO v_avg_n;
      WHEN 'staffMonthlySalaries' THEN SELECT COALESCE(pg_total_relation_size('public.staff_monthly_salaries') / NULLIF((SELECT count(*) FROM public.staff_monthly_salaries), 0), 0) INTO v_avg_n;
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

-- ---------------------------------------------------------------------------
-- month_preview_counts: add openBillCount — in-month NOT_PAID, non-voided
-- sales that still carry a remaining balance after their recorded payments.
-- The client warns and blocks cleanup while this is > 0 (deleting those
-- bills would erase customer outstanding).
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
    'openBillCount', (SELECT count(*) FROM public.sales s
      WHERE s.shop_id = p_shop_id AND s.payment_status = 'NOT_PAID' AND s.voided = false
        AND s.created_at >= v_start AND s.created_at < v_end
        AND s.total_paise - (SELECT COALESCE(SUM(cp.amount_paise), 0)
          FROM public.customer_payments cp
          WHERE cp.sale_id = s.id AND cp.reversed = false) > 0),
    'confirmed', (SELECT count(*) FROM public.monthly_report_confirmations
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end),
    'alreadyCleaned', (SELECT count(*) FROM public.month_cleanup_markers
      WHERE shop_id = p_shop_id AND month >= v_start AND month < v_end)
  ) INTO v_result;
  RETURN v_result;
END; $$;

GRANT EXECUTE ON FUNCTION public.month_preview_counts(uuid, date) TO authenticated;

-- ---------------------------------------------------------------------------
-- month_cleanup_atomic: optional category selection + open-bill protection.
--
-- p_categories NULL (or absent) = the full month scope, exactly as before.
-- Otherwise only the listed categories are deleted; each maps to the same
-- tables the full scope used. When 'sales' is in scope the month is refused
-- while any in-month bill is still unpaid or partially paid — deleting it
-- would erase customer outstanding and break the ledger.
--
-- Out of scope by design (never silently touched): master data (products,
-- variants, categories, customers, suppliers, offers, recipes), payee-keyed
-- expense payments, the sync outbox, sequences and device-local bookkeeping.
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.month_cleanup_atomic(
  p_shop_id uuid,
  p_month date,
  p_marker_id uuid,
  p_categories text[] DEFAULT NULL
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
  v_sales_in_scope boolean;
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

  v_sales_in_scope := p_categories IS NULL OR 'sales' = ANY(p_categories);

  -- Open-bill protection: never delete unpaid/partially-paid customer bills.
  IF v_sales_in_scope AND EXISTS (SELECT 1 FROM public.sales s
      WHERE s.shop_id = p_shop_id AND s.payment_status = 'NOT_PAID' AND s.voided = false
        AND s.created_at >= v_start AND s.created_at < v_end
        AND s.total_paise - (SELECT COALESCE(SUM(cp.amount_paise), 0)
          FROM public.customer_payments cp
          WHERE cp.sale_id = s.id AND cp.reversed = false) > 0) THEN
    RAISE EXCEPTION 'OPEN_BILLS' USING ERRCODE = 'P0001';
  END IF;

  -- Children before parents (RESTRICT FKs), month window on the owning row.
  IF v_sales_in_scope THEN
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
  END IF;

  IF p_categories IS NULL OR 'purchases' = ANY(p_categories) THEN
    DELETE FROM public.purchase_items pi USING public.purchases p
      WHERE pi.purchase_id = p.id AND p.shop_id = p_shop_id
        AND p.created_at >= v_start AND p.created_at < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('purchaseItems', v_n);

    DELETE FROM public.purchases
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('purchases', v_n);
  END IF;

  IF p_categories IS NULL OR 'expenses' = ANY(p_categories) THEN
    DELETE FROM public.expenses
      WHERE shop_id = p_shop_id AND expense_date >= v_start AND expense_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('expenses', v_n);
  END IF;

  IF p_categories IS NULL OR 'stockMovements' = ANY(p_categories) THEN
    DELETE FROM public.stock_movements
      WHERE shop_id = p_shop_id AND created_at >= v_start AND created_at < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('stockMovements', v_n);
  END IF;

  IF p_categories IS NULL OR 'dailyClosings' = ANY(p_categories) THEN
    DELETE FROM public.daily_closings
      WHERE shop_id = p_shop_id AND business_date >= v_start AND business_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('dailyClosings', v_n);
  END IF;

  IF p_categories IS NULL OR 'staffAttendance' = ANY(p_categories) THEN
    DELETE FROM public.staff_attendance
      WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('staffAttendance', v_n);
  END IF;

  IF p_categories IS NULL OR 'staffAdvances' = ANY(p_categories) THEN
    DELETE FROM public.staff_advances
      WHERE shop_id = p_shop_id AND advance_date >= v_start AND advance_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('staffAdvances', v_n);
  END IF;

  IF p_categories IS NULL OR 'staffDailySalaries' = ANY(p_categories) THEN
    DELETE FROM public.staff_daily_salaries
      WHERE shop_id = p_shop_id AND attendance_date >= v_start AND attendance_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('staffDailySalaries', v_n);
  END IF;

  IF p_categories IS NULL OR 'staffMonthlySalaries' = ANY(p_categories) THEN
    DELETE FROM public.staff_monthly_salaries
      WHERE shop_id = p_shop_id AND month_date >= v_start AND month_date < v_end;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_deleted := v_deleted || jsonb_build_object('staffMonthlySalaries', v_n);
  END IF;

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

GRANT EXECUTE ON FUNCTION public.month_cleanup_atomic(uuid, date, uuid, text[]) TO authenticated;
