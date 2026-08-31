import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v11.dart' as v11;

/// ---------------------------------------------------------------------------
/// Owner/Staff access control — v11 → v12 migration tests (SchemaVerifier)
///
/// The v11 database is created from the exported snapshot, seeded with a
/// pre-existing user and business data, then migrated with the real strategy.
/// Verifies: existing users preserved untouched (authUserId/shopId stay NULL),
/// shops starts empty, staff_permissions usable after migration.
/// ---------------------------------------------------------------------------

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v11 → v12 migration', () {
    test(
      'preserves users/business rows; adds access-control structures',
      () async {
        final schema = await verifier.schemaAt(11);

        final oldDb = v11.DatabaseAtV11(schema.newConnection());
        await oldDb
            .into(oldDb.users)
            .insert(
              v11.UsersCompanion.insert(
                id: 'u1',
                email: 'owner@brewflow.example',
                displayName: const Value('Owner'),
                isActive: const Value(1),
                createdAt: '2026-01-01T00:00:00.000Z',
                updatedAt: '2026-01-01T00:00:00.000Z',
              ),
            );
        await oldDb.close();

        final db = AppDatabase(schema.newConnection());
        await verifier.migrateAndValidate(db, 12);

        // Existing user preserved exactly; new columns are NULL.
        final legacy = await (db.select(
          db.users,
        )..where((t) => t.id.equals('u1'))).getSingle();
        expect(legacy.email, 'owner@brewflow.example');
        expect(legacy.displayName, 'Owner');
        expect(legacy.isActive, isTrue);
        expect(legacy.role, isNull);
        expect(legacy.authUserId, isNull);
        expect(legacy.shopId, isNull);

        // Shops starts empty (created during owner bootstrap).
        expect(await db.select(db.shops).get(), isEmpty);

        // Access-control tables are usable post-migration.
        await db
            .into(db.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-1'), name: 'My Shop'),
            );
        await (db.update(db.users)..where((t) => t.id.equals('u1'))).write(
          const UsersCompanion(
            role: Value('OWNER'),
            authUserId: Value('auth-1'),
            shopId: Value('shop-1'),
          ),
        );
        await db
            .into(db.staffPermissions)
            .insert(
              StaffPermissionsCompanion.insert(
                userId: 'u1',
                permission: 'BILLING',
                enabled: const Value(true),
              ),
            );

        final linked = await (db.select(
          db.users,
        )..where((t) => t.id.equals('u1'))).getSingle();
        expect(linked.authUserId, 'auth-1');
        expect(linked.shopId, 'shop-1');
        expect(linked.role, 'OWNER');

        await db.close();
        schema.close();
      },
    );
  });
}
