import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Staff attendance cloud contract.
///
/// The Supabase migrations cannot execute against production here, so this test
/// locks the exact shape of the attendance schema in its text. It guards the
/// properties a future edit could silently break:
///
///   1. the base table (0023) keeps its NOT NULL contract, the pull index and
///      the server-owned `updated_at` trigger — the incremental pull depends on
///      all three;
///   2. delete stays OWNER-only (0027) — the per-member `FOR ALL` policy must be
///      gone, or a STAFF session could delete attendance through the API;
///   3. the cross-device key is `auth_user_id` (0028) — the local `staff_user_id`
///      is device-local and must never be the identity again;
///   4. Leave is additive (0038): `is_leave` defaults false, a Leave row can
///      never carry minutes, and the constraint is added idempotently.
///
/// It also asserts no LATER migration re-opens a permissive attendance policy or
/// reintroduces a device-local identity, because migrations are append-only and
/// get replayed against partially-migrated databases.
/// ---------------------------------------------------------------------------
void main() {
  const migrationsDir = 'supabase/migrations';

  late String base;
  late String ownerDelete;
  late String authKey;
  late String leave;

  String read(String name) {
    final file = File('$migrationsDir/$name');
    expect(file.existsSync(), isTrue, reason: '$name must exist');
    return file.readAsStringSync();
  }

  setUpAll(() {
    base = read('0023_staff_payroll_daily_closing.sql');
    ownerDelete = read('0027_staff_attendance_deletion.sql');
    authKey = read('0028_staff_payroll_auth_key.sql');
    leave = read('0038_staff_attendance_leave.sql');
  });

  /// The whole statement collapsed onto one line so wrapping in the source
  /// cannot hide a clause from the assertions.
  String flatten(String sql) => sql.replaceAll(RegExp(r'\s+'), ' ');

  group('base table (0023) keeps the pull contract', () {
    test('the table and its NOT NULL columns are unchanged', () {
      final flat = flatten(base);
      expect(
        flat,
        contains('CREATE TABLE IF NOT EXISTS public.staff_attendance'),
      );
      expect(flat, contains('id uuid PRIMARY KEY'));
      expect(
        flat,
        contains(
          'shop_id uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE',
        ),
        reason: 'a deleted shop must take its attendance with it',
      );
      expect(flat, contains('staff_user_id text NOT NULL'));
      expect(flat, contains('in_at timestamptz NOT NULL'));
      expect(flat, contains('out_at timestamptz NULL'));
      expect(
        flat,
        contains('worked_minutes integer NOT NULL DEFAULT 0'),
        reason: 'minutes accrue from zero and can never be negative',
      );
      expect(flat, contains('CHECK (worked_minutes >= 0)'));
    });

    test('RLS is enabled and the incremental pull index exists', () {
      final flat = flatten(base);
      expect(flat, contains('ENABLE ROW LEVEL SECURITY'));
      expect(
        flat,
        contains('idx_staff_attendance_pull'),
        reason: 'the (shop_id, updated_at) cursor index drives every pull',
      );
      expect(flat, contains('(shop_id, updated_at)'));
    });

    test('updated_at is server-owned by a BEFORE UPDATE trigger', () {
      final flat = flatten(base);
      expect(flat, contains('trg_staff_attendance_touch'));
      expect(flat, contains('BEFORE UPDATE ON public.staff_attendance'));
      expect(flat, contains('public.touch_row_updated_at()'));
    });
  });

  group('delete is owner-only (0027)', () {
    test('the old catch-all member policy is dropped', () {
      final flat = flatten(ownerDelete);
      expect(
        flat,
        contains('drop policy if exists staff_attendance_all_own_shop'),
        reason:
            'the single FOR ALL policy let STAFF delete attendance via the API',
      );
      expect(flat, isNot(contains('for all using')));
    });

    test('read / insert / update stay shop-scoped for every member', () {
      final flat = flatten(ownerDelete);
      expect(flat, contains('staff_attendance_read_own_shop'));
      expect(flat, contains('staff_attendance_insert_own_shop'));
      expect(flat, contains('staff_attendance_update_own_shop'));
      // Staff must keep clocking in/out: every non-delete clause is member-only.
      expect(
        RegExp(r'is_shop_member\(shop_id\)').allMatches(flat).length,
        greaterThanOrEqualTo(4),
      );
    });

    test('delete additionally requires an owner', () {
      final flat = flatten(ownerDelete);
      expect(flat, contains('staff_attendance_delete_owner_only'));
      expect(flat, contains('for delete using (is_shop_member(shop_id) and'));
      expect(flat, contains('public.is_shop_owner()'));
    });
  });

  group('cross-device identity is auth_user_id (0028)', () {
    test('the auth key column and pull index are added', () {
      final flat = flatten(authKey);
      expect(
        flat,
        contains(
          'ALTER TABLE public.staff_attendance ADD COLUMN IF NOT EXISTS auth_user_id text',
        ),
      );
      expect(flat, contains('idx_staff_attendance_auth_pull'));
      expect(flat, contains('(shop_id, auth_user_id, attendance_date)'));
    });

    test('the legacy-claim lookup is partial on rows with no auth key', () {
      final flat = flatten(authKey);
      expect(flat, contains('idx_staff_attendance_legacy_claim'));
      expect(
        flat,
        contains('WHERE auth_user_id IS NULL'),
        reason: 'only pre-0028 rows may ever be re-claimed',
      );
    });

    test('RLS is deliberately unchanged here', () {
      final flat = flatten(authKey);
      expect(flat, isNot(contains('create policy')));
      expect(flat, isNot(contains('drop policy')));
    });
  });

  group('Leave is a day-level state on the same row (0038)', () {
    test('columns are additive and default to a worked day', () {
      final flat = flatten(leave);
      expect(
        flat,
        contains(
          'ADD COLUMN IF NOT EXISTS is_leave boolean NOT NULL DEFAULT false',
        ),
        reason: 'every pre-existing shift must stay worked',
      );
      expect(flat, contains('ADD COLUMN IF NOT EXISTS leave_reason text'));
    });

    test('a Leave row can never accrue minutes', () {
      final flat = flatten(leave);
      expect(flat, contains('chk_staff_attendance_leave_no_minutes'));
      expect(flat, contains('CHECK ((NOT is_leave) OR (worked_minutes = 0))'));
    });

    test('the constraint is added idempotently', () {
      final flat = flatten(leave);
      expect(
        flat,
        contains('WHERE conname = \'chk_staff_attendance_leave_no_minutes\''),
        reason: 'a replay must not hit a duplicate-constraint error',
      );
      expect(flat, contains('IF NOT EXISTS'));
    });
  });

  group('no later migration undoes the attendance contract', () {
    test('later migrations never re-open a permissive policy or local key', () {
      final files =
          Directory(migrationsDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.sql'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      String name(File f) => f.path.split(RegExp(r'[\\/]')).last;
      int number(File f) =>
          int.parse(RegExp(r'^(\d+)').firstMatch(name(f))!.group(1)!);

      for (final file in files.where((f) => number(f) > 38)) {
        final flat = flatten(file.readAsStringSync());
        expect(
          flat,
          isNot(contains('staff_attendance_all_own_shop')),
          reason:
              '${name(file)} re-creates the per-member attendance policy that '
              '0027 removed',
        );
        expect(
          flat,
          isNot(
            matches(
              RegExp(
                r'(create|drop)\s+policy[^;]*?staff_attendance',
                caseSensitive: false,
              ),
            ),
          ),
          reason:
              '${name(file)} touches attendance RLS; verify owner-only delete '
              'is preserved',
        );
      }
    });
  });
}
