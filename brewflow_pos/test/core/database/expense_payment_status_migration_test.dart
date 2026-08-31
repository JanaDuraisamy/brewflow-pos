import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/daos/expenses_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v8.dart' as v8;

/// ---------------------------------------------------------------------------
/// Expense payment status — v8 → v9 migration tests (drift SchemaVerifier)
///
/// The v8 database is created from the exported drift schema snapshot, seeded
/// with realistic v8-era expenses (plus one category/product to prove rows
/// outside the migration's scope survive untouched), then migrated with the
/// app's real migration strategy. [SchemaVerifier.migrateAndValidate] also
/// compares the migrated schema semantically against a fresh v9 database
/// (columns, constraints, foreign keys and indexes must match exactly).
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v8 → v9 migration', () {
    test(
      'preserves every existing row and defaults payment status to PAID',
      () async {
        final schema = await verifier.schemaAt(8);

        final oldDb = v8.DatabaseAtV8(schema.newConnection());
        await oldDb
            .into(oldDb.categories)
            .insert(
              v8.CategoriesCompanion.insert(
                id: 'cat-1',
                name: 'Beverages',
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.products)
            .insert(
              v8.ProductsCompanion.insert(
                id: 'p1',
                categoryId: 'cat-1',
                name: 'Filter Coffee',
                sellingPricePaise: 12000,
                costPricePaise: Value(8000),
                stockQuantity: Value(7),
                isActive: Value(1),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.expenses)
            .insert(
              v8.ExpensesCompanion.insert(
                id: 'e1',
                name: 'Coffee beans',
                amountPaise: 25500,
                category: 'SUPPLIES',
                paymentMethod: 'UPI',
                expenseDate: '2026-08-10T00:00:00.000Z',
                note: Value('Weekly order'),
                isActive: Value(1),
                createdAt: '2026-08-10T08:00:00.000Z',
                updatedAt: '2026-08-10T08:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.expenses)
            .insert(
              v8.ExpensesCompanion.insert(
                id: 'e2',
                name: 'Printer repair',
                amountPaise: 1200,
                category: 'MAINTENANCE',
                paymentMethod: 'CASH',
                expenseDate: '2026-08-08T00:00:00.000Z',
                note: Value(null),
                isActive: Value(0),
                createdAt: '2026-08-08T10:00:00.000Z',
                updatedAt: '2026-08-08T10:00:00.000Z',
              ),
            );
        await oldDb.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 9);

        final expenses = await (db.select(
          db.expenses,
        )..orderBy([(t) => OrderingTerm.asc(t.id)])).get();
        expect(expenses, hasLength(2));

        // Every v8-era expense is treated as settled: payment_status = PAID.
        final first = expenses.first;
        expect(first.id, 'e1');
        expect(first.name, 'Coffee beans');
        expect(first.amountPaise, 25500);
        expect(first.category, 'SUPPLIES');
        expect(first.paymentMethod, 'UPI');
        expect(first.paymentStatus, 'PAID');
        expect(first.note, 'Weekly order');
        expect(first.isActive, true);

        final second = expenses[1];
        expect(second.id, 'e2');
        expect(second.name, 'Printer repair');
        expect(second.amountPaise, 1200);
        expect(second.paymentStatus, 'PAID');
        expect(second.isActive, false);

        // Rows outside the migration's scope survive untouched.
        final product = await (db.select(
          db.products,
        )..where((t) => t.id.equals('p1'))).getSingle();
        expect(product.name, 'Filter Coffee');
        expect(product.sellingPricePaise, 12000);
        expect(product.costPricePaise, 8000);

        await db.close();
        schema.close();
      },
    );

    test('v9 additions work after migration: NOT_PAID expenses and payable '
        'aggregation', () async {
      final schema = await verifier.schemaAt(8);

      final oldDb = v8.DatabaseAtV8(schema.newConnection());
      await oldDb
          .into(oldDb.expenses)
          .insert(
            v8.ExpensesCompanion.insert(
              id: 'e1',
              name: 'Coffee beans',
              amountPaise: 25500,
              category: 'SUPPLIES',
              paymentMethod: 'UPI',
              expenseDate: '2026-08-10T00:00:00.000Z',
              note: Value(null),
              isActive: Value(1),
              createdAt: '2026-08-10T08:00:00.000Z',
              updatedAt: '2026-08-10T08:00:00.000Z',
            ),
          );
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 9);

      // New expenses can be recorded as NOT_PAID and become shop payable.
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value('e2'),
              name: 'Rent',
              amountPaise: 5000000,
              category: 'RENT',
              paymentMethod: 'BANK',
              paymentStatus: Value('NOT_PAID'),
              expenseDate: DateTime.utc(2026, 8, 1),
            ),
          );
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value('e3'),
              name: 'Deferred supply bill',
              amountPaise: 30000,
              category: 'SUPPLIES',
              paymentMethod: 'CASH',
              paymentStatus: Value('NOT_PAID'),
              expenseDate: DateTime.utc(2026, 8, 2),
              isActive: const Value(false),
            ),
          );

      // payablePaise sums active NOT_PAID expenses only: e2 qualifies,
      // e1 is PAID and e3 is NOT_PAID but inactive.
      final dao = ExpensesDao(db);
      expect(await dao.payablePaise(), 5000000);

      // Existing migrated rows stay PAID unless explicitly updated.
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: Value('e4'),
              name: 'Utilities bill',
              amountPaise: 4000,
              category: 'UTILITIES',
              paymentMethod: 'UPI',
              expenseDate: DateTime.utc(2026, 8, 3),
            ),
          );
      final defaulted = await (db.select(
        db.expenses,
      )..where((t) => t.id.equals('e4'))).getSingle();
      expect(defaulted.paymentStatus, 'PAID');

      await db.close();
      schema.close();
    });
  });
}
