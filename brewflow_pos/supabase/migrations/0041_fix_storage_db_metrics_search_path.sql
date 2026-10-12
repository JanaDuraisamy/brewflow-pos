-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0041: Fix storage_db_metrics search_path
--
-- The function storage_db_metrics(uuid) was created in migration 0040 with
-- `SET search_path = public`. Its body calls pg_total_relation_size(),
-- format(), jsonb_build_object(), and pg_database_size() — all of which
-- live in pg_catalog, not public. With search_path restricted to public
-- only, these functions cannot be resolved at runtime, causing HTTP 500.
--
-- This migration adds pg_catalog (and storage, for future-proofing) to the
-- function's search_path. No logic, authorization, return shape, or cleanup
-- behavior is changed.
--
-- Append-only: never edit released migrations. Apply with:
--   supabase db push
--   or: supabase db execute --file supabase/migrations/0041_fix_storage_db_metrics_search_path.sql
-- ---------------------------------------------------------------------------

ALTER FUNCTION public.storage_db_metrics(uuid)
  SET search_path = public, pg_catalog, storage;
