import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v9.dart' as v9;

/// ---------------------------------------------------------------------------
/// Sales payment status — v9 → v10 migration tests (drift SchemaVerifier)
///
/// The v9 database is created from the exported drift schema snapshot, seeded
/// with realistic v9-era sales (one customer-linked, one walk-in), then
/// migrated with the app's real migration strategy.
/// [SchemaVerifier.migrateAndValidate] also compares the migrated schema
/// semantically against a fresh v10 database (columns, constraints, foreign
/// keys and indexes must match exactly).
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v9 → v10 migration', () {
    test(
      'preserves every existing row and defaults payment status to PAID',
      () async {
        final schema = await verifier.schemaAt(9);

        final oldDb = v9.DatabaseAtV9(schema.newConnection());
        await oldDb
            .into(oldDb.categories)
            .insert(
              v9.CategoriesCompanion.insert(
                id: 'cat-1',
                name: 'Beverages',
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.customers)
            .insert(
              v9.CustomersCompanion.insert(
                id: 'c1',
                name: 'Lakshmi',
                phone: Value('9876543210'),
                isActive: Value(1),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.sales)
            .insert(
              v9.SalesCompanion.insert(
                id: 's1',
                customerId: Value('c1'),
                receiptNumber: 'BF-000001',
                subtotalPaise: 24000,
                totalPaise: 24000,
                paymentMethod: 'UPI',
                createdAt: '2026-01-02T10:00:00.000Z',
                updatedAt: '2026-01-02T10:00:00.000Z',
              ),
            );
        await oldDb
            .into(oldDb.sales)
            .insert(
              v9.SalesCompanion.insert(
                id: 's2',
                customerId: Value(null),
                receiptNumber: 'BF-000002',
                subtotalPaise: 8000,
                totalPaise: 8000,
                paymentMethod: 'CASH',
                createdAt: '2026-01-03T11:00:00.000Z',
                updatedAt: '2026-01-03T11:00:00.000Z',
              ),
            );
        await oldDb.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 10);

        // Read only the columns that exist at the v10 migration target. (The
        // latest schema table gains new NOT NULL columns in later versions —
        // here e.g. sales.voided — so mapping full rows of an older schema
        // would hit a null check on a column the v10 database lacks.)
        final rows =
            await (db.selectOnly(db.sales)
                  ..addColumns([
                    db.sales.id,
                    db.sales.receiptNumber,
                    db.sales.customerId,
                    db.sales.subtotalPaise,
                    db.sales.totalPaise,
                    db.sales.paymentMethod,
                    db.sales.paymentStatus,
                  ])
                  ..orderBy([OrderingTerm.asc(db.sales.id)]))
                .get();
        expect(rows, hasLength(2));

        // Every v9-era sale is treated as paid: payment_status = PAID.
        final first = rows.first;
        expect(first.read(db.sales.id), 's1');
        expect(first.read(db.sales.receiptNumber), 'BF-000001');
        expect(first.read(db.sales.customerId), 'c1');
        expect(first.read(db.sales.subtotalPaise), 24000);
        expect(first.read(db.sales.totalPaise), 24000);
        expect(first.read(db.sales.paymentMethod), 'UPI');
        expect(first.read(db.sales.paymentStatus), 'PAID');

        final second = rows[1];
        expect(second.read(db.sales.id), 's2');
        expect(second.read(db.sales.receiptNumber), 'BF-000002');
        expect(second.read(db.sales.customerId), isNull);
        expect(second.read(db.sales.paymentMethod), 'CASH');
        expect(second.read(db.sales.paymentStatus), 'PAID');

        await db.close();
        schema.close();
      },
    );

    test('v10 additions work after migration: NOT_PAID sales with a NULL '
        'payment method, and PAID remains the default', () async {
      final schema = await verifier.schemaAt(9);

      final oldDb = v9.DatabaseAtV9(schema.newConnection());
      await oldDb
          .into(oldDb.customers)
          .insert(
            v9.CustomersCompanion.insert(
              id: 'c1',
              name: 'Lakshmi',
              phone: Value('9876543210'),
              isActive: Value(1),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 10);

      // A credit sale: no payment method, NOT_PAID status.
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: const Value('s1'),
              customerId: Value('c1'),
              receiptNumber: 'BF-000001',
              subtotalPaise: 30000,
              totalPaise: 30000,
              paymentMethod: const Value(null),
              paymentStatus: const Value('NOT_PAID'),
              createdAt: Value(DateTime.utc(2026, 8, 1, 10)),
              updatedAt: Value(DateTime.utc(2026, 8, 1, 10)),
            ),
          );

      final credit =
          await (db.selectOnly(db.sales)
                ..addColumns([
                  db.sales.id,
                  db.sales.paymentStatus,
                  db.sales.paymentMethod,
                  db.sales.totalPaise,
                ])
                ..where(db.sales.id.equals('s1')))
              .getSingle();
      expect(credit.read(db.sales.paymentStatus), 'NOT_PAID');
      expect(credit.read(db.sales.paymentMethod), isNull);
      expect(credit.read(db.sales.totalPaise), 30000);

      // A new cash sale without an explicit status defaults to PAID.
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              id: const Value('s2'),
              receiptNumber: 'BF-000002',
              subtotalPaise: 12000,
              totalPaise: 12000,
              paymentMethod: const Value('CASH'),
              createdAt: Value(DateTime.utc(2026, 8, 2, 10)),
              updatedAt: Value(DateTime.utc(2026, 8, 2, 10)),
            ),
          );

      final paid =
          await (db.selectOnly(db.sales)
                ..addColumns([db.sales.paymentStatus, db.sales.paymentMethod])
                ..where(db.sales.id.equals('s2')))
              .getSingle();
      expect(paid.read(db.sales.paymentStatus), 'PAID');
      expect(paid.read(db.sales.paymentMethod), 'CASH');

      // The schema still rejects unknown status values.
      await expectLater(
        db
            .into(db.sales)
            .insert(
              SalesCompanion.insert(
                id: const Value('s3'),
                receiptNumber: 'BF-000003',
                subtotalPaise: 1000,
                totalPaise: 1000,
                paymentMethod: const Value('CASH'),
                paymentStatus: const Value('UNKNOWN'),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      await db.close();
      schema.close();
    });
  });
}
