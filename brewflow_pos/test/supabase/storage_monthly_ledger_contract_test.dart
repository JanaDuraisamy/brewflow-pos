import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Monthly storage ledger cloud migration contract.
///
/// Migration 0040 adds the server side of the owner storage dashboard and
/// month-wise cleanup: the monthly snapshots ledger, the synced report
/// confirmations and the cleanup markers, plus the atomic preview/cleanup
/// functions. The migration cannot execute against production here, so this
/// test locks the exact shape of 0040 in its text.
///
/// Guarded properties:
///   1. the three ledger tables exist with shop scope, month key and RLS.
///   2. cleanup refuses unconfirmed months (NEEDS_REPORT) and converges on
///      repeat runs (alreadyCleaned) instead of deleting twice.
///   3. children are deleted before parents (RESTRICT-safe order).
///   4. master data, payee-keyed expense payments, outbox and bookkeeping are
///      never touched by the cleanup.
///   5. everything is idempotent (IF NOT EXISTS / OR REPLACE), because
///      migrations replay against partially-migrated databases.
/// ---------------------------------------------------------------------------
void main() {
  const migrationsDir = 'supabase/migrations';
  late String sql;

  setUpAll(() {
    final file = File('$migrationsDir/0040_storage_monthly_ledger.sql');
    expect(file.existsSync(), isTrue, reason: 'migration 0040 must exist');
    sql = file.readAsStringSync();
  });

  /// The whole statement, collapsed onto one line so wrapping in the source
  /// cannot hide a clause from the assertions.
  String flatten() => sql.replaceAll(RegExp(r'\s+'), ' ');

  group('ledger tables', () {
    test('snapshots, confirmations and markers exist shop-scoped', () {
      final flat = flatten();
      for (final table in [
        'storage_monthly_snapshots',
        'monthly_report_confirmations',
        'month_cleanup_markers',
      ]) {
        expect(
          flat,
          contains('CREATE TABLE IF NOT EXISTS public.$table ('),
          reason: '$table must be created idempotently',
        );
        expect(
          flat,
          contains('ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY;'),
          reason: '$table must have RLS enabled',
        );
        expect(
          flat,
          contains('${table}_all_own_shop'),
          reason: '$table must carry the owner shop policy',
        );
        expect(
          flat,
          contains('is_shop_member(shop_id)'),
          reason: 'shop isolation must use the standard membership check',
        );
      }
    });

    test('one confirmation and one marker per shop+month', () {
      final flat = flatten();
      expect(
        flat,
        contains('UNIQUE (shop_id, month)'),
        reason:
            're-confirming a month must converge on one row, never duplicate',
      );
    });
  });

  group('month_cleanup_atomic', () {
    test('refuses months without a report confirmation', () {
      final flat = flatten();
      expect(
        flat,
        contains('SELECT 1 FROM public.monthly_report_confirmations'),
        reason: 'destructive cleanup must check the confirmation first',
      );
      expect(
        flat,
        contains("RAISE EXCEPTION 'NEEDS_REPORT'"),
        reason: 'an unconfirmed month must fail loudly, never delete',
      );
    });

    test('repeat runs converge instead of deleting twice', () {
      final flat = flatten();
      expect(
        flat,
        contains('SELECT 1 FROM public.month_cleanup_markers'),
        reason: 'the marker from a previous run must be detected',
      );
      expect(
        flat,
        contains("'alreadyCleaned', true"),
        reason: 'a retry must report convergence with zero counts',
      );
    });

    test('children are deleted before parents', () {
      final flat = flatten();
      int indexOf(String needle) {
        final i = flat.indexOf(needle);
        expect(i, isNot(-1), reason: '$needle must exist');
        return i;
      }

      expect(
        indexOf('DELETE FROM public.sale_items'),
        lessThan(indexOf('DELETE FROM public.sales WHERE')),
        reason: 'sale items go before their sales (RESTRICT FK)',
      );
      expect(
        indexOf('DELETE FROM public.purchase_items'),
        lessThan(indexOf('DELETE FROM public.purchases WHERE')),
        reason: 'purchase items go before their purchases (RESTRICT FK)',
      );
      expect(
        flat,
        contains('DELETE FROM public.customer_payments'),
        reason:
            'payments linked to the month sales must go, or the sales delete '
            'trips the RESTRICT key',
      );
    });

    test('master and queue tables are never touched', () {
      final flat = flatten();
      // Extract just the cleanup function body: the preview function
      // legitimately counts master rows.
      final body = flat.substring(flat.indexOf('month_cleanup_atomic'));
      for (final table in [
        'public.products ',
        'public.customers ',
        'public.product_recipes',
        'public.expense_payments',
        'public.sync_outbox',
      ]) {
        expect(
          body,
          isNot(contains('DELETE FROM $table')),
          reason: '$table must never be month-deleted',
        );
      }
    });

    test('is owner-gated and executable by authenticated clients', () {
      final flat = flatten();
      expect(
        flat,
        contains('IF NOT public.owns_shop(p_shop_id)'),
        reason:
            'the DEFINER function must still check the caller owns the shop',
      );
      expect(
        flat,
        contains(
          'GRANT EXECUTE ON FUNCTION public.month_cleanup_atomic(uuid, date, uuid) '
          'TO authenticated;',
        ),
      );
      expect(
        flat,
        contains(
          'GRANT EXECUTE ON FUNCTION public.month_preview_counts(uuid, date) '
          'TO authenticated;',
        ),
      );
    });
  });
}
