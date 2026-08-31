-- ============================================================================
-- BrewFlow POS — Migration 0004: Transaction Sync
--
-- Creates cloud mirror tables for sales, sale items, expenses, and customer
-- payments. Follows the exact same patterns as 0003_master_data_sync.sql:
--   - UUID primary keys (client-generated)
--   - shop_id NOT NULL with FK → shops(id) ON DELETE CASCADE
--   - RLS via current_shop_id() for shop isolation
--   - BEFORE UPDATE triggers for server-owned updated_at
--   - Incremental pull indexes on (shop_id, updated_at)
--   - UPSERT-based idempotent apply (ON CONFLICT (id) DO UPDATE)
--
-- Deletion semantics:
--   Sales, sale_items, and customer_payments are immutable append-only
--   records. Expenses support soft-deactivation (is_active flag) only.
--   NONE of these entities require tombstone rows in master_deletions.
--
-- Idempotent: safe to re-run (CREATE TABLE IF NOT EXISTS, CREATE POLICY IF
-- NOT EXISTS patterns not used — Supabase migrations run once).
-- ============================================================================

-- ======================== SALES =============================================

CREATE TABLE public.sales (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  customer_id      uuid NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
  receipt_number   text NOT NULL,
  subtotal_paise   integer NOT NULL CHECK (subtotal_paise >= 0),
  total_paise      integer NOT NULL CHECK (total_paise >= 0),
  payment_method   text NULL CHECK (payment_method IS NULL OR payment_method IN ('CASH', 'UPI', 'BANK')),
  payment_status   text NOT NULL DEFAULT 'PAID' CHECK (payment_status IN ('PAID', 'NOT_PAID')),
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  -- Duplicate protection: one receipt number per shop (matches local UNIQUE).
  CONSTRAINT ux_sales_shop_receipt UNIQUE (shop_id, receipt_number)
);

-- RLS: shop isolation (matches existing pattern from 0003).
ALTER TABLE public.sales ENABLE ROW LEVEL SECURITY;

CREATE POLICY sales_all_own_shop ON public.sales
  FOR ALL
  USING (shop_id = public.current_shop_id())
  WITH CHECK (shop_id = public.current_shop_id());

-- Incremental pull index.
CREATE INDEX idx_sales_pull ON public.sales (shop_id, updated_at);

-- Server-owned updated_at trigger.
CREATE TRIGGER trg_sales_touch
  BEFORE UPDATE ON public.sales
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== SALE ITEMS ========================================

CREATE TABLE public.sale_items (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  sale_id          uuid NOT NULL REFERENCES public.sales(id) ON DELETE RESTRICT,
  product_id       uuid NOT NULL,
  variant_id       uuid NULL,
  product_name     text NOT NULL,
  variant_name     text NULL,
  sku              text NULL,
  unit_price_paise integer NOT NULL CHECK (unit_price_paise >= 0),
  quantity         integer NOT NULL CHECK (quantity > 0),
  line_total_paise integer NOT NULL CHECK (line_total_paise >= 0),
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.sale_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY sale_items_all_own_shop ON public.sale_items
  FOR ALL
  USING (shop_id = public.current_shop_id())
  WITH CHECK (shop_id = public.current_shop_id());

CREATE INDEX idx_sale_items_pull ON public.sale_items (shop_id, updated_at);
CREATE INDEX idx_sale_items_sale ON public.sale_items (sale_id);

CREATE TRIGGER trg_sale_items_touch
  BEFORE UPDATE ON public.sale_items
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== EXPENSES ==========================================

CREATE TABLE public.expenses (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  name             text NOT NULL,
  amount_paise     integer NOT NULL CHECK (amount_paise >= 0),
  category         text NOT NULL CHECK (category IN (
    'SUPPLIES', 'UTILITIES', 'RENT', 'SALARIES',
    'MAINTENANCE', 'MARKETING', 'TRANSPORT', 'MISC'
  )),
  payment_method   text NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK')),
  payment_status   text NOT NULL DEFAULT 'PAID' CHECK (payment_status IN ('PAID', 'NOT_PAID')),
  expense_date     timestamptz NOT NULL,
  note             text NULL,
  is_active        boolean NOT NULL DEFAULT true,
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY expenses_all_own_shop ON public.expenses
  FOR ALL
  USING (shop_id = public.current_shop_id())
  WITH CHECK (shop_id = public.current_shop_id());

CREATE INDEX idx_expenses_pull ON public.expenses (shop_id, updated_at);

CREATE TRIGGER trg_expenses_touch
  BEFORE UPDATE ON public.expenses
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== CUSTOMER PAYMENTS =================================

CREATE TABLE public.customer_payments (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  customer_id      uuid NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
  sale_id          uuid NULL REFERENCES public.sales(id) ON DELETE RESTRICT,
  amount_paise     integer NOT NULL CHECK (amount_paise >= 0),
  payment_method   text NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK')),
  note             text NULL,
  paid_at          timestamptz NOT NULL,
  reversed         boolean NOT NULL DEFAULT false,
  reversed_at      timestamptz NULL,
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.customer_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_payments_all_own_shop ON public.customer_payments
  FOR ALL
  USING (shop_id = public.current_shop_id())
  WITH CHECK (shop_id = public.current_shop_id());

CREATE INDEX idx_customer_payments_pull ON public.customer_payments (shop_id, updated_at);
CREATE INDEX idx_customer_payments_customer ON public.customer_payments (customer_id);

CREATE TRIGGER trg_customer_payments_touch
  BEFORE UPDATE ON public.customer_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();
