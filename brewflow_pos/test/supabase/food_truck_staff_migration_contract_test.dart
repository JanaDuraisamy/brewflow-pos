import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Food Truck staff-management migration contract.
///
/// The Supabase migration cannot execute against production here, so this test
/// locks the exact authorization invariants in the migration text. It guards
/// the two properties a future edit could silently break: owner reactivation
/// must never become STAFF self-promotion, and STAFF_PROFILE tombstones must
/// be authorized by the tombstone's own shop rather than the primary shop.
/// ---------------------------------------------------------------------------
void main() {
  late String sql;

  setUpAll(() {
    final file = File(
      'supabase/migrations/0032_food_truck_staff_management.sql',
    );
    expect(file.existsSync(), isTrue, reason: 'migration 0032 must exist');
    sql = file.readAsStringSync();
  });

  String section(String start, String end) {
    final begin = sql.indexOf(start);
    final finish = sql.indexOf(end, begin);
    expect(begin, isNot(-1), reason: 'missing migration section $start');
    expect(finish, isNot(-1), reason: 'missing migration section $end');
    return sql.substring(begin, finish);
  }

  test('owner reactivation cannot promote STAFF or duplicate memberships', () {
    final bootstrap = section(
      'create or replace function public.bootstrap_owner_membership',
      'grant execute on function public.bootstrap_owner_membership',
    );

    expect(
      bootstrap,
      contains('and m.is_active is false'),
      reason: 'only the caller’s own inactive OWNER row may unblock a claim',
    );
    expect(
      bootstrap,
      contains("v_role <> 'OWNER'"),
      reason: 'a non-OWNER profile must still be rejected before any claim',
    );
    expect(
      bootstrap,
      contains('preserve the existing role'),
      reason: 'conflict updates must not escalate STAFF to OWNER',
    );
    expect(
      bootstrap,
      contains('on conflict (auth_user_id, shop_id)'),
      reason: 'reactivation must reuse the unique membership row',
    );
    expect(
      bootstrap,
      isNot(contains('delete from public.user_shop_memberships')),
      reason: 'membership history must not be deleted by a bootstrap repair',
    );
  });

  test('STAFF_PROFILE tombstone policies use the tombstone shop only', () {
    final policies = RegExp(
      r'create policy master_deletions_staff_profile_.*?;',
      dotAll: true,
    ).allMatches(sql).map((match) => match.group(0)!).join('\n');
    expect(policies, isNotEmpty);

    expect(
      policies,
      isNot(contains('current_shop_id')),
      reason: 'the primary shop must not authorize another business tombstone',
    );
    expect(
      policies,
      contains('is_staff_profile_delete_allowed(shop_id)'),
      reason: 'the tombstone’s own shop must carry the OWNER check',
    );
    expect(
      policies,
      isNot(contains("entity <> 'STAFF_PROFILE'")),
      reason: 'these additive policies must not touch ordinary entities',
    );
  });

  test('atomic deletion refuses OWNER targets before writing anything', () {
    final atomic = section(
      'create or replace function public.delete_staff_profile_atomic',
      'grant execute on function public.delete_staff_profile_atomic',
    );
    final roleRefusal = atomic.indexOf("v_role <> 'STAFF'");
    final callerCheck = atomic.indexOf(
      'is_staff_profile_delete_allowed(v_shop_id)',
    );
    final deleteProfile = atomic.indexOf('delete from public.user_profiles');
    final deactivateMembership = atomic.indexOf(
      'update public.user_shop_memberships',
    );
    final tombstone = atomic.indexOf('insert into public.master_deletions');

    expect([
      roleRefusal,
      callerCheck,
      deleteProfile,
      deactivateMembership,
      tombstone,
    ], everyElement(isNot(-1)));
    expect(
      [
        roleRefusal,
        callerCheck,
        deleteProfile,
        deactivateMembership,
        tombstone,
      ],
      orderedEquals(
        [
          roleRefusal,
          callerCheck,
          deleteProfile,
          deactivateMembership,
          tombstone,
        ]..sort(),
      ),
      reason: 'OWNER/caller checks must precede every cloud write',
    );
    expect(
      atomic,
      contains("and u.role = 'STAFF'"),
      reason: 'a concurrent promotion must not slip through the delete',
    );
    expect(
      atomic,
      contains('is_active = false'),
      reason: 'the STAFF membership must be revoked without deleting its row',
    );
  });
}
