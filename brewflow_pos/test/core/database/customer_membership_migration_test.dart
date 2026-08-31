import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v10.dart' as v10;

/// ---------------------------------------------------------------------------
/// Customer membership — v10 → v11 migration tests (drift SchemaVerifier)
///
/// The v10 database is created from the exported drift schema snapshot, seeded
/// with a pre-existing customer, then migrated with the app's real migration
/// strategy. [SchemaVerifier.migrateAndValidate] also compares the migrated
/// schema semantically against a fresh v11 database.
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v10 → v11 migration', () {
    test(
      'adds membership columns; every existing customer stays a non-member',
      () async {
        final schema = await verifier.schemaAt(10);

        final oldDb = v10.DatabaseAtV10(schema.newConnection());
        await oldDb
            .into(oldDb.customers)
            .insert(
              v10.CustomersCompanion.insert(
                id: 'c1',
                name: 'Lakshmi',
                phone: const Value('9876543210'),
                isActive: const Value(1),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 11);

        // The current customers row type requires whatsapp_status (v13); the
        // migrated table only has the v11 columns, so read explicitly.
        final customer =
            await (db.selectOnly(db.customers)
                  ..addColumns([
                    db.customers.name,
                    db.customers.phone,
                    db.customers.membershipActive,
                    db.customers.membershipFeePaise,
                  ])
                  ..where(db.customers.id.equals('c1')))
                .getSingle();
        expect(customer.read(db.customers.name), 'Lakshmi');
        expect(customer.read(db.customers.phone), '9876543210');

        // Additive defaults: existing customers land as non-members with no
        // fee snapshot.
        expect(customer.read(db.customers.membershipActive), false);
        expect(customer.read(db.customers.membershipFeePaise), isNull);

        // New members can be enrolled after the migration (explicit column
        // write keeps the read below on the v11-safe surface).
        await db.customUpdate(
          'UPDATE customers SET membership_active = 1, '
          'membership_fee_paise = 5000 WHERE id = ?',
          variables: [Variable.withString('c1')],
        );
        final enrolled =
            await (db.selectOnly(db.customers)
                  ..addColumns([
                    db.customers.membershipActive,
                    db.customers.membershipFeePaise,
                  ])
                  ..where(db.customers.id.equals('c1')))
                .getSingle();
        expect(enrolled.read(db.customers.membershipActive), true);
        expect(enrolled.read(db.customers.membershipFeePaise), 5000);

        await db.close();
        schema.close();
      },
    );
  });
}
