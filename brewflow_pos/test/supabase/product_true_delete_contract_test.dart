import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Product true-delete cloud migration contract.
///
/// The Supabase migration cannot execute against production here, so this test
/// locks the exact shape of migration 0037 in its text. It guards the two
/// properties a future edit could silently break:
///
///   1. `product_variants.product_id` must end up `ON DELETE CASCADE`, so
///      deleting a product that has variants really deletes them instead of
///      raising a foreign-key violation — the whole point of the migration.
///   2. the six historical ledger columns must stay FK-free, so nothing here
///      turns a product with sales/purchases/stock history undeletable again,
///      and no historical row is nulled or rewritten.
///
/// It also asserts the drop/re-add is idempotent, because migrations get
/// replayed against partially-migrated databases.
/// ---------------------------------------------------------------------------
void main() {
  const migrationsDir = 'supabase/migrations';
  late String sql;

  setUpAll(() {
    final file = File('$migrationsDir/0037_product_true_delete.sql');
    expect(file.existsSync(), isTrue, reason: 'migration 0037 must exist');
    sql = file.readAsStringSync();
  });

  /// The whole statement, collapsed onto one line so wrapping in the source
  /// cannot hide a clause from the assertions.
  String flatten() => sql.replaceAll(RegExp(r'\s+'), ' ');

  group('product_variants cascades with its product', () {
    test('the re-added foreign key carries ON DELETE CASCADE', () {
      final flat = flatten();
      expect(
        flat,
        contains(
          'add constraint product_variants_product_id_fkey foreign key '
          '(product_id) references public.products (id) on delete cascade',
        ),
        reason:
            'a product with variants must be really deletable — this is the '
            'constraint that was blocking it',
      );
    });

    test('the previous delete action is dropped first, whatever it was', () {
      final flat = flatten();
      expect(
        flat,
        contains("contype = 'f'"),
        reason: 'only foreign keys may be dropped',
      );
      expect(
        flat,
        contains("confrelid = 'public.products'::regclass"),
        reason: 'only the constraint that points at products may be dropped',
      );
      expect(
        flat,
        contains('alter table public.product_variants drop constraint %I'),
        reason:
            'the constraint name must be looked up, not hardcoded, so the '
            'migration is replayable against a differently-named constraint',
      );
    });

    test('the drop-then-add is idempotent, not a duplicate-constraint error', () {
      final flat = flatten();
      final dropIndex = flat.indexOf('drop constraint %I');
      final addIndex = flat.indexOf(
        'add constraint product_variants_product_id_fkey',
      );
      expect(dropIndex, isNonNegative);
      expect(addIndex, greaterThan(dropIndex), reason: 'drop must precede add');
      // A plain `add constraint` fails on replay with 42710 (duplicate). It
      // cannot here because the drop loop is UNCONDITIONAL: it selects every FK
      // pointing at products without inspecting its delete action, so a
      // constraint that is already CASCADE is dropped and re-added just the
      // same. Guarding the drop on `confdelact` would break exactly that.
      expect(
        flat,
        isNot(contains('confdelact')),
        reason:
            'the drop must not be conditional on the current delete action, or a '
            'replay hits a duplicate-constraint error',
      );
      expect(flat, contains("confrelid = 'public.products'::regclass"));
    });
  });

  group('history is never nulled or re-referenced', () {
    test('this migration adds no new foreign key to a ledger table', () {
      // Only the product_variants retarget may create a constraint. Anything
      // adding a key on sale_items / purchase_items / stock_movements would
      // resurrect exactly the restriction 0037 exists to remove.
      expect(flatten(), isNot(contains('add constraint public.sale_items')));
      expect(
        flatten(),
        isNot(contains('add constraint public.purchase_items')),
      );
      expect(
        flatten(),
        isNot(contains('add constraint public.stock_movements')),
      );
      expect(flatten(), isNot(contains('set null')));
      expect(flatten(), isNot(contains('update public.sale_items')));
      expect(flatten(), isNot(contains('update public.purchase_items')));
      expect(flatten(), isNot(contains('update public.stock_movements')));
    });

    test('the ledger columns are documented as intentionally FK-free', () {
      expect(sql, contains('comment on column public.sale_items.product_id'));
    });
  });

  group('nothing else is touched', () {
    test('no RLS, policy, grant or index change sneaks in', () {
      final flat = flatten();
      expect(flat, isNot(contains('create policy')));
      expect(flat, isNot(contains('drop policy')));
      expect(flat, isNot(contains('enable row level security')));
      expect(flat, isNot(contains('grant ')));
      expect(flat, isNot(contains('revoke ')));
      expect(
        flat,
        isNot(contains('create index')),
        reason: 'a new index here would be unrelated schema churn',
      );
      expect(
        flat,
        isNot(contains('drop index')),
        reason: 'indexes already exist and must be preserved',
      );
    });
  });

  group('it is genuinely the last word on this constraint', () {
    test('no later migration re-adds a restrictive variant FK', () {
      final files =
          Directory(migrationsDir)
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.sql'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));

      int number(File f) => int.parse(
        RegExp(r'^(\d+)').firstMatch(f.path.split(r'\').last)!.group(1)!,
      );

      for (final file in files.where((f) => number(f) > 37)) {
        final later = file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        expect(
          later,
          isNot(contains('product_variants_product_id_fkey')),
          reason:
              '${file.path.split(r'\').last} re-references the variant foreign '
              'key and would undo the cascade',
        );
        expect(
          later,
          isNot(matches(RegExp(r'references\s+public\.products'))),
          reason:
              '${file.path.split(r'\').last} references products directly; '
              'check whether it is restrictive again',
        );
      }
    });
  });
}
