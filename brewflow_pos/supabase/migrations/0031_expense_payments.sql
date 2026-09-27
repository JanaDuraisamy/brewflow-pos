-- ---------------------------------------------------------------------------
-- 0031: Shop payable payments
--
-- The payable side of the ledger. `expenses` records what the shop OWES (its
-- NOT_PAID rows aggregate into a shop payable); this table records what the
-- shop actually PAYS against them.
--
-- Kept separate from `expenses` on purpose:
--   * a payment never edits, reduces or deletes an expense row, so the expense
--     history stays exactly as recorded;
--   * `payee_key` is a normalized name (lower(trim(name))) rather than an
--     expense id, because one payment settles a *group* of same-named expenses
--     ("Milk" 700 + "Milk" 900 = one 1600 payable);
--   * it mirrors `customer_payments` (0012) on the payable side, so the sync,
--     RLS and RPC conventions of that table carry over unchanged.
--
-- No balance column anywhere, on either side. The remaining balance is always
-- derived:
--     sum(active NOT_PAID expenses where lower(trim(name)) = payee_key)
--   - sum(expense_payments where payee_key = ... and reversed = false)
-- Because it is derived from rows that sync replicates verbatim, every device
-- computes the identical number. A stored balance would be per-device state
-- that sync could never converge on.
--
-- Shop isolation: same shape as `expenses`, whose policy 0007 re-pointed from
-- current_shop_id() to is_shop_member(shop_id) to keep Cafe and Food Truck
-- separate.
-- ---------------------------------------------------------------------------

