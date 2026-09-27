import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v14.dart' as v14;

/// ---------------------------------------------------------------------------
/// v27 — shop-payables payment table migration gate.
///
/// The v27 step is the one place a settled-vs-unsettled bug becomes permanent:
/// `expense_payments` is the ONLY record that a payee was ever paid, and it is
/// append-only. If this step is wrong, balances are permanently wrong and there
/// is no repair that does not involve re-keying real money.
///
/// Two specific hazards this file locks down:
///
///  * **The column set must match the live table exactly.** `payee_name` was
///    added to the table *after* the v27 step was first generated. A stale
///    `drift_schema_v27.json` does not break this migration (the step calls the
///    live `schema.expensePayments` accessor, so the real DDL follows the code),
///    but it does silently poison the *next* generated step, which would offer
///    a redundant `ADD COLUMN payee_name` to devices already at v27. Asserting
///    the dumped schema agrees with the live table keeps that failure loud.
///  * **No expense row may move.** The step is purely additive: a payable is
///    settled by appending a payment, never by rewriting the expense it
///    settles. A migration that "helpfully" normalised or deleted expenses
///    would destroy the very history payments are matched against.
/// ---------------------------------------------------------------------------

Future<List<Map<String, Object?>>> _snapshot(
  GeneratedDatabase db,
  String table,
) async {
  final rows = await db.customSelect('SELECT * FROM $table ORDER BY id').get();
  return [for (final row in rows) row.data];
}

Future<String?> _ddl(GeneratedDatabase db, String table) async {
  final row = await db
      .customSelect(
        "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
        variables: [Variable.withString(table)],
      )
      .getSingleOrNull();
  return row?.data['sql'] as String?;
}

Future<Set<String>> _indexes(GeneratedDatabase db, String table) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ? "
        "AND name NOT LIKE 'sqlite_%'",
        variables: [Variable.withString(table)],
      )
      .get();
  return {for (final row in rows) row.data['name'] as String};
}

Future<Set<String>> _columns(GeneratedDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return {for (final row in rows) row.data['name'] as String};
}

/// A minimal database stamped at v26: one shop, one unpaid expense, and no
/// `expense_payments` table yet — the exact state a shipping install is in.
class V26Fixture {
  V26Fixture(this.db, this.reopen, this.expenseBefore);
  final v14.DatabaseAtV14 db;
  final DatabaseConnection Function() reopen;
  final List<Map<String, Object?>> expenseBefore;
}

