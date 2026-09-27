-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0024: Cloud persistence for Daily Staff Salary amounts
--
-- Owner requirement: the owner-entered DAILY salary amounts (one per staff
-- member per business day) MUST NOT stay local-device-only. They feed the
-- CALCULATED monthly salary (SUM of daily amounts), so a tablet-entered daily
-- amount must appear on the owner's phone after login and vice-versa,
-- preserving Cafe/Food Truck business scoping. The local Drift table stays as
-- an offline cache; Supabase is the authoritative store.
--
-- Pattern: identical to 0023 (staff_attendance / staff_monthly_salaries):
--   - UUID primary keys (client-generated, idempotent upserts)
--   - shop_id NOT NULL with FK → shops(id) ON DELETE CASCADE
--   - RLS FOR ALL USING/WITH CHECK (is_shop_member(shop_id)) — no policy
--     weakened
--   - BEFORE UPDATE trigger touch_row_updated_at() (server-owned updated_at)
--   - Incremental pull index on (shop_id, updated_at)
--   - staff_user_id is plain text matching the local Users.id
--
-- UNIQUE (shop_id, staff_user_id, attendance_date) is the BUSINESS key: the
-- daily salary for one staff member on one business day is a single value.
-- Cross-device edits upsert on that composite key (onConflict), so two
-- devices can never create duplicate rows for the same day and the monthly
-- SUM can never double-count a day.
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.staff_daily_salaries (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  staff_user_id    text NOT NULL,
  attendance_date  date NOT NULL,
  salary_paise     integer NOT NULL CHECK (salary_paise >= 0),
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ux_staff_daily_salaries_staff_day
    UNIQUE (shop_id, staff_user_id, attendance_date)
);

ALTER TABLE public.staff_daily_salaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_daily_salaries_all_own_shop
  ON public.staff_daily_salaries;
CREATE POLICY staff_daily_salaries_all_own_shop
  ON public.staff_daily_salaries
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_staff_daily_salaries_pull
  ON public.staff_daily_salaries (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_staff_daily_salaries_staff_date
  ON public.staff_daily_salaries (staff_user_id, attendance_date);

DROP TRIGGER IF EXISTS trg_staff_daily_salaries_touch
  ON public.staff_daily_salaries;
CREATE TRIGGER trg_staff_daily_salaries_touch
  BEFORE UPDATE ON public.staff_daily_salaries
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();