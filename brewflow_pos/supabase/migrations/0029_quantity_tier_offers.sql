-- BrewFlow POS — Migration 0029: Quantity-tier offers
--
-- Adds the QUANTITY_TIER offer type ("buy X quantity for Rs.Y", e.g.
-- 1 Kulfi = 45, 2 = 85, 3 = 120). This is a bundled PRICE, not a free
-- item, so it is a distinct type from BUY_X_GET_Y.
--
-- Postgres cannot widen an existing CHECK in place, so the old constraints
-- are dropped and re-added. The DROP step looks the constraint up by
-- definition rather than by name, because inline column CHECKs are
-- auto-named (<table>_<column>_check) and the exact name depends on how the
-- table was first created (CREATE TABLE IF NOT EXISTS vs. a pre-existing
-- install). RLS, policies and triggers on these tables are untouched.
--
-- Local mirror: the same value set is enforced by the Drift `offers` table
-- CHECK constraint, migrated locally in schema v25.

-- ---------------------------------------------------------------------------
-- offers.type
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  constraint_row record;
BEGIN
  FOR constraint_row IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE rel.relname = 'offers'
      AND nsp.nspname = 'public'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%PERCENTAGE%'
      AND pg_get_constraintdef(con.oid) LIKE '%BUY_X_GET_Y%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.offers DROP CONSTRAINT %I',
      constraint_row.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.offers
  DROP CONSTRAINT IF EXISTS offers_type_check;

ALTER TABLE public.offers
  ADD CONSTRAINT offers_type_check
  CHECK (type IN ('PERCENTAGE','QUANTITY_TIER','COMBO','BUY_X_GET_Y'));

-- ---------------------------------------------------------------------------
-- sale_items.applied_offer_type (the per-line snapshot written at checkout)
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  constraint_row record;
BEGIN
  FOR constraint_row IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    WHERE rel.relname = 'sale_items'
      AND nsp.nspname = 'public'
      AND con.contype = 'c'
      AND pg_get_constraintdef(con.oid) LIKE '%applied_offer_type%'
      AND pg_get_constraintdef(con.oid) LIKE '%BUY_X_GET_Y%'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.sale_items DROP CONSTRAINT %I',
      constraint_row.conname
    );
  END LOOP;
END $$;

ALTER TABLE public.sale_items
  DROP CONSTRAINT IF EXISTS sale_items_applied_offer_type_check;

ALTER TABLE public.sale_items
  ADD CONSTRAINT sale_items_applied_offer_type_check
  CHECK (
    applied_offer_type IS NULL
    OR applied_offer_type IN ('PERCENTAGE','QUANTITY_TIER','COMBO','BUY_X_GET_Y')
  );
