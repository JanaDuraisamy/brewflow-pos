import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// `void_sale_atomic` (0045) + `void_sale_without_restore_atomic` contract.
///
/// Mirror of `create_sale_atomic_contract_test.dart`: the migrations cannot run
/// against a real Postgres here, so these assertions pin the invariants that the
/// 0045 review found broken in the first draft:
///   C1  the UPDATE ... RETURNING capture must use a dedicated record, never
///       overwrite the loop cursor;
///   C2  the legacy (no-snapshot) reversal must aggregate ONCE for the sale,
///       outside the per-line loop;
///   C3  a pruned/mixed history must RAISE (roll the whole transaction back),
///       never `return` after partial writes;
///   C5  a NONE-only legacy sale must void cleanly (no stock, no movements);
///   C9  the 0015 guards must be re-issued (CREATE OR REPLACE resets proconfig).
///
/// It also locks the no-restore function to its contract: same guards, payments
/// reversed, sale voided, stock and movements untouched.
/// ---------------------------------------------------------------------------
void main() {
  const migrationsDir = 'supabase/migrations';
  late String sql;

  setUpAll(() {
    final file = File(
      '$migrationsDir/0045_void_reverses_recorded_consumption.sql',
    );
    expect(file.existsSync(), isTrue, reason: 'migration 0045 must exist');
    sql = file.readAsStringSync().replaceAll('\r\n', '\n');
  });

  group('0045 is the last word on void_sale_atomic', () {
    test('defines void_sale_atomic with the unchanged 1-arg signature', () {
      expect(
        sql,
        contains('create or replace function public.void_sale_atomic('),
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
      int number(File f) => int.parse(
        RegExp(
          r'^(\d+)',
        ).firstMatch(f.path.split(Platform.pathSeparator).last)!.group(1)!,
      );
      final definers = files
          .where((f) => f.readAsStringSync().contains('void_sale_atomic'))
          .where(
            (f) =>
                f.readAsStringSync().contains('create or replace') ||
                f.readAsStringSync().contains('create function'),
          )
          .where((f) => number(f) <= 45)
          .toList();
      expect(
        definers.last.path,
        contains('0045'),
        reason: '0045 must be the last migration to define the void RPC',
      );
    });

    test('preserves the security envelope and the void side effects', () {
      expect(sql, contains('set search_path = public'));
      expect(sql, contains('if not public.is_shop_member(v_shop_id) then'));
      expect(sql, contains("raise exception 'FORBIDDEN'"));
      expect(sql, contains("raise exception 'ALREADY_VOIDED'"));
      expect(sql, contains('set reversed = true'));
      expect(sql, contains('set voided = true'));
      expect(
        sql,
        contains('from public.sales where id = p_sale_id for update'),
        reason: 'the sale header lock is what serializes concurrent voids',
      );
    });
  });

  group('C1 — the UPDATE ... RETURNING capture uses a dedicated record', () {
    test('never writes into the loop cursor', () {
      expect(
        sql,
        contains('returning stock_quantity into v_after'),
        reason: 'the post-update level must land in its own record',
      );
      expect(
        sql,
        isNot(contains('into v_row')),
        reason:
            'C1: `select ... into v_row`/`returning ... into v_row` inside the '
            '`for v_row` loop clobbers the loop cursor and reads dead fields',
      );
    });

    test('declares a distinct v_after record', () {
      expect(sql, contains('v_after record'));
    });
  });

  group('C2/C8 — movement reversal is sale-level and deterministic', () {
    test('aggregates the legacy movements once, grouped and ordered', () {
      expect(
        sql,
        contains('group by sm.product_id, sm.variant_id'),
        reason: 'C2: per-line aggregation multiplies the restore',
      );
      expect(
        sql,
        contains('order by sm.product_id, sm.variant_id'),
        reason: 'C8: a fixed lock order is what makes concurrent voids safe',
      );
    });

    test('the legacy reversal is not nested in the per-line loop', () {
      // The only `for v_row in` loops must be the snapshot contribution set
      // and the legacy movement set — both keyed by stock entity, never by a
      // `sale_items` line cursor named v_line.
      expect(
        sql,
        isNot(contains('v_line')),
        reason: 'C2: a per-line loop is exactly the multiplication bug',
      );
    });
  });

  group('C3 — pruned/mixed history fails before any mutation', () {
    test('raises instead of returning a partial result', () {
      expect(sql, contains("raise exception 'VOID_HISTORY_PRUNED'"));
      expect(sql, contains("raise exception 'VOID_SNAPSHOT_MIXED'"));
      expect(
        sql,
        isNot(contains('history_pruned')),
        reason:
            'C3: the old fail path `return ... reason history_pruned` committed '
            'earlier writes; failure must be an exception',
      );
    });

    test('the restorability proof precedes the mutation loops', () {
      final proveAt = sql.indexOf('VOID_HISTORY_PRUNED');
      final firstUpdateAt = sql.indexOf('update public.product_variants');
      expect(proveAt, isNot(-1));
      expect(
        proveAt,
        lessThan(firstUpdateAt),
        reason: 'C3/decision 4: prove restorability before touching stock',
      );
    });
  });

  group('C4/C5 — snapshot rule and NONE handling', () {
    test('non-empty snapshot restores ingredients x line quantity', () {
      expect(sql, contains('jsonb_array_length(si.consumed) > 0'));
      expect(
        sql,
        contains("(e.value->>'q')::int * si.quantity"),
        reason: 'the snapshot quantity is per unit and scales by the line',
      );
    });

    test('empty snapshot means no ingredients, own stock only when tracked', () {
      expect(sql, contains("si.consumed = '[]'::jsonb"));
      expect(
        sql,
        contains("p.stock_unit <> 'NONE'"),
        reason:
            'C5/decision: NONE lines provably consumed nothing; tracked lines '
            'derive their own stock from stock_unit, never from recipes',
      );
      expect(
        sql,
        isNot(contains('from public.product_recipes')),
        reason: 'the whole point of 0045 is to stop consulting current recipes',
      );
    });

    test('writes one VOID audit movement per restored entity', () {
      expect(sql, contains("'VOID', v_row.total"));
      expect(sql, contains("'SALE', p_sale_id"));
    });
  });

  group('C9 — the 0015 guards are re-issued after CREATE OR REPLACE', () {
    test('void_sale_atomic regains all three settings', () {
      expect(
        sql,
        contains(
          'alter function public.void_sale_atomic(uuid)\n'
          "  set statement_timeout = '20s'",
        ),
      );
      expect(
        sql,
        contains(
          'alter function public.void_sale_atomic(uuid)\n'
          "  set lock_timeout = '10s'",
        ),
      );
      expect(
        sql,
        contains(
          'alter function public.void_sale_atomic(uuid)\n'
          "  set idle_in_transaction_session_timeout = '30s'",
        ),
      );
    });
  });

  group('the no-restore contract is distinct and safe', () {
    late String noRestoreBody;

    setUpAll(() {
      final start = sql.indexOf(
        'create or replace function public.void_sale_without_restore_atomic',
      );
      expect(start, isNot(-1), reason: 'the no-restore RPC must be defined');
      noRestoreBody = sql.substring(start);
    });

    test('has the same guards and void side effects', () {
      expect(noRestoreBody, contains('set search_path = public'));
      expect(
        noRestoreBody,
        contains('if not public.is_shop_member(v_shop_id) then'),
      );
      expect(noRestoreBody, contains("raise exception 'ALREADY_VOIDED'"));
      expect(noRestoreBody, contains('set reversed = true'));
      expect(noRestoreBody, contains('set voided = true'));
    });

    test('never touches stock or the movement ledger', () {
      expect(
        noRestoreBody,
        isNot(contains('stock_quantity')),
        reason: 'the no-restore contract must not credit stock',
      );
      expect(
        noRestoreBody,
        isNot(contains('stock_movements')),
        reason: 'and must not write an audit movement',
      );
    });

    test('is granted and guarded', () {
      expect(
        sql,
        contains(
          'grant execute on function '
          'public.void_sale_without_restore_atomic(uuid) to authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'alter function public.void_sale_without_restore_atomic(uuid)\n'
          "  set statement_timeout = '20s'",
        ),
      );
    });
  });
}
