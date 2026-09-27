-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0023: Cloud persistence for Staff Attendance, Manual Salary,
-- Staff Advances and Daily Closing
--
-- Owner requirement: attendance, salary and advances MUST NOT be
-- local-device-only. They must load on another owner device after login,
-- preserving Cafe/Food Truck business scoping. Same for daily closing
-- records. The local Drift tables stay as an offline cache; Supabase is the
-- authoritative store (the client reads cloud-first when online).
--
-- Pattern: identical to 0004_transaction_sync.sql / 0007 multi-business RLS:
--   - UUID primary keys (client-generated, idempotent upserts)
--   - shop_id NOT NULL with FK → shops(id) ON DELETE CASCADE
--   - RLS FOR ALL USING/WITH CHECK (is_shop_member(shop_id)) — no policy
--     weakened; owners see Cafe + Food Truck via memberships, staff see only
--     their own shop (client permission MANAGE_STAFF / expenses still gates UI)
--   - BEFORE UPDATE trigger touch_row_updated_at() (server-owned updated_at)
--   - Incremental pull indexes on (shop_id, updated_at)
--   - staff_user_id is plain text matching the local Users.id (no FK: local
--     profile ids and auth ids live in different identity surfaces)
--
-- Append-only: never edit released migrations.
-- ---------------------------------------------------------------------------

-- ======================== STAFF ATTENDANCE =================================

CREATE TABLE IF NOT EXISTS public.staff_attendance (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  staff_user_id    text NOT NULL,
  in_at            timestamptz NOT NULL,
  out_at           timestamptz NULL,
  attendance_date  date NOT NULL,
  worked_minutes   integer NOT NULL DEFAULT 0 CHECK (worked_minutes >= 0),
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.staff_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_attendance_all_own_shop ON public.staff_attendance;
CREATE POLICY staff_attendance_all_own_shop ON public.staff_attendance
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_staff_attendance_pull
  ON public.staff_attendance (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_staff_attendance_staff_date
  ON public.staff_attendance (staff_user_id, attendance_date);

DROP TRIGGER IF EXISTS trg_staff_attendance_touch ON public.staff_attendance;
CREATE TRIGGER trg_staff_attendance_touch
  BEFORE UPDATE ON public.staff_attendance
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== STAFF ADVANCES ===================================

CREATE TABLE IF NOT EXISTS public.staff_advances (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  staff_user_id    text NOT NULL,
  amount_paise     integer NOT NULL CHECK (amount_paise >= 0),
  advance_date     date NOT NULL,
  note             text NULL,
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.staff_advances ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_advances_all_own_shop ON public.staff_advances;
CREATE POLICY staff_advances_all_own_shop ON public.staff_advances
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_staff_advances_pull
  ON public.staff_advances (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_staff_advances_staff_date
  ON public.staff_advances (staff_user_id, advance_date);

DROP TRIGGER IF EXISTS trg_staff_advances_touch ON public.staff_advances;
CREATE TRIGGER trg_staff_advances_touch
  BEFORE UPDATE ON public.staff_advances
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== STAFF MONTHLY SALARIES ===========================
-- Owner-entered manual salary per staff member per month. Salary is NEVER
-- derived from an hourly rate: attendance hours are display-only.

CREATE TABLE IF NOT EXISTS public.staff_monthly_salaries (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  staff_user_id    text NOT NULL,
  month_date       date NOT NULL,
  salary_paise     integer NOT NULL CHECK (salary_paise >= 0),
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT ux_staff_monthly_salaries_staff_month
    UNIQUE (shop_id, staff_user_id, month_date)
);

ALTER TABLE public.staff_monthly_salaries ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS staff_monthly_salaries_all_own_shop
  ON public.staff_monthly_salaries;
CREATE POLICY staff_monthly_salaries_all_own_shop
  ON public.staff_monthly_salaries
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_staff_monthly_salaries_pull
  ON public.staff_monthly_salaries (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_staff_monthly_salaries_staff_month
  ON public.staff_monthly_salaries (staff_user_id, month_date);

DROP TRIGGER IF EXISTS trg_staff_monthly_salaries_touch
  ON public.staff_monthly_salaries;
CREATE TRIGGER trg_staff_monthly_salaries_touch
  BEFORE UPDATE ON public.staff_monthly_salaries
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();


-- ======================== DAILY CLOSINGS ===================================

CREATE TABLE IF NOT EXISTS public.daily_closings (
  id                    uuid PRIMARY KEY,
  shop_id               uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  business_date         date NOT NULL,
  total_cash_paise      integer NOT NULL DEFAULT 0 CHECK (total_cash_paise >= 0),
  total_upi_paise       integer NOT NULL DEFAULT 0 CHECK (total_upi_paise >= 0),
  total_sales_paise     integer NOT NULL DEFAULT 0 CHECK (total_sales_paise >= 0),
  total_expense_paise   integer NOT NULL DEFAULT 0 CHECK (total_expense_paise >= 0),
  cash_left_in_box_paise integer NOT NULL DEFAULT 0 CHECK (cash_left_in_box_paise >= 0),
  cash_taken_out_paise  integer NOT NULL DEFAULT 0 CHECK (cash_taken_out_paise >= 0),
  taken_out_by          text NULL,
  tallied_by            text NULL,
  note                  text NULL,
  client_created_at     timestamptz NOT NULL DEFAULT now(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.daily_closings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS daily_closings_all_own_shop ON public.daily_closings;
CREATE POLICY daily_closings_all_own_shop ON public.daily_closings
  FOR ALL USING (is_shop_member(shop_id))
  WITH CHECK (is_shop_member(shop_id));

CREATE INDEX IF NOT EXISTS idx_daily_closings_pull
  ON public.daily_closings (shop_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_daily_closings_shop_date
  ON public.daily_closings (shop_id, business_date);

DROP TRIGGER IF EXISTS trg_daily_closings_touch ON public.daily_closings;
CREATE TRIGGER trg_daily_closings_touch
  BEFORE UPDATE ON public.daily_closings
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();
