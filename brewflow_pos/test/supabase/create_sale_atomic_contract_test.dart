import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// `create_sale_atomic` RPC / schema contract.
///
/// The Supabase migrations cannot execute against production here, so this test
/// derives the REAL `sale_sequences` column set from the migration that created
/// it (0011) and then proves no migration ever references a column outside it.
///
/// That derivation is the point. The production outage
/// (`column "id" of relation "sale_sequences" does not exist`, 42703) shipped
/// because 0035 hard-coded an `insert into public.sale_sequences (id, shop_id,
/// next_value) ... on conflict (id, shop_id)` — the shape of a global
/// GENERATED-ALWAYS sequence — against a table whose sole primary key has
/// always been `shop_id`. Reading the column list out of 0011 rather than
/// restating it means a future migration cannot reintroduce the same invented
/// column without failing here.
///
/// It also locks the invariants 0035 dropped while it was rewriting the
/// function: the membership check, the stock ledger, the per-shop receipt
/// prefix, and shop isolation on `sale_payments`.
/// ---------------------------------------------------------------------------
/// Statement boundary markers. `$$` delimits a function body, which is where
/// nearly every `sale_sequences` reference lives, so it has to split the same
/// way `;` does — otherwise a scan of one statement window swallows the next.
final RegExp _statementBoundary = RegExp(r'[;$]{2}|\$\$|;');

/// The SQL text of every statement that mentions `public.sale_sequences`.
///
/// Scoping to whole statements is what makes the column scan trustworthy: a
/// bare `<ident> =` term anywhere in a file is far too noisy, but every
/// identifier that appears in an insert column list, an `on conflict` target, a
/// `set` target or a `where` comparison *inside a sale_sequences statement* is
/// unambiguously a column of that table.
List<String> saleSequencesStatements(String sql) {
  final lower = sql.toLowerCase();
  final statements = <String>[];
  var start = 0;
  for (final match in _statementBoundary.allMatches(lower)) {
    final statement = sql.substring(start, match.start);
    if (statement.contains('public.sale_sequences')) {
      statements.add(statement);
    }
    start = match.end;
  }
  final tail = sql.substring(start);
  if (tail.contains('public.sale_sequences')) statements.add(tail);
  return statements;
}

/// Column names referenced against `public.sale_sequences`, in the slots where
/// a column can only mean a column of that table.
///
/// Statements that merely NAME the table are ignored — a `pg_policies` lookup
/// or a `create policy ... on public.sale_sequences` mentions it without
/// touching a column, and its identifiers (`policyname`, `tablename`) are
/// catalog columns, not columns of the counter. A statement only contributes
/// references if it actually reads or writes a row.
List<String> saleSequencesColumnRefs(String statement) {
  final lower = statement.toLowerCase();
  final readsOrWrites =
      lower.contains('insert into public.sale_sequences') ||
      lower.contains('update public.sale_sequences') ||
      lower.contains('from public.sale_sequences');
  if (!readsOrWrites) return const [];

  final refs = <String>[];

  // `insert into public.sale_sequences (a, b, c)`. A statement with no column
  // list writes defaults only, so it can name no column.
  final insert = RegExp(
    r'insert\s+into\s+public\.sale_sequences\s*\(([^)]*)\)',
    dotAll: true,
  ).firstMatch(statement);
  if (insert != null) {
    refs.addAll(
      insert
          .group(1)!
          .split(',')
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty),
    );
  }

  // `on conflict (a, b)` — only meaningful when it follows a sale_sequences
  // insert, which is the only place an ON CONFLICT can appear in a window.
  final conflict = RegExp(
    r'conflict\s*\(([^)]*)\)',
    dotAll: true,
  ).firstMatch(statement);
  if (conflict != null) {
    refs.addAll(
      conflict
          .group(1)!
          .split(',')
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty && c != 'where' && c != 'on'),
    );
  }

  // `set <col> = ...` — the update target list.
  final set = RegExp(
    r'\bset\s+([a-z_][a-z0-9_]*)\s*=',
    dotAll: true,
  ).firstMatch(statement);
  if (set != null) {
    refs.add(set.group(1)!.toLowerCase());
  }

  // `where <col> <op> ...` — including the sequence key, which is the one
  // identifier that must always be present in these statements.
  final where = RegExp(
    r'\bwhere\s+([a-z_][a-z0-9_]*)\s*(?:=|<>|>=|<=|>|<)',
    dotAll: true,
  ).allMatches(statement);
  for (final match in where) {
    refs.add(match.group(1)!.toLowerCase());
  }

  // `select <col>[, <col>...] from public.sale_sequences` — the projection.
  // The optional `into <variables>` clause is skipped: those are plpgsql
  // locals, not columns, which is exactly the ambiguity the production bug
  // slipped through.
  final select = RegExp(
    r'\bselect\s+(?:distinct\s+)?'
    r'([a-z_][a-z0-9_]*(?:\s*,\s*[a-z_][a-z0-9_]*)*)'
    r'(?:\s+into\s+[a-z_][a-z0-9_]*(?:\s*,\s*[a-z_][a-z0-9_]*)*)?'
    r'\s+from\s+public\.sale_sequences\b',
    dotAll: true,
  ).firstMatch(statement);
  if (select != null) {
    refs.addAll(
      select
          .group(1)!
          .split(',')
          .map((c) => c.trim().toLowerCase())
          .where((c) => c.isNotEmpty),
    );
  }

  return refs;
}

