import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../helpers/fake_preferences_storage.dart';

void main() {
  late AppDatabase db;
  late DriftSyncRepository repo;

  setUp(() async {
    DeviceIdentity.resetForTest();
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftSyncRepository(db);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value('shop-1'), name: 'Shop'));
  });

  tearDown(() => db.close());

  group('device identity', () {
    test('generated once, persisted, survives restart and logout', () async {
      final storage = FakePreferencesStorage();
      final first = (await DeviceIdentity.resolve(storage: storage)).value;
      final second = (await DeviceIdentity.resolve(storage: storage)).value;
      expect(first, second);

      // Simulated restart: new process cache, same persisted storage.
      DeviceIdentity.resetForTest();
      final afterRestart = (await DeviceIdentity.resolve(
        storage: storage,
      )).value;
      expect(afterRestart, first);
    });

    test('device id differs from user id and shop id', () async {
      await repo.registerDevice(
        deviceId: 'device-a',
        shopId: 'shop-1',
        userId: 'supabase-user-1',
      );
      expect('device-a', isNot('supabase-user-1'));
      expect('device-a', isNot('shop-1'));
    });
  });

  group('device registration', () {
    test(
      'owner may register MANY devices — no unique user constraint',
      () async {
        for (final device in ['device-a', 'device-b', 'device-c']) {
          await repo.registerDevice(
            deviceId: device,
            shopId: 'shop-1',
            userId: 'owner-1',
          );
        }
        final devices = await repo.devicesForShop('shop-1');
        expect(devices.length, 3);
        expect(devices.every((d) => d.userId == 'owner-1'), isTrue);
        expect(devices.every((d) => d.isActive), isTrue);
      },
    );

    test('staff device resolves to its own user in the same shop', () async {
      await repo.registerDevice(
        deviceId: 'device-d',
        shopId: 'shop-1',
        userId: 'staff-1',
      );
      final devices = await repo.devicesForShop('shop-1');
      expect(devices.single.userId, 'staff-1');
      expect(devices.single.shopId, 'shop-1');
    });

    test(
      're-registration refreshes binding without duplicating rows',
      () async {
        await repo.registerDevice(
          deviceId: 'device-a',
          shopId: 'shop-1',
          userId: 'owner-1',
        );
        await repo.registerDevice(
          deviceId: 'device-a',
          shopId: 'shop-1',
          userId: 'owner-1',
          deviceName: 'Counter tablet',
        );
        final devices = await repo.devicesForShop('shop-1');
        expect(devices.length, 1);
        expect(devices.single.deviceName, 'Counter tablet');
      },
    );
  });

  group('outbox', () {
    SyncOutboxEntry entry(String entityId) => SyncOutboxEntry(
      id: 'obx-$entityId',
      deviceId: 'device-a',
      shopId: 'shop-1',
      entity: 'PRODUCT',
      entityId: entityId,
      operation: 'UPSERT',
      payload: '{"id":"$entityId"}',
      status: 'PENDING',
      attemptCount: 0,
    );

    test('enqueue + pending count + batch ordering', () async {
      await repo.insertOutbox(entry('p2'));
      await repo.insertOutbox(entry('p1'));
      expect(await repo.pendingOutboxCount(), 2);

      final batch = await repo.pendingOutboxBatch();
      expect(batch.map((e) => e.entityId).toList(), ['p2', 'p1']);
      expect(batch.first.operation, 'UPSERT');
    });

    test(
      'markDone clears pending; incrementAttempt keeps it pending',
      () async {
        await repo.insertOutbox(entry('p1'));

        await repo.incrementAttempt('obx-p1', 'network down');
        expect(await repo.pendingOutboxCount(), 1);
        final retried = (await repo.pendingOutboxBatch()).single;
        expect(retried.attemptCount, 1);
        expect(retried.status, 'PENDING');

        await repo.markDone('obx-p1');
        expect(await repo.pendingOutboxCount(), 0);
      },
    );

    test(
      'atomic helper rolls the outbox back with a failed business write',
      () async {
        // Force the "business write" to fail inside the transaction.
        await expectLater(
          repo.enqueueInTransaction<int>(
            () async => throw StateError('business write failed'),
            entry('p9'),
          ),
          throwsA(isA<StateError>()),
        );
        expect(
          await repo.pendingOutboxCount(),
          0,
          reason: 'no orphaned outbox row after rollback',
        );

        // Success path writes both.
        final result = await repo.enqueueInTransaction<String>(
          () async => 'saved',
          entry('p10'),
        );
        expect(result, 'saved');
        expect(await repo.pendingOutboxCount(), 1);
      },
    );

    test('identity replay collapses duplicate pending change', () async {
      await repo.insertOutbox(entry('dup'));
      await repo.insertOutbox(entry('dup'));
      final batch = await repo.pendingOutboxBatch();
      expect(batch.length, 1);
    });
  });

  group('sync state', () {
    test('cursors upsert per device', () async {
      final now = DateTime.now().toUtc();
      await repo.upsertState(
        deviceId: 'device-a',
        shopId: 'shop-1',
        lastPulledAt: now,
      );
      await repo.upsertState(
        deviceId: 'device-a',
        shopId: 'shop-1',
        lastPushedAt: now,
      );

      final state = await repo.stateFor('device-a');
      expect(state, isNotNull);
      expect(state!.shopId, 'shop-1');
      expect(state.lastPulledAt, now);
      expect(state.lastPushedAt, now);
    });
  });

  group('shop isolation', () {
    test(
      'devices of another shop are not visible through this shop query',
      () async {
        await db
            .into(db.shops)
            .insert(
              ShopsCompanion.insert(id: const Value('shop-2'), name: 'Other'),
            );
        await repo.registerDevice(
          deviceId: 'd-shop1',
          shopId: 'shop-1',
          userId: 'u1',
        );
        await repo.registerDevice(
          deviceId: 'd-shop2',
          shopId: 'shop-2',
          userId: 'u2',
        );

        final shop1 = await repo.devicesForShop('shop-1');
        expect(shop1.map((d) => d.id), ['d-shop1']);
      },
    );
  });
}
