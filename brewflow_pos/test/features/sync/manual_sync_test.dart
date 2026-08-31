import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_remote_master_data_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('manual sync', () {
    test('refresh triggers sync and pending reaches DONE', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final cloud = FakeRemoteStore();
      final gateway = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: 'shop-1',
      );
      addTearDown(db.close);

      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('shop-1'), name: 'S'));
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              email: 'a@b.co',
              authUserId: Value('u1'),
              shopId: Value('shop-1'),
              role: Value('OWNER'),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          deviceIdProvider.overrideWith((ref) => 'dev-1'),
          remoteDeviceGatewayProvider.overrideWithValue(gateway),
          syncGatewayProvider.overrideWithValue(gateway),
          syncEngineProvider.overrideWith(
            (ref) => SyncEngine(
              DriftSyncRepository(db),
              gateway,
              LocalMasterDataApplier(db),
            ),
          ),
          connectivityServiceProvider.overrideWithValue(
            fakeConnectivityServiceOnline(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      // Wait for any background sync from the initial bootstrap to finish
      await Future<void>.delayed(const Duration(milliseconds: 400));

      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(id: Value('cat-1'), name: 'TestCat'),
          );
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'dev-1',
              shopId: 'shop-1',
              entity: 'CATEGORY',
              entityId: 'cat-1',
              payload:
                  '{"id":"cat-1","shopId":"shop-1","name":"TestCat","isActive":true,"createdAt":"2026-01-01T00:00:00.000Z"}',
            ),
          );
      expect(
        await db
            .select(db.syncOutbox)
            .get()
            .then((rows) => rows.where((r) => r.status == 'PENDING').length),
        1,
      );

      // Ensure no background sync is still running before manual sync
      for (var i = 0; i < 20; i++) {
        if (!container.read(syncEngineProvider).isRunning) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await container.read(syncStatusProvider.notifier).syncNow();
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(cloud.categories.length, 1);
      final rows = await db.select(db.syncOutbox).get();
      final pending = rows.where((r) => r.status == 'PENDING').length;
      if (pending != 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final rows2 = await db.select(db.syncOutbox).get();
        final p2 = rows2.where((r) => r.status == 'PENDING').length;
        expect(p2, 0);
      } else {
        expect(pending, 0);
      }
    });

    test('multiple refreshes are serialized', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final cloud = FakeRemoteStore();
      final gateway = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: 'shop-1',
      );
      addTearDown(db.close);
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('shop-1'), name: 'S'));
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              email: 'a@b.co',
              authUserId: Value('u1'),
              shopId: Value('shop-1'),
              role: Value('OWNER'),
            ),
          );

      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          deviceIdProvider.overrideWith((ref) => 'dev-1'),
          remoteDeviceGatewayProvider.overrideWithValue(gateway),
          syncGatewayProvider.overrideWithValue(gateway),
          syncEngineProvider.overrideWith(
            (ref) => SyncEngine(
              DriftSyncRepository(db),
              gateway,
              LocalMasterDataApplier(db),
            ),
          ),
          connectivityServiceProvider.overrideWithValue(
            fakeConnectivityService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final f1 = container.read(syncStatusProvider.notifier).syncNow();
      final f2 = container.read(syncStatusProvider.notifier).syncNow();
      await Future.wait([f1, f2]);
      expect(container.read(syncStatusProvider).isSyncing, isFalse);
    });

    test('offline refresh does not destroy local data', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value('shop-1'), name: 'S'));
      await db
          .into(db.users)
          .insert(
            UsersCompanion.insert(
              email: 'a@b.co',
              authUserId: Value('u1'),
              shopId: Value('shop-1'),
              role: Value('OWNER'),
            ),
          );
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: Value('cat-off'),
              name: 'OfflineCat',
            ),
          );

      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'u1', email: 'a@b.co'),
      );
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authRepositoryProvider.overrideWithValue(auth),
          deviceIdProvider.overrideWith((ref) => 'dev-1'),
          connectivityServiceProvider.overrideWithValue(
            fakeConnectivityService(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(userProfileProvider.future);

      await container.read(syncStatusProvider.notifier).syncNow();
      final cats = await db.select(db.categories).get();
      expect(cats.any((c) => c.id == 'cat-off'), isTrue);
    });
  });
}