void main() {
  const migrationsDir = 'supabase/migrations';

  late String currentSql; // the live create_sale_atomic (0036)
  late List<String> sequenceColumns;
  late List<String> sequenceKeyColumns;

  setUpAll(() {
    // --- Derive the real sale_sequences shape from the migration that made it.
    final origin = File('$migrationsDir/0011_online_billing_purchases.sql');
    expect(origin.existsSync(), isTrue, reason: 'migration 0011 must exist');
    final originSql = origin.readAsStringSync();

    final open = originSql.indexOf(
      'create table if not exists public.sale_sequences',
    );
    expect(open, isNot(-1), reason: '0011 must create sale_sequences');
    final bodyStart = originSql.indexOf('(', open);
    final bodyEnd = originSql.indexOf(');', bodyStart);
    final body = originSql.substring(bodyStart + 1, bodyEnd);

    const tableKeywords = {
      'constraint',
      'primary',
      'unique',
      'check',
      'foreign',
    };
    sequenceColumns = body
        .split(',')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .map((line) => line.split(RegExp(r'\s')).first.toLowerCase())
        .where((col) => !tableKeywords.contains(col))
        .toList();
    sequenceKeyColumns = sequenceColumns
        .where((c) => c == 'shop_id')
        .toList(); // PK is declared inline on shop_id

    // --- The live RPC.
    final current = File(
      '$migrationsDir/0036_split_payments_sequence_and_authz_fix.sql',
    );
    expect(current.existsSync(), isTrue, reason: 'migration 0036 must exist');
    currentSql = current.readAsStringSync().replaceAll('\r\n', '\n');
  });

  group('sale_sequences real shape (derived from 0011)', () {
    test('the counter is keyed by shop_id alone and has no id column', () {
      expect(
        sequenceColumns,
        containsAll(<String>['shop_id', 'next_value', 'updated_at']),
      );
      expect(
        sequenceColumns,
        isNot(contains('id')),
        reason:
            'sale_sequences must never gain an id column — the counter is '
            'one row per shop, so an id would be redundant and any code '
            'assuming one is wrong',
      );
      expect(
        sequenceKeyColumns,
        <String>['shop_id'],
        reason:
            'the per-shop primary key is what guarantees two businesses '
            'never share a receipt counter',
      );
    });
  });

  group('the live RPC cannot reference a nonexistent sale_sequences column', () {
    final dir = Directory(migrationsDir);
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    String fileName(File f) => f.path.split(Platform.pathSeparator).last;

    /// The leading migration number, e.g. `0036_split…` -> 36. Comparing the
    /// number rather than the whole filename matters: `'0036_x'` sorts AFTER
    /// `'0036'`, so a plain string compare would silently exclude the fix
    /// migration from its own "is this the live definition" check.
    int migrationNumber(File f) =>
        int.parse(RegExp(r'^(\d+)').firstMatch(fileName(f))!.group(1)!);

    String describe(File file, String statement, String ref) =>
        '${fileName(file)} references sale_sequences.$ref — no such column.\n'
        '  ...${statement.replaceAll(RegExp(r'\s+'), ' ').trim()}';

    void scanInto(
      Iterable<File> subset,
      Set<String> known,
      List<String> offenders,
    ) {
      for (final file in subset) {
        final sql = file.readAsStringSync().replaceAll('\r\n', '\n');
        for (final statement in saleSequencesStatements(sql)) {
          for (final ref in saleSequencesColumnRefs(statement)) {
            if (!known.contains(ref)) {
              offenders.add(describe(file, statement, ref));
            }
          }
        }
      }
    }

    test('the effective definition of create_sale_atomic is schema-clean', () {
      // The migration that DEFINES the currently live function. 0035's
      // definition is broken but is already applied and append-only, so what
      // matters is that the last word on this function — the one in force in
      // production — matches the table.
      final definers = files
          .where((f) => migrationNumber(f) <= 36)
          .where(
            (f) => f.readAsStringSync().contains(
              'function public.create_sale_atomic',
            ),
          )
          .toList();
      expect(
        definers.last.path,
        contains('0036'),
        reason:
            '0036 must remain the last migration to define this function, '
            'or the fix is not the one in force',
      );

      final offenders = <String>[];
      scanInto([definers.last], sequenceColumns.toSet(), offenders);
      expect(
        offenders,
        isEmpty,
        reason:
            'sale_sequences only ever has (${sequenceColumns.join(', ')}). '
            'Referencing anything else fails at runtime with PostgrestException '
            '42703 and breaks every cloud sale:\n${offenders.join('\n')}',
      );
    });

    test('no forward migration reintroduces an invented column', () {
      // Everything from 0036 onward is unapplied-or-new and must be clean on
      // its own, so the next person to add a migration cannot reopen this.
      final forward = files.where((f) => migrationNumber(f) >= 36).toList();
      expect(forward, isNotEmpty, reason: 'the fix migration must exist');

      final offenders = <String>[];
      scanInto(forward, sequenceColumns.toSet(), offenders);
      expect(
        offenders,
        isEmpty,
        reason:
            'sale_sequences only ever has (${sequenceColumns.join(', ')}):\n'
            '${offenders.join('\n')}',
      );
    });

    test('0035’s broken reference stays visible and stays superseded', () {
      // 0035 is already applied in production, so it must NOT be edited. What
      // must hold is that its defect is recorded here rather than quietly
      // forgotten, and that 0036 drops the exact signature 0035 introduced.
      final broken = File('$migrationsDir/0035_split_payments.sql');
      expect(broken.existsSync(), isTrue);
      final offenders = <String>[];
      scanInto([broken], sequenceColumns.toSet(), offenders);
      expect(
        offenders.any((o) => o.contains('sale_sequences.id')),
        isTrue,
        reason:
            '0035 should still document the shape that caused the outage; '
            'if this ever goes green, 0035 was edited and the history of the '
            'incident was lost',
      );

      expect(
        currentSql,
        contains(
          'drop function if exists public.create_sale_atomic(\n'
          '  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb\n'
          ')',
        ),
        reason:
            'the broken overload must be dropped, not left in the catalog '
            'as a second candidate for PostgREST to pick',
      );
    });

    test('the live RPC allocates the receipt from the per-shop counter', () {
      // A global-sequence assumption would show up as an `id` predicate here.
      expect(currentSql, contains('on conflict (shop_id) do nothing'));
      expect(
        currentSql,
        contains(
          'select next_value into v_new_stock from public.sale_sequences '
          'where shop_id = p_shop_id for update',
        ),
        reason:
            'the counter row must be row-locked, or concurrent sales race '
            'and reuse a receipt number',
      );
      expect(currentSql, contains('returning next_value into v_new_stock'));
    });
  });

  group('the live RPC keeps the 0034 guarantees 0035 dropped', () {
    test('rejects a caller who is not a member of the shop', () {
      expect(
        currentSql,
        contains('if not public.is_shop_member(p_shop_id) then'),
        reason:
            'SECURITY DEFINER without a membership check would let any '
            'authenticated user sell into any shop',
      );
      expect(currentSql, contains("raise exception 'FORBIDDEN'"));
    });

    test('pins search_path', () {
      expect(
        currentSql,
        contains('set search_path = public'),
        reason:
            'a SECURITY DEFINER function without a pinned search_path is '
            'search_path hijackable',
      );
    });

    test('labels the receipt with the shop prefix, not a hardcoded BF-', () {
      expect(
        currentSql,
        contains('v_prefix := public.shop_receipt_prefix(p_shop_id)'),
        reason:
            'hardcoding BF- makes a Food Truck receipt indistinguishable '
            'from a Cafe one',
      );
      expect(currentSql, isNot(contains("v_receipt := 'BF-'")));
    });

    test('still deducts stock and writes the stock movement ledger', () {
      // 0035 omitted this block entirely: a sale would have moved no stock and
      // left no audit row.
      expect(
        currentSql,
        contains('set stock_quantity = stock_quantity - v_quantity'),
        reason: 'a cloud sale must decrement the stock row it sold from',
      );
      expect(currentSql, contains('INSUFFICIENT_STOCK'));
      expect(currentSql, contains('insert into public.stock_movements'));
      expect(
        currentSql,
        contains("'SALE', -v_quantity"),
        reason: 'the movement must record the negative quantity actually sold',
      );
    });

    test('keeps the 0011/0034 input validation', () {
      expect(currentSql, contains('negative money'));
      expect(currentSql, contains('EMPTY_CART'));
      expect(currentSql, contains('MISSING_CUSTOMER'));
      expect(currentSql, contains('CUSTOMER_NOT_FOUND'));
      expect(currentSql, contains('INACTIVE_CUSTOMER'));
    });
  });

  group('split-payment rules', () {
    test('legs must sum to the charged total', () {
      expect(currentSql, contains("v_leg_sum <> p_total_paise"));
      expect(currentSql, contains("raise exception 'SPLIT_PAYMENT_MISMATCH'"));
    });

    test('a BANK leg can never be persisted', () {
      // The reject list is the whole set of allowed legs, so asserting on it
      // is what pins BANK out of the split path.
      final match = RegExp(
        r"if v_leg_method not in \('([A-Z]*(?:','[A-Z]*)*)'\) then",
      ).firstMatch(currentSql);
      expect(match, isNotNull, reason: 'the leg method allow-list must exist');
      final allowed = match!
          .group(1)!
          .split("','")
          .map((s) => s.replaceAll("'", '').trim())
          .toSet();
      expect(
        allowed,
        <String>{'CASH', 'UPI'},
        reason: 'Bank is not a user-facing option and must not be storable',
      );
      expect(allowed, isNot(contains('BANK')));
    });

    test('a zero or negative leg is rejected', () {
      expect(currentSql, contains('non-positive split leg'));
      expect(currentSql, contains('v_leg_paise <= 0'));
    });

    test('a split sale stores NULL in sales.payment_method', () {
      // The header has no single instrument; the legs are the record. Storing
      // a method here would double-count a split sale in single-method
      // reports.
      expect(
        currentSql,
        contains(
          'case when p_payments is not null then null else p_payment_method end',
        ),
      );
    });

    test('legs are validated before anything is written', () {
      final validateAt = currentSql.indexOf('SPLIT_PAYMENT_MISMATCH');
      final firstWriteAt = currentSql.indexOf(
        'insert into public.sale_sequences',
      );
      expect(validateAt, isNot(-1));
      expect(
        validateAt,
        lessThan(firstWriteAt),
        reason:
            'validating after the receipt/stock writes would consume a '
            'receipt number and deduct stock for a sale that then aborts',
      );
    });

    test('a credit sale cannot carry payment legs', () {
      expect(currentSql, contains('credit sale cannot carry payment legs'));
    });

    test('a single-method PAID sale is unchanged, BANK still readable', () {
      expect(
        currentSql,
        contains("p_payment_method not in ('CASH','UPI','BANK')"),
        reason:
            'historic BANK sales stay valid — only the SPLIT path bans BANK',
      );
    });
  });

  group('one signature, not two overloads', () {
    test('both prior overloads are dropped before the new one is created', () {
      // CREATE OR REPLACE with a new parameter list silently creates a second
      // overload instead of replacing, which is how 0035 left two candidates
      // for PostgREST to choose between.
      final drops = RegExp(
        r'drop function if exists public\.create_sale_atomic\(([^)]*)\)',
        dotAll: true,
      ).allMatches(currentSql).map((m) => m.group(1)!.split(',').length);
      expect(
        drops.toList(),
        containsAll(<int>[8, 9]),
        reason:
            'both the 8-arg (0034) and 9-arg (0035) overloads must be '
            'dropped so exactly one candidate remains',
      );
    });

    test('p_payments defaults to null so pre-split clients still resolve', () {
      expect(
        currentSql,
        contains('p_payments jsonb default null'),
        reason:
            'every pre-0035 build omits the split key entirely; without a '
            'default it would get "function not found"',
      );
    });

    test('execute is granted on the surviving signature', () {
      expect(
        currentSql,
        contains(
          'grant execute on function public.create_sale_atomic(\n'
          '  uuid, uuid, integer, integer, integer, text, text, jsonb, jsonb\n'
          ') to authenticated',
        ),
      );
    });
  });

  group('sale_payments shop isolation (0035 created it with no RLS)', () {
    test('RLS is enabled on the table', () {
      expect(
        currentSql,
        contains('alter table public.sale_payments enable row level security'),
      );
    });

    test(
      'a leg is reachable only through a sale in a shop the caller is in',
      () {
        final policy = RegExp(
          r'create policy sale_payments_all_own_shop.*?;',
          dotAll: true,
        ).firstMatch(currentSql);
        expect(policy, isNotNull, reason: 'the isolation policy must exist');
        final body = policy!.group(0)!;
        expect(body, contains('for all'));
        expect(body, contains('public.is_shop_member(s.shop_id)'));
        expect(
          body,
          contains('with check'),
          reason:
              'without a WITH CHECK a member of one shop could insert a leg '
              'onto another shop’s sale',
        );
      },
    );

    test(
      'isolation reads the shop off the parent sale, not a duplicated column',
      () {
        final policy = RegExp(
          r'create policy sale_payments_all_own_shop.*?;',
          dotAll: true,
        ).firstMatch(currentSql)!.group(0)!;
        expect(policy, contains('from public.sales s'));
        expect(
          policy,
          contains('s.id = sale_payments.sale_id'),
          reason:
              'the sale is the authority on which shop a leg belongs to, so '
              'a leg can never disagree with its sale',
        );
        expect(
          currentSql,
          isNot(contains('alter table public.sale_payments\n  add column')),
          reason:
              'no denormalized shop_id is added — it could drift from the sale',
        );
      },
    );
  });
}
