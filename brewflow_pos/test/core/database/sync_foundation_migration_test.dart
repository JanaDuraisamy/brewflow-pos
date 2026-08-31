import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';
import '../../generated_migrations/schema_v13.dart' as v13;

void main() {
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('v13 → v14 migration', () {
    test('preserves users/shops/staff permissions/business data; sync tables '
        'start empty and usable', () async {
      final schema = await verifier.schemaAt(13);

      final oldDb = v13.DatabaseAtV13(schema.newConnection());
      await oldDb
          .into(oldDb.shops)
          .insert(
            v13.ShopsCompanion.insert(
              id: 'shop-1',
              name: 'My Shop',
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb
          .into(oldDb.users)
          .insert(
            v13.UsersCompanion.insert(
              id: 'u1',
              email: 'o@x.co',
              isActive: const Value(1),
              createdAt: '2026-01-01T00:00:00.000Z',
              updatedAt: '2026-01-01T00:00:00.000Z',
            ),
          );
      await oldDb.customInsert(
        "UPDATE users SET role = 'OWNER', auth_user_id = 'auth-1', "
        "shop_id = 'shop-1' WHERE id = 'u1'",
      );
      await oldDb.close();

      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 14);

      // Preserved.
      expect(await db.select(db.shops).get(), hasLength(1));
      final user = await (db.select(
        db.users,
      )..where((t) => t.id.equals('u1'))).getSingle();
      expect(user.role, 'OWNER');
      expect(user.authUserId, 'auth-1');
      expect(user.shopId, 'shop-1');

      // Sync structures start empty and are usable.
      expect(await db.select(db.devices).get(), isEmpty);
      expect(await db.select(db.syncOutbox).get(), isEmpty);
      expect(await db.select(db.syncState).get(), isEmpty);

      await db
          .into(db.devices)
          .insert(
            DevicesCompanion.insert(
              id: const Value('device-a'),
              shopId: 'shop-1',
              userId: 'auth-1',
            ),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'device-a',
              shopId: 'shop-1',
              entity: 'PRODUCT',
              entityId: 'p1',
              payload: '{}',
            ),
          );
      await db
          .into(db.syncState)
          .insert(
            SyncStateCompanion.insert(deviceId: 'device-a', shopId: 'shop-1'),
          );

      expect(await db.select(db.devices).get(), hasLength(1));
      expect(await db.select(db.syncOutbox).get(), hasLength(1));
      expect(await db.select(db.syncState).get(), hasLength(1));

      await db.close();
      schema.close();
    });

    test('multiple devices for one user are valid after migration', () async {
      final schema = await verifier.schemaAt(13);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 14);

      await db
          .into(db.shops)
          .insert(
            ShopsCompanion.insert(id: const Value('shop-1'), name: 'Shop'),
          );
      for (final device in ['d1', 'd2', 'd3']) {
        await db
            .into(db.devices)
            .insert(
              DevicesCompanion.insert(
                id: Value(device),
                shopId: 'shop-1',
                userId: 'same-owner',
              ),
            );
      }
      expect(await db.select(db.devices).get(), hasLength(3));

      await db.close();
      schema.close();
    });
  });
}