Future<V26Fixture> buildV26(DatabaseConnection Function() connect) async {
  final connection = connect();
  final db = v14.DatabaseAtV14(connection);

  await db
      .into(db.shops)
      .insert(
        v14.ShopsCompanion.insert(
          id: 'shop-cafe',
          name: 'Cafe',
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ),
      );

  // v14 `expenses` has no shop_id column; that is added by a later step. The row
  // is inserted with raw SQL so it survives untouched into v27.
  await db.customStatement(
    'INSERT INTO expenses (id, name, amount_paise, category, payment_method, '
    'payment_status, expense_date, note, is_active, created_at, updated_at) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [
      'e-milk-1',
      'Milk',
      70000,
      'SUPPLIES',
      'CASH',
      'NOT_PAID',
      '2026-08-10T00:00:00.000Z',
      'Weekly milk',
      1,
      '2026-08-10T00:00:00.000Z',
      '2026-08-10T00:00:00.000Z',
    ],
  );
  await db.customStatement(
    'INSERT INTO expenses (id, name, amount_paise, category, payment_method, '
    'payment_status, expense_date, note, is_active, created_at, updated_at) '
    'VALUES (?,?,?,?,?,?,?,?,?,?,?)',
    [
      'e-milk-2',
      'milk',
      90000,
      'SUPPLIES',
      'CASH',
      'NOT_PAID',
      '2026-08-11T00:00:00.000Z',
      null,
      1,
      '2026-08-11T00:00:00.000Z',
      '2026-08-11T00:00:00.000Z',
    ],
  );

  final before = await _snapshot(db, 'expenses');
  await db.customStatement('PRAGMA user_version = 26');
  return V26Fixture(db, connect, before);
}

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  test('a v26 database has no expense_payments table yet', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV26(schema.newConnection);
    expect(await _ddl(fixture.db, 'expense_payments'), isNull);
    await fixture.db.close();
  });

  test(
    'the wired v26 -> v27 step creates the payment table with payee_name',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildV26(schema.newConnection);
      await fixture.db.close();

      final db = AppDatabase(fixture.reopen());
      await db.customSelect('SELECT 1').get();

      // The table exists, and carries the display name that the grouping key
      // cannot recover. Losing this column is the specific regression this test
      // exists to catch: every device would then show "milk" instead of "Milk".
      final ddl = await _ddl(db, 'expense_payments');
      expect(ddl, isNot(isNull), reason: 'v27 must create expense_payments');
      expect(
        await _columns(db, 'expense_payments'),
        containsAll(<String>{
          'id',
          'shop_id',
          'payee_key',
          'payee_name',
          'amount_paise',
          'payment_method',
          'note',
          'paid_at',
          'reversed',
          'reversed_at',
          'created_at',
          'updated_at',
        }),
      );

      // No stored balance: the whole point is that dues are derived at read time
      // so every device reaches the same number from the same rows.
      final columns = await _columns(db, 'expense_payments');
      expect(columns, isNot(contains('remaining_paise')));
      expect(columns, isNot(contains('balance_paise')));
      expect(columns, isNot(contains('total_paise')));

      expect(
        await _indexes(db, 'expense_payments'),
        containsAll(<String>{
          'idx_expense_payments_shop',
          'idx_expense_payments_payee',
          'idx_expense_payments_paid_at',
        }),
      );

      await db.close();
    },
  );

  test(
    'the v26 -> v27 step leaves every existing expense byte-identical',
    () async {
      final schema = await verifier.schemaAt(14);
      final fixture = await buildV26(schema.newConnection);
      await fixture.db.close();

      final db = AppDatabase(fixture.reopen());
      await db.customSelect('SELECT 1').get();

      // Append-only discipline, enforced at the schema level: adding the ability
      // to record a payment must not disturb the expenses it settles. If this
      // ever differs, someone's migration is rewriting history.
      expect(await _snapshot(db, 'expenses'), fixture.expenseBefore);
      expect(fixture.expenseBefore, hasLength(2));

      final status = await db
          .customSelect(
            "SELECT payment_status FROM expenses WHERE id = 'e-milk-1'",
          )
          .getSingle();
      expect(
        status.data['payment_status'],
        'NOT_PAID',
        reason:
            'settling a payable must not rewrite the expense payment status',
      );

      // A brand-new table starts empty — the migration backfills nothing, because
      // there is no honest way to invent historical payments.
      expect(await _snapshot(db, 'expense_payments'), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);

      await db.close();
    },
  );

  test('the wired step is a no-op on an already-migrated database', () async {
    final schema = await verifier.schemaAt(14);
    final fixture = await buildV26(schema.newConnection);
    await fixture.db.close();

    final first = AppDatabase(fixture.reopen());
    await first.customSelect('SELECT 1').get();
    final ddl = await _ddl(first, 'expense_payments');
    final expenses = await _snapshot(first, 'expenses');
    await first.close();

    // Re-opening must not re-run the step or add a second payee_name column.
    final second = AppDatabase(fixture.reopen());
    await second.customSelect('SELECT 1').get();
    expect(await _ddl(second, 'expense_payments'), ddl);
    expect(await _snapshot(second, 'expenses'), expenses);
    expect(
      (await second.customSelect('PRAGMA user_version').getSingle())
          .data
          .values
          .first,
      AppConstants.databaseSchemaVersion,
    );

    await second.close();
  });

  test(
    'payee_name survives a real payment round-trip on the live schema',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(id: const Value('shop-cafe'), name: 'Cafe'),
          );

      await db
          .into(db.expensePayments)
          .insert(
            ExpensePaymentsCompanion.insert(
              id: const Value('pay-1'),
              shopId: const Value('shop-cafe'),
              payeeKey: 'milk',
              payeeName: const Value('Milk'),
              amountPaise: 100000,
              paymentMethod: 'UPI',
              paidAt: DateTime.utc(2026, 8, 12),
            ),
          );

      final row = await db.select(db.expensePayments).getSingle();
      // The normalised key drives grouping; the display name drives the UI.
      expect(row.payeeKey, 'milk');
      expect(row.payeeName, 'Milk');
      expect(row.amountPaise, 100000);
      expect(row.reversed, isFalse);
      expect(row.reversedAt, isNull);
    },
  );
}
