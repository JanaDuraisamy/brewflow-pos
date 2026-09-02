-- BrewFlow POS — Migration 0006: Offers (business-scoped)
CREATE TABLE IF NOT EXISTS public.offers (
  id uuid PRIMARY KEY,
  shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  name text NOT NULL,
  type text NOT NULL CHECK (type IN ('PERCENTAGE','COMBO','BUY_X_GET_Y')),
  config_json text NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  start_at timestamptz NULL,
  end_at timestamptz NULL,
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (start_at IS NULL OR end_at IS NULL OR start_at <= end_at)
);
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
CREATE POLICY offers_all_own_shop ON public.offers FOR ALL USING (shop_id = public.current_shop_id()) WITH CHECK (shop_id = public.current_shop_id());
CREATE INDEX IF NOT EXISTS idx_offers_pull ON public.offers (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_offers_shop_active ON public.offers (shop_id, is_active);
CREATE TRIGGER trg_offers_touch BEFORE UPDATE ON public.offers FOR EACH ROW EXECUTE FUNCTION public.touch_row_updated_at();
-- Allow OFFER tombstones
ALTER TABLE public.master_deletions DROP CONSTRAINT IF EXISTS master_deletions_entity_check;
ALTER TABLE public.master_deletions ADD CONSTRAINT master_deletions_entity_check CHECK (entity IN ('CATEGORY','PRODUCT','PRODUCT_VARIANT','SUPPLIER','CUSTOMER','EXPENSE','OFFER'));
