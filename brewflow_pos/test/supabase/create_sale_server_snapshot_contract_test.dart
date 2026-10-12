import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// `create_sale_atomic` (0047) server-snapshot contract.
///
/// 0046 deducted from the authoritative `product_recipes` rows but persisted
/// the client-supplied `consumed` key verbatim, so a recipe edit between the
/// client's snapshot read and the server's execution (or a stale/forged
/// payload) stored a snapshot that disagreed with what was deducted — and the
/// void then restored the wrong stock. 0047 derives every line's `consumed`
/// from the same temp rows that drove the deduction, orders the ingredient
/// locks deterministically, and scopes ingredient writes to the sale's shop.
///
/// The migrations cannot run against a real Postgres here, so these
/// assertions pin the source-text invariants the fix depends on:
///   S1  0047 is the last migration defining `create_sale_atomic`;
///   S2  the persisted snapshot is rebuilt from `t_recipe_needs` (per line,
///       per-unit quantities) and the client `consumed` key is never read;
///   S3  the ingredient deduction loop locks in a fixed
///       (product, variant) order;
///   S4  ingredient stock SELECT ... FOR UPDATE / UPDATE statements are
///       scoped with `shop_id = p_shop_id`;
///   S5  the 0015 guards are re-issued (CREATE OR REPLACE resets proconfig).
/// ---------------------------------------------------------------------------
void main() {
  const migrationsDir = 'supabase/migrations';
  late String sql;

  setUpAll(() {
    final file = File('$migrationsDir/0047_create_sale_server_snapshot.sql');
    expect(file.existsSync(), isTrue, reason: 'migration 0047 must exist');
    sql = file.readAsStringSync().replaceAll('\r\n', '\n');
  });

  group('S1 — 0047 is the last word on create_sale_atomic', () {
    test('defines it with the unchanged 9-arg signature', () {
      expect(
        sql,
        contains('create or replace function public.create_sale_atomic('),
      );
      expect(
        sql,
        contains('p_lines jsonb,\n  p_payments jsonb default null'),
        reason: 'the line/payment payload shape is part of the client contract',
      );
      expect(
        sql,
        isNot(contains('drop function')),
        reason:
            'same-signature OR REPLACE needs no drop; dropping would discard '
            'the guards and risk a two-candidate PostgREST catalog',
      );
    });

    test('no later migration in the tree redefines it', () {
      final dir = Directory(migrationsDir);
      final files =
          dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.sql'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      final definers = files
          .where(
            (f) => f.readAsStringSync().contains(
              'function public.create_sale_atomic',
            ),
          )
          .where(
            (f) =>
                f.readAsStringSync().contains('create or replace') ||
                f.readAsStringSync().contains('create function'),
          )
          .toList();
      expect(
        definers.last.path,
        contains('0047'),
        reason: '0047 must be the last migration to define the create RPC',
      );
    });
  });

  group('S2 — the snapshot is server-derived, never client-trusted', () {
    test('never reads the client-supplied consumed key', () {
      expect(
        sql,
        isNot(contains("v_line->'consumed'")),
        reason:
            'the client key is accepted for backward compatibility but must '
            'never be read for persistence; a stale or forged snapshot must '
            'not reach sale_items.consumed',
      );
    });

    test('rebuilds each line snapshot from the deduction accumulator', () {
      expect(
        sql,
        contains('line_idx integer not null'),
        reason:
            'the temp accumulator must tag rows per line, or per-line '
            'snapshots cannot be rebuilt from deduction data',
      );
      expect(sql, contains('where line_idx = v_line_idx'));
      expect(sql, contains('sum(need) / v_quantity as per_unit'));
      expect(
        sql,
        contains("jsonb_build_object(\n                  'ip'"),
        reason:
            'the persisted entries must keep the {ip, iv, q} shape the void '
            'parses',
      );
    });
  });

  group('S3 — deterministic ingredient lock order', () {
    test('the deduction loop orders by (product, variant)', () {
      expect(
        sql,
        contains(
          'from t_recipe_needs group by ingredient_product_id, ingredient_variant_id\n'
          '    order by ingredient_product_id, ingredient_variant_id',
        ),
        reason:
            'concurrent sales must lock shared ingredients in the same order '
            'or they can deadlock; the void already orders this way',
      );
    });
  });

  group('S4 — ingredient writes stay inside the sale shop', () {
    test('every ingredient lock and deduction is shop-scoped', () {
      final scopedLocks = RegExp(
        r'where id = v_recipe\.ingredient_(variant|product)_id and shop_id = p_shop_id for update',
      ).allMatches(sql).length;
      expect(
        scopedLocks,
        2,
        reason:
            'both the variant and the product SELECT ... FOR UPDATE must '
            'carry shop_id = p_shop_id',
      );
      final scopedUpdates = RegExp(
        r'where id = v_recipe\.ingredient_(variant|product)_id and shop_id = p_shop_id;',
      ).allMatches(sql).length;
      expect(
        scopedUpdates,
        2,
        reason:
            'both deduction UPDATEs must carry shop_id = p_shop_id, or a '
            'recipe row pointing at another shop would deduct across the '
            'tenant boundary',
      );
    });
  });

  group('S5 — the security envelope survives OR REPLACE', () {
    test('re-issues guards, grant and timeouts', () {
      expect(sql, contains('set search_path = public'));
      expect(
        sql,
        contains('grant execute on function public.create_sale_atomic('),
      );
      expect(sql, contains("set statement_timeout = '20s'"));
      expect(sql, contains("set lock_timeout = '10s'"));
      expect(sql, contains("set idle_in_transaction_session_timeout = '30s'"));
    });
  });
}
