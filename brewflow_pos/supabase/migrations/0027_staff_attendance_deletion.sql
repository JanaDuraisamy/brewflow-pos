-- ---------------------------------------------------------------------------
-- BrewFlow POS — 0027: Owner-only deletion of Staff Attendance
--
-- Owner requirement: a recorded attendance shift must be deletable, and the
-- delete must be an OWNER decision. 0023 gave staff_attendance a single
-- `FOR ALL USING (is_shop_member(shop_id))` policy, which lets every shop
-- member — including STAFF — DELETE rows straight through the Supabase API,
-- bypassing the app's owner guard entirely.
--
-- This migration splits that one policy per operation:
--   - SELECT / INSERT / UPDATE stay shop-scoped for every member, so staff
--     clock-in / clock-out (and the owner's edits) keep working unchanged.
--   - DELETE additionally requires is_shop_owner(), so a staff session cannot
--     remove attendance even with a valid token and a direct API call.
--
-- The app layer already enforces the same boundary (the Delete action is
-- owner-only in the UI and PayrollSummaryController.deleteAttendance calls
-- requireOwner); this is the database-side half of that guarantee, and it
-- reuses is_shop_owner() from 0026 rather than introducing a new helper.
--
-- Cross-device propagation needs no new table: attendance is cloud
-- authoritative on read, and a row the cloud no longer lists for a pulled
-- month window is hard-deleted from each device's local mirror on its next
-- read of that month. Removing a shift therefore clears it everywhere without
-- a tombstone entity, and without touching advances, daily/monthly salary or
-- the final payable calculation.
-- ---------------------------------------------------------------------------

drop policy if exists staff_attendance_all_own_shop on public.staff_attendance;

drop policy if exists staff_attendance_read_own_shop on public.staff_attendance;
create policy staff_attendance_read_own_shop on public.staff_attendance
  for select
  using (is_shop_member(shop_id));

drop policy if exists staff_attendance_insert_own_shop on public.staff_attendance;
create policy staff_attendance_insert_own_shop on public.staff_attendance
  for insert
  with check (is_shop_member(shop_id));

drop policy if exists staff_attendance_update_own_shop on public.staff_attendance;
create policy staff_attendance_update_own_shop on public.staff_attendance
  for update
  using (is_shop_member(shop_id))
  with check (is_shop_member(shop_id));

drop policy if exists staff_attendance_delete_owner_only on public.staff_attendance;
create policy staff_attendance_delete_owner_only on public.staff_attendance
  for delete
  using (is_shop_member(shop_id) and public.is_shop_owner());
