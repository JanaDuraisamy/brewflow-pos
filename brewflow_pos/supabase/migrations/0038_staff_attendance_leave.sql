-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0038: Day-level Leave on staff_attendance
--
-- Owner requirement: Leave is an explicit day-level attendance state, NOT a
-- fake check-in/out shift. It rides the EXISTING staff_attendance entity,
-- outbox and incremental pull (no new sync system): the same STAFF_ATTENDANCE
-- wire, the same shop RLS, the same owner-only DELETE.
--
-- Columns (purely additive, existing rows untouched):
--   - is_leave boolean NOT NULL DEFAULT false (every existing shift stays
--     worked),
--   - leave_reason text NULL (optional owner note).
--
-- A Leave row carries its business-day cookie (UTC midnight date) in
-- in_at/out_at with worked_minutes 0 so the existing NOT NULL contract and
-- the open-shift notion (out_at IS NULL) stay intact; is_leave is the source
-- of truth and those timestamps are never rendered or counted. The CHECK
-- below enforces that Leave never accrues minutes.
--
-- RLS is unchanged (shop-scoped, owner-only DELETE from 0027). The pull
-- index already covers (shop_id, updated_at); no new index is required.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

ALTER TABLE public.staff_attendance
  ADD COLUMN IF NOT EXISTS is_leave boolean NOT NULL DEFAULT false;

ALTER TABLE public.staff_attendance
  ADD COLUMN IF NOT EXISTS leave_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_staff_attendance_leave_no_minutes'
  ) THEN
    ALTER TABLE public.staff_attendance
      ADD CONSTRAINT chk_staff_attendance_leave_no_minutes
      CHECK ((NOT is_leave) OR (worked_minutes = 0));
  END IF;
END $$;
