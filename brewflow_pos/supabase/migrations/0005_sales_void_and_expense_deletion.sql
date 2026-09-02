-- ============================================================================
-- BrewFlow POS — Migration 0005: Sales void + expense deletion
--
-- A. Adds void columns to public.sales so that voided sales propagate
--    cross-device (local Drift already has voided/voided_at; cloud was
--    missing them, causing Supabase gateway to strip the flag).
--
-- B. Widens master_deletions entity check to include EXPENSE so that
--    expense deletions (soft-deactivation via tombstone) can be recorded
--    without a CHECK violation.
--
-- Idempotent: safe to re-run.
-- ============================================================================

-- A. Sales void columns (append-only UPSERT with is_active semantics)
ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS voided boolean NOT NULL DEFAULT false;

ALTER TABLE public.sales
  ADD COLUMN IF NOT EXISTS voided_at timestamptz NULL;

-- B. Allow EXPENSE tombstones
ALTER TABLE public.master_deletions DROP CONSTRAINT IF EXISTS master_deletions_entity_check;

ALTER TABLE public.master_deletions
  ADD CONSTRAINT master_deletions_entity_check
  CHECK (entity IN ('CATEGORY','PRODUCT','PRODUCT_VARIANT','SUPPLIER','CUSTOMER','EXPENSE'));
