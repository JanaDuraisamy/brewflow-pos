import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Food Truck context-recovery migration contract (0034).
///
/// The Supabase migration cannot execute against production here, so this test
/// locks the exact authorization and labelling invariants in the migration
/// text. It guards the properties a future edit could silently break:
///
///  * A receipt must be labelled with its OWN shop's prefix, and Cafe must keep
///    `BF-` so every historic receipt stays valid.
///  * The shop-recovery RPC may only ever return the CALLER's own memberships.
///    It is the surface that replaces a SharedPreferences id after a clear-data
///    reinstall, so a leak here hands one owner another owner's shop ids.
///  * The 0033 RLS hole must stay closed: `visible_in_shops` is a READ gate.
///    Re-admitting it to a `for all` policy silently grants every authenticated
///    user UPDATE on price, cost and stock of another business's catalogue.
///  * `master_deletions` may widen READ to every shop the caller belongs to, but
///    its WRITE policies must not move — a staff member of a secondary shop
///    still must not author another shop's tombstones.
/// ---------------------------------------------------------------------------
void main() {
  late String sql;

  setUpAll(() {
    final file = File(
      'supabase/migrations/0034_food_truck_context_recovery.sql',
    );
    expect(file.existsSync(), isTrue, reason: 'migration 0034 must exist');
    // Normalised to \n so the section/policy matchers below can use plain
    // newlines. Without this the contract silently stops matching on a
    // checkout with CRLF line endings, which is a green-to-red flip that has
    // nothing to do with the SQL.
    sql = file.readAsStringSync().replaceAll('\r\n', '\n');
  });

  String section(String start, String end) {
    final begin = sql.indexOf(start);
    expect(begin, isNot(-1), reason: 'missing migration section: $start');
    final finish = sql.indexOf(end, begin);
    expect(finish, isNot(-1), reason: 'missing migration section: $end');
    return sql.substring(begin, finish);
  }

  /// The body of one `create policy ... on <table> ... ;` statement.
  String policy(String name) {
    final pattern = RegExp(
      'create policy $name\\b.*?;',
      dotAll: true,
    ).firstMatch(sql);
    expect(pattern, isNotNull, reason: 'policy $name must exist in 0034');
    return pattern!.group(0)!;
  }

  group('per-shop receipt prefix', () {
    test('the column defaults to the historical Cafe label', () {
      expect(
        sql,
        contains(
          "add column if not exists receipt_prefix text not null default 'BF-'",
        ),
        reason:
            'Cafe must keep BF- by default or every receipt it already issued '
            'changes on upgrade',
      );
    });

    test('the Food Truck shop is relabelled to FT-', () {
      expect(
        sql,
        contains("lower(btrim(name)) = 'food truck'"),
        reason: 'the truck is matched on the name the client itself writes',
      );
      expect(sql, contains("set receipt_prefix = 'FT-'"));
      expect(
        section("update public.shops\n   set receipt_prefix", '-- B.'),
        contains("receipt_prefix = 'BF-'"),
        reason:
            'the update must be a no-op for a shop whose prefix was already '
            'changed by the owner',
      );
    });

    test('the prefix resolver never returns an unprefixed label', () {
      final resolver = section(
        'create or replace function public.shop_receipt_prefix',
        'grant execute on function public.shop_receipt_prefix',
      );
      expect(resolver, contains('nullif(btrim(s.receipt_prefix), \'\')'));
      expect(
        resolver,
        contains("'BF-'"),
        reason: 'a missing or blank prefix must fall back, not vanish',
      );
    });

    test('no receipt allocator hardcodes BF- any more', () {
      final next = section(
        'create or replace function public.next_receipt_number',
        'grant execute on function public.next_receipt_number',
      );
      expect(
        next,
        contains('v_prefix := public.shop_receipt_prefix(p_shop_id)'),
      );
      expect(next, contains("return v_prefix || lpad(v_next::text, 6, '0')"));
      expect(
        next,
        isNot(contains("'BF-' ||")),
        reason: 'the literal label is the bug this migration removes',
      );

      final atomic = section(
        'create or replace function public.create_sale_atomic',
        'grant execute on function public.create_sale_atomic',
      );
      expect(
        atomic,
        contains('v_prefix := public.shop_receipt_prefix(p_shop_id)'),
      );
      expect(
        atomic,
        isNot(contains("v_receipt := 'BF-' ||")),
        reason: 'a truck sale must not be labelled as a Cafe sale',
      );
    });

    test('the per-shop sequence locking is preserved', () {
      // The prefix must not be the only thing that changed: the gapless,
      // row-locked allocator is the part that keeps two devices from minting
      // the same number, and this migration is not allowed to weaken it.
      final next = section(
        'create or replace function public.next_receipt_number',
        'grant execute on function public.next_receipt_number',
      );
      expect(next, contains('on conflict (shop_id) do nothing'));
      expect(next, contains('where shop_id = p_shop_id for update'));
      expect(next, contains('returning next_value into v_next'));
      expect(
        next,
        contains('if not public.is_shop_member(p_shop_id) then'),
        reason: 'membership must still be checked before allocating',
      );
    });
  });

  group('shop recovery RPC', () {
    test('it returns only the caller own memberships', () {
      final rpc = section(
        'create or replace function public.list_my_managed_shops',
        'grant execute on function public.list_my_managed_shops',
      );
      expect(
        rpc,
        contains('m.auth_user_id = auth.uid()'),
        reason:
            'this RPC is the clear-data recovery path; it must never expose '
            'another owner shop ids',
      );
      expect(rpc, contains('m.is_active'));
      expect(
        rpc,
        isNot(contains('m.role = ')),
        reason:
            'the filter is identity-based, never role-based, so a caller '
            'cannot widen it by filtering on their own role',
      );
    });

    test('it is granted to authenticated only', () {
      expect(
        sql,
        contains(
          'grant execute on function public.list_my_managed_shops() to authenticated;',
        ),
      );
      expect(
        sql,
        isNot(contains('list_my_managed_shops() to anon')),
        reason: 'the recovery surface must not be reachable anonymously',
      );
    });
  });

  group('product visibility RLS', () {
    test('the 0033 write hole is closed', () {
      // The exact string 0033 shipped. If it reappears anywhere, any
      // authenticated user can edit another business price, cost and stock.
      expect(
        sql,
        isNot(contains('or visible_in_shops = true\n  )')),
        reason: 'the visibility escape must not be back in a for-all policy',
      );

      final all = policy('products_all_own_shop');
      expect(all, contains('for all'));
      expect(
        all,
        contains('using (public.is_shop_member(shop_id))'),
        reason: 'writes are gated on membership of the owning shop alone',
      );
      expect(
        all,
        contains('with check (public.is_shop_member(shop_id))'),
        reason: 'a member must not re-point a product at another shop',
      );
      expect(
        all,
        isNot(contains('visible_in_shops')),
        reason: 'a write policy must not mention visibility at all',
      );
    });

    test('cross-shop reading is a separate, read-only policy', () {
      final read = policy('products_select_shared_visible');
      expect(read, contains('for select'));
      expect(read, contains('using (visible_in_shops = true)'));
      expect(
        read,
        isNot(contains('with check')),
        reason: 'a select policy cannot carry a write check',
      );
    });

    test('toggling visibility still requires ownership', () {
      // The owner-only toggle gate was created by 0033 and 0034 must NOT
      // redefine it — a second, weaker copy would quietly re-open the write
      // path this migration exists to close. So the gate is asserted where it
      // lives, and asserted absent from this file.
      expect(
        sql,
        isNot(
          contains('drop policy if exists products_owner_toggle_visibility'),
        ),
        reason: '0034 must leave the 0033 ownership gate exactly as it is',
      );
      expect(
        sql,
        isNot(contains('create policy products_owner_toggle_visibility')),
        reason: 'a second definition would let a later edit weaken the gate',
      );

      final previous = File(
        'supabase/migrations/0033_food_truck_product_visibility.sql',
      ).readAsStringSync();
      final toggle = RegExp(
        r'create policy products_owner_toggle_visibility\b.*?;',
        dotAll: true,
      ).firstMatch(previous);
      expect(toggle, isNotNull, reason: '0033 must still define the gate');

      final body = toggle!.group(0)!;
      expect(body, contains('for update'));
      expect(body, contains("m.role = 'OWNER'"));
      expect(body, contains('m.auth_user_id = auth.uid()'));
      expect(body, contains('m.is_active'));
    });

    test('shared variants are readable, and only via the parent product', () {
      final variants = policy('product_variants_select_shared_visible');
      expect(variants, contains('for select'));
      expect(
        variants,
        contains('p.visible_in_shops = true'),
        reason: 'a variant is shared when its parent product is',
      );
      // product_variants has no such column; referencing it bare would make the
      // policy fail to compile and take the whole migration down with it.
      final bare = RegExp(
        r'(?<!p\.)(?<!p)\bvisible_in_shops\b',
      ).allMatches(variants.replaceAll('p.visible_in_shops', ''));
      expect(
        bare,
        isEmpty,
        reason: 'visible_in_shops does not exist on product_variants',
      );
      expect(variants, contains('product_variants.product_id'));
    });
  });

  group('master_deletions read scope', () {
    test('reads widen to every shop the caller is a member of', () {
      final read = policy('master_deletions_select_member');
      expect(read, contains('for select'));
      expect(
        read,
        contains('using (public.is_shop_member(shop_id))'),
        reason:
            'a Food Truck tombstone must be readable, or a deletion made on '
            'one device never propagates',
      );
    });

    test('the read widening does not touch any write policy', () {
      expect(
        policy('master_deletions_select_member'),
        isNot(contains('with check')),
        reason: 'this migration must not widen tombstone writes',
      );
      expect(
        sql,
        isNot(contains('drop policy if exists master_deletions_all_own_shop')),
        reason:
            'replacing the 0026 all-in-one policy would silently change who '
            'may author tombstones; widen reads additively instead',
      );
      expect(
        sql,
        isNot(contains('drop policy if exists master_deletions_staff_profile')),
        reason: 'the 0032 staff deletion policies must be left intact',
      );
    });
  });
}
