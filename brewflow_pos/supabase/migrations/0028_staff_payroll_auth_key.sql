-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0028: Key staff payroll rows on auth_user_id
--
-- Why: the payroll tables were keyed on `staff_user_id text`, which held the
-- LOCAL `users.id` — a uuid minted per device in
-- DriftStaffRepository._insertProfile (const Uuid().v4()). Two devices for the
-- same human therefore hold different local ids, so a second device queried
-- the cloud with an id the cloud had never seen and received zero rows:
-- attendance, advances and salary never propagated between real devices.
--
-- `auth_user_id` is the only identity that is stable across devices (it is
-- user_profiles' primary key and references auth.users). Going forward the
-- cloud is filtered and written on it. The local Drift mirror keeps its own
-- device-local `users.id`; the client maps between the two, so no local schema
-- change and no build_runner regeneration is required.
--
-- Legacy rows: `staff_user_id` was never uploaded anywhere else in the cloud,
-- and user_profiles has no local-profile `id` column, so pre-existing rows
-- CANNOT be attributed to a person by any join. They are left in place with a
-- null `auth_user_id` (inert, and NULLs never collide in the unique indexes
-- below) and are repaired by the client, which knows the mapping locally: the
-- originating device re-claims its own rows with
--   UPDATE ... SET auth_user_id = :auth WHERE shop_id = :shop
--     AND staff_user_id = :localId AND auth_user_id IS NULL
-- That predicate is keyed on the local id, so it can only ever claim rows
-- this device itself wrote, it is idempotent, and it can never resurrect a row
-- an owner genuinely deleted (those no longer exist to match).
--
-- The business keys move with the identity: (shop, staff, period) would let
-- two devices with different local ids each insert a row for the same person
-- and month, double-counting salary into the payable. Unique constraints are
-- therefore re-pointed to auth_user_id.
--
-- RLS is unchanged and deliberately not keyed on any staff column: the
-- policies stay shop-scoped (is_shop_member(shop_id), and owner-only DELETE
-- on staff_attendance from 0027).
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ======================== ATTENDANCE =======================================

ALTER TABLE public.staff_attendance
  ADD COLUMN IF NOT EXISTS auth_user_id text;

CREATE INDEX IF NOT EXISTS idx_staff_attendance_auth_pull
  ON public.staff_attendance (shop_id, auth_user_id, attendance_date);

-- Cheap path for the client re-claim; partial so it only holds legacy rows.
CREATE INDEX IF NOT EXISTS idx_staff_attendance_legacy_claim
  ON public.staff_attendance (shop_id, staff_user_id)
  WHERE auth_user_id IS NULL;

-- ======================== ADVANCES ========================================

ALTER TABLE public.staff_advances
  ADD COLUMN IF NOT EXISTS auth_user_id text;

CREATE INDEX IF NOT EXISTS idx_staff_advances_auth_pull
  ON public.staff_advances (shop_id, auth_user_id, advance_date);

CREATE INDEX IF NOT EXISTS idx_staff_advances_legacy_claim
  ON public.staff_advances (shop_id, staff_user_id)
  WHERE auth_user_id IS NULL;

-- ======================== MONTHLY SALARIES ================================

ALTER TABLE public.staff_monthly_salaries
  ADD COLUMN IF NOT EXISTS auth_user_id text;

CREATE INDEX IF NOT EXISTS idx_staff_monthly_salaries_auth_month
  ON public.staff_monthly_salaries (shop_id, auth_user_id, month_date);

CREATE INDEX IF NOT EXISTS idx_staff_monthly_salaries_legacy_claim
  ON public.staff_monthly_salaries (shop_id, staff_user_id)
  WHERE auth_user_id IS NULL;

-- Re-point the business key. The legacy constraint is dropped only after the
-- auth-keyed one exists, and both tolerate NULL auth_user_id (Postgres treats
-- NULLs as distinct), so no row can be lost or merged by this swap.
ALTER TABLE public.staff_monthly_salaries
  DROP CONSTRAINT IF EXISTS ux_staff_monthly_salaries_staff_month;
ALTER TABLE public.staff_monthly_salaries
  DROP CONSTRAINT IF EXISTS ux_staff_monthly_salaries_auth_month;
ALTER TABLE public.staff_monthly_salaries
  ADD CONSTRAINT ux_staff_monthly_salaries_auth_month
  UNIQUE (shop_id, auth_user_id, month_date);

-- ======================== DAILY SALARIES ==================================

ALTER TABLE public.staff_daily_salaries
  ADD COLUMN IF NOT EXISTS auth_user_id text;

CREATE INDEX IF NOT EXISTS idx_staff_daily_salaries_auth_date
  ON public.staff_daily_salaries (shop_id, auth_user_id, attendance_date);

CREATE INDEX IF NOT EXISTS idx_staff_daily_salaries_legacy_claim
  ON public.staff_daily_salaries (shop_id, staff_user_id)
  WHERE auth_user_id IS NULL;

ALTER TABLE public.staff_daily_salaries
  DROP CONSTRAINT IF EXISTS ux_staff_daily_salaries_staff_day;
ALTER TABLE public.staff_daily_salaries
  DROP CONSTRAINT IF EXISTS ux_staff_daily_salaries_auth_day;
ALTER TABLE public.staff_daily_salaries
  ADD CONSTRAINT ux_staff_daily_salaries_auth_day
  UNIQUE (shop_id, auth_user_id, attendance_date);
