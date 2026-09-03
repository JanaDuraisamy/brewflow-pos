-- ---------------------------------------------------------------------------
-- BrewFlow POS — Sale Offer Columns
--
-- Preserves offer context on cloud-synced sales: the total offer discount on
-- `public.sales` and the per-line discount + applied-offer identity on
-- `public.sale_items`. Mirrors the local Drift columns
-- (`sales.offer_discount_paise`, `sale_items.offer_discount_paise`,
-- `applied_offer_id/name/type`).
--
-- Contract (deliberate, do not "simplify"):
--
-- 1. PURELY ADDITIVE. All columns are nullable or have defaults, so rows
--    written before this migration (and older clients that do not send the
--    fields) keep working. Reads treat a missing discount as 0 / no offer.
-- 2. IMMUTABLE HISTORY. Sales and sale_items are append-only snapshots; the
--    offer fields are part of the snapshot written once at checkout.
-- 3. SHOP ISOLATION UNCHANGED. No RLS or policy changes — the existing
--    `is_shop_member(shop_id)` policies keep governing both tables.
-- ---------------------------------------------------------------------------

-- Sale header: total offer discount in paise.
ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS offer_discount_paise integer NOT NULL DEFAULT 0
    CHECK (offer_discount_paise >= 0);

-- Sale line: per-line discount + applied-offer identity snapshot.
ALTER TABLE public.sale_items
  ADD COLUMN IF NOT EXISTS offer_discount_paise integer NOT NULL DEFAULT 0
    CHECK (offer_discount_paise >= 0),
  ADD COLUMN IF NOT EXISTS applied_offer_id text NULL,
  ADD COLUMN IF NOT EXISTS applied_offer_name text NULL,
  ADD COLUMN IF NOT EXISTS applied_offer_type text NULL
    CHECK (
      applied_offer_type IS NULL
      OR applied_offer_type IN ('PERCENTAGE', 'COMBO', 'BUY_X_GET_Y')
    );