create table if not exists public.expense_payments (
  id               uuid PRIMARY KEY,
  shop_id          uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  -- Normalized grouping key: lower(trim(name)) of the payee/item.
  payee_key        text NOT NULL CHECK (length(trim(payee_key)) > 0),
  -- Display name as written when the payment was recorded. Kept so payment
  -- history reads "Milk" instead of the lower-cased key.
  payee_name       text NULL,
  amount_paise     integer NOT NULL CHECK (amount_paise > 0),
  payment_method   text NOT NULL CHECK (payment_method IN ('CASH', 'UPI', 'BANK')),
  note             text NULL,
  paid_at          timestamptz NOT NULL,
  reversed         boolean NOT NULL DEFAULT false,
  reversed_at      timestamptz NULL,
  client_created_at timestamptz NOT NULL DEFAULT now(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now(),
  -- Reversal is the only way back out of a payment. A non-reversed row never
  -- carries a reversal timestamp and vice versa.
  CONSTRAINT expense_payments_reversal_pair CHECK (
    (reversed AND reversed_at IS NOT NULL) OR (NOT reversed AND reversed_at IS NULL)
  )
);

ALTER TABLE public.expense_payments ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- RLS: read like any other master data, write like moving money
--
-- A member-wide `FOR ALL` policy would be a hole: paying a payable moves money
-- out of the shop, and the owner-only guarantee in
-- record_expense_payment_atomic would be trivially bypassed by any STAFF
-- device doing a direct `upsert` against PostgREST. The offline outbox replay
-- path is exactly such a direct upsert, so the row policy is what actually
-- has to carry the owner check for the replay case.
--
-- So, mirroring the 0026 staff-deletion split: reads stay member-scoped so
-- every device can still pull the shop's payment history, while INSERT /
-- UPDATE / DELETE demand an active OWNER membership on that specific shop.
-- Owning Cafe therefore never grants the right to write Food Truck's payments.
-- ---------------------------------------------------------------------------
create or replace function public.owns_shop(target_shop_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public as $$
  select exists (
    select 1
      from public.user_shop_memberships m
     where m.auth_user_id = auth.uid()
       and m.shop_id = target_shop_id
       and m.is_active
       and m.role = 'OWNER'
  )
$$;

grant execute on function public.owns_shop(uuid) to authenticated;

-- Reads: any active member of the shop, so the payable and its payment history
-- render identically on every device regardless of who is logged in.
DROP POLICY IF EXISTS expense_payments_all_own_shop ON public.expense_payments;
DROP POLICY IF EXISTS expense_payments_read_own_shop ON public.expense_payments;
CREATE POLICY expense_payments_read_own_shop ON public.expense_payments
  FOR SELECT
  USING (is_shop_member(shop_id));

-- Writes: owner-only, per shop. Kept as three explicit policies rather than one
-- `FOR ALL` so a future change to reads cannot silently widen writes.
DROP POLICY IF EXISTS expense_payments_insert_own_shop ON public.expense_payments;
CREATE POLICY expense_payments_insert_own_shop ON public.expense_payments
  FOR INSERT
  WITH CHECK (owns_shop(shop_id));

DROP POLICY IF EXISTS expense_payments_update_own_shop ON public.expense_payments;
CREATE POLICY expense_payments_update_own_shop ON public.expense_payments
  FOR UPDATE
  USING (owns_shop(shop_id))
  WITH CHECK (owns_shop(shop_id));

-- Delete is the reversal escape hatch: a mistaken payment is reversed with
-- UPDATE, so a hard delete is never a legitimate app path. It stays owner-only
-- rather than being banned outright so an owner can still repair a bad row.
DROP POLICY IF EXISTS expense_payments_delete_own_shop ON public.expense_payments;
CREATE POLICY expense_payments_delete_own_shop ON public.expense_payments
  FOR DELETE
  USING (owns_shop(shop_id));

-- Payable reads are always "one payee in one shop" or "the whole shop".
CREATE INDEX idx_expense_payments_payee
  ON public.expense_payments (shop_id, payee_key);
CREATE INDEX idx_expense_payments_pull
  ON public.expense_payments (shop_id, updated_at);
CREATE INDEX idx_expense_payments_paid_at
  ON public.expense_payments (shop_id, paid_at);

DROP TRIGGER IF EXISTS trg_expense_payments_touch ON public.expense_payments;
CREATE TRIGGER trg_expense_payments_touch
  BEFORE UPDATE ON public.expense_payments
  FOR EACH ROW
  EXECUTE FUNCTION public.touch_row_updated_at();

-- ---------------------------------------------------------------------------
-- Atomic payment RPC
--
-- The server is authoritative whenever it is reachable: it recomputes the
-- payable from the same two row sets the app derives from and rejects an
-- over-payment, so two devices cannot both spend the same remaining balance.
-- The local drift repository mirrors the returned row, and the next sync cycle
-- reconciles.
--
-- Authorization is stricter than plain membership: paying a payable moves
-- money out, so it is OWNER-only for that specific shop, matching the app-side
-- `requireOwner` gate on the pay action. It is the same `owns_shop(shop_id)`
-- helper the row write policies use, so the online RPC and the offline outbox
-- replay cannot drift apart — owning Cafe never implies the right to pay Food
-- Truck's payables.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_expense_payment_atomic(
  p_shop_id uuid,
  p_payee_key text,
  p_payee_name text,
  p_amount_paise integer,
  p_payment_method text,
  p_paid_at timestamptz,
  p_note text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payment_id uuid := gen_random_uuid();
  v_now timestamptz := now();
  v_paid_at timestamptz;
  v_unpaid bigint;
  v_paid bigint;
  v_remaining bigint;
BEGIN
  IF NOT public.owns_shop(p_shop_id) THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF p_amount_paise IS NULL OR p_amount_paise <= 0 THEN
    RAISE EXCEPTION 'INVALID_AMOUNT';
  END IF;

  IF p_payee_key IS NULL OR length(trim(p_payee_key)) = 0 THEN
    RAISE EXCEPTION 'PAYEE_NOT_FOUND';
  END IF;

  IF p_payment_method IS NULL
     OR p_payment_method NOT IN ('CASH', 'UPI', 'BANK') THEN
    RAISE EXCEPTION 'INVALID_PAYMENT_METHOD';
  END IF;

  -- Derive the balance server-side, per payee, exactly as the client does.
  SELECT COALESCE(SUM(e.amount_paise), 0) INTO v_unpaid
    FROM public.expenses e
   WHERE e.shop_id = p_shop_id
     AND e.is_active = true
     AND e.payment_status = 'NOT_PAID'
     AND lower(trim(e.name)) = lower(trim(p_payee_key));

  SELECT COALESCE(SUM(p.amount_paise), 0) INTO v_paid
    FROM public.expense_payments p
   WHERE p.shop_id = p_shop_id
     AND p.reversed = false
     AND lower(trim(p.payee_key)) = lower(trim(p_payee_key));

  v_remaining := v_unpaid - v_paid;

  IF v_remaining <= 0 THEN
    RAISE EXCEPTION 'PAYEE_NOT_FOUND';
  END IF;

  IF p_amount_paise > v_remaining THEN
    RAISE EXCEPTION 'PAYMENT_EXCEEDS_DUE';
  END IF;

  v_paid_at := COALESCE(p_paid_at, v_now);

  INSERT INTO public.expense_payments (
    id, shop_id, payee_key, payee_name, amount_paise, payment_method,
    note, paid_at, reversed, reversed_at, client_created_at, created_at, updated_at
  ) VALUES (
    v_payment_id, p_shop_id, lower(trim(p_payee_key)),
    NULLIF(trim(p_payee_name), ''), p_amount_paise, p_payment_method,
    NULLIF(p_note, ''), v_paid_at, false, NULL, v_now, v_now, v_now
  );

  RETURN jsonb_build_object(
    'id', v_payment_id,
    'paidAt', v_paid_at,
    'remaining', v_remaining - p_amount_paise
  );
END; $$;

GRANT EXECUTE ON FUNCTION public.record_expense_payment_atomic(uuid, text, text, integer, text, timestamptz, text) TO authenticated;
