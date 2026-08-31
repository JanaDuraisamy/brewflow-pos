import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v12.dart' as v12;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v12 → v13 migration', () {
    test(
      'preserves customers and phones; defaults whatsapp_status to UNKNOWN',
      () async {
        final schema = await verifier.schemaAt(12);

        final oldDb = v12.DatabaseAtV12(schema.newConnection());
        await oldDb
            .into(oldDb.customers)
            .insert(
              v12.CustomersCompanion.insert(
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
        await verifier.migrateAndValidate(db, 14);

        final lakshmi = await (db.select(
          db.customers,
        )..where((t) => t.id.equals('c1'))).getSingle();
        expect(lakshmi.phone, '9876543210');
        expect(lakshmi.name, 'Lakshmi');
        expect(lakshmi.whatsappStatus, 'UNKNOWN');

        // Status is writable for a future real provider.
        await (db.update(db.customers)..where((t) => t.id.equals('c1'))).write(
          const CustomersCompanion(whatsappStatus: Value('VERIFIED')),
        );
        final verified = await (db.select(
          db.customers,
        )..where((t) => t.id.equals('c1'))).getSingle();
        expect(verified.whatsappStatus, 'VERIFIED');

        // Unknown values fall back to UNKNOWN when parsed by the domain.
        expect(WhatsAppStatus.fromDbValue('WHATEVER'), WhatsAppStatus.unknown);

        await db.close();
        schema.close();
      },
    );
  });
}
