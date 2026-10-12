-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0039: Shared stock (recipe consumption mapping)
--
-- Business requirement: several menu products (Plain / Cheese / Egg / Veg
-- Maggi) consume one underlying stock source (Maggi Packet) without the shop
-- knowing the split in advance. The ingredient is an ordinary product row
-- (purchased, alerted and synced like any other); `is_ingredient` only hides
-- it from the sale shelf. `product_recipes` maps a sellable product (or one
-- of its variants) to its ingredients with per-unit quantities.
--
-- Pattern: identical to the other master-data tables —
--   - UUID primary keys (client-generated, idempotent upserts)
--   - shop_id NOT NULL with FK → shops(id) ON DELETE CASCADE
--   - RLS FOR ALL USING/WITH CHECK (is_shop_member(shop_id)) — no policy
--     weakened
--   - BEFORE UPDATE trigger touch_row_updated_at() (server-owned updated_at)
--   - Incremental pull index on (shop_id, updated_at)
--
-- A sale of a product WITH recipe rows deducts ONLY its ingredients (one
-- conditional atomic deduction per ingredient, aggregated across lines);
-- products WITHOUT rows deduct their own stock exactly as before.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS is_ingredient boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.product_recipes (
  id                    uuid PRIMARY KEY,
  shop_id               uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  product_id            uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  variant_id            uuid NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  ingredient_product_id uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  ingredient_variant_id uuid NULL REFERENCES public.product_variants(id) ON DELETE CASCADE,
  quantity              integer NOT NULL CHECK (quantity >= 1),
  client_created_at     timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.product_recipes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_recipes_all_own_shop
  ON public.product_recipes;
CREATE POLICY product_recipes_all_own_shop
  ON public.product_recipes
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_product_recipes_pull
  ON public.product_recipes (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_product_recipes_product
  ON public.product_recipes (shop_id, product_id, variant_id);

DROP TRIGGER IF EXISTS trg_product_recipes_touch
  ON public.product_recipes;
CREATE TRIGGER trg_product_recipes_touch
  BEFORE UPDATE ON public.product_recipes
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();
