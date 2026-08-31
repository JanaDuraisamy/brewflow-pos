import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart'
    show AuthUser;
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/data/device_registration_coordinator.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_preferences_storage.dart';

/// ---------------------------------------------------------------------------
/// Phase 6.1 — device registration tests.
///
/// Covers the coordinator (local + cloud layers, idempotency, offline
/// pending/retry) and the session wiring that registers THIS installation
/// right after the authenticated profile resolves — including the owner
/// multi-device and staff-device business rules.
/// ---------------------------------------------------------------------------

/// In-memory remote device registry standing in for Supabase `devices`.
final class FakeRemoteDeviceGateway implements RemoteDeviceGateway {
  final Map<String, DeviceRegistration> rows = {};

  /// When > 0, the next calls fail (offline simulation) and decrement.
  int failingCallsLeft = 0;

  /// Every failure is observed so tests can assert retry behavior.
  int failedCalls = 0;

  @override
  Future<void> registerDevice(DeviceRegistration registration) async {
    if (failingCallsLeft > 0) {
      failingCallsLeft--;
      failedCalls++;
      throw Exception('offline');
    }
    rows[registration.deviceId] = registration;
  }

  Iterable<DeviceRegistration> devicesForShop(String shopId) =>
      rows.values.where((row) => row.shopId == shopId);
}

void main() {
  late AppDatabase db;
  late DriftSyncRepository syncRepository;
  late FakeRemoteDeviceGateway remote;

  setUp(() async {
    DeviceIdentity.resetForTest();
    db = AppDatabase(NativeDatabase.memory());
    syncRepository = DriftSyncRepository(db);
    remote = FakeRemoteDeviceGateway();
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: const Value('shop-1'), name: 'Shop'));
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(id: const Value('shop-2'), name: 'Other'),
        );
  });

  tearDown(() => db.close());

  /// Coordinator whose installation id is deterministic per test.
  DeviceRegistrationCoordinator coordinator(String deviceId) =>
      DeviceRegistrationCoordinator(
        syncRepository: syncRepository,
        remoteGateway: remote,
        resolveDeviceId: () async => deviceId,
      );

  group('coordinator', () {
    test('registers locally AND remotely for one session', () async {
      const deviceId = '11111111-1111-1111-1111-111111111111';
      final confirmed = await coordinator(deviceId).ensureRegisteredForSession(
        shopId: 'shop-1',
        userId: 'owner-1',
        platform: 'android',
      );

      expect(confirmed, isTrue);
      expect(await syncRepository.hasDevice(deviceId), isTrue);
      expect(remote.rows, containsPair(deviceId, anything));
      expect(remote.rows[deviceId]!.userId, 'owner-1');
      expect(remote.rows[deviceId]!.shopId, 'shop-1');
    });

    test('re-registration stays idempotent locally and remotely', () async {
      const deviceId = '22222222-2222-2222-2222-222222222222';
      final coord = coordinator(deviceId);
      await coord.ensureRegisteredForSession(shopId: 'shop-1', userId: 'o');
      final first = (await syncRepository.devicesForShop('shop-1')).single;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await coord.ensureRegisteredForSession(
        shopId: 'shop-1',
        userId: 'o',
        platform: 'android',
      );
      final rows = await syncRepository.devicesForShop('shop-1');
      expect(rows.length, 1);
      expect(rows.single.id, first.id);
      // Cloud upsert keyed by id: still exactly one row.
      expect(remote.rows.length, 1);
    });

    test(
      'cloud failure keeps local registration; retry confirms later',
      () async {
        remote.failingCallsLeft = 1;
        const deviceId = '33333333-3333-3333-3333-333333333333';
        final confirmed = await coordinator(
          deviceId,
        ).ensureRegisteredForSession(shopId: 'shop-1', userId: 'owner-1');
        expect(confirmed, isFalse);

        expect(await syncRepository.hasDevice(deviceId), isTrue);
        expect(remote.rows, isEmpty);

        // Connectivity restored → next attempt succeeds without duplicates.
        final retried = await coordinator(
          deviceId,
        ).ensureRegisteredForSession(shopId: 'shop-1', userId: 'owner-1');
        expect(retried, isTrue);
        expect(remote.rows.keys, [deviceId]);
        expect(remote.failedCalls, 1);
      },
    );

    test('the SAME owner may register MANY devices', () async {
      // Three installations of one owner account (phone + phone2 + tablet):
      // each installation has its own stable identity, so registration never
      // collapses them into one row.
      for (var i = 0; i < 3; i++) {
        DeviceIdentity.resetForTest();
        final storage = FakePreferencesStorage();
        final identity = await DeviceIdentity.resolve(storage: storage);
        await coordinator('fixed').ensureRegistered(
          DeviceRegistration(
            deviceId: identity.value,
            shopId: 'shop-1',
            userId: 'owner-1',
          ),
        );
      }
      expect(remote.devicesForShop('shop-1').map((d) => d.userId).toSet(), {
        'owner-1',
      });
      expect(remote.devicesForShop('shop-1').length, 3);
    });

    test('a staff device joins the same shop under its own user', () async {
      await coordinator('fixed').ensureRegistered(
        const DeviceRegistration(
          deviceId: 'device-d',
          shopId: 'shop-1',
          userId: 'staff-1',
        ),
      );
      final staffRows = remote
          .devicesForShop('shop-1')
          .where((d) => d.userId == 'staff-1');
      expect(staffRows.length, 1);
    });

    test('device rows are scoped per shop (isolation)', () async {
      await coordinator('fixed').ensureRegistered(
        const DeviceRegistration(
          deviceId: 'd-shop1',
          shopId: 'shop-1',
          userId: 'u1',
        ),
      );
      await coordinator('fixed').ensureRegistered(
        const DeviceRegistration(
          deviceId: 'd-shop2',
          shopId: 'shop-2',
          userId: 'u2',
        ),
      );
      expect(remote.devicesForShop('shop-1').map((d) => d.deviceId), [
        'd-shop1',
      ]);
    });
  });

  group('session wiring', () {
    /// Seeds the local profile the real authorization chain resolves.
    Future<void> seedUser({
      required String authUserId,
      required String email,
      String? shopId,
      String role = 'OWNER',
    }) => db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            email: email,
            authUserId: Value(authUserId),
            shopId: Value(shopId),
            role: Value(role),
          ),
        );

    ProviderContainer containerWith({
      required FakeAuthRepository auth,
      required String deviceId,
    }) => ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(auth),
        deviceIdProvider.overrideWith((ref) => deviceId),
        remoteDeviceGatewayProvider.overrideWithValue(remote),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
      ],
    );

    test('registers THIS device right after the profile resolves', () async {
      DeviceIdentity.resetForTest();
      const deviceId = 'aaaaaaaa-0000-0000-0000-000000000001';
      await seedUser(
        authUserId: 'owner-1',
        email: 'owner@shop.co',
        shopId: 'shop-1',
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'owner-1', email: 'owner@shop.co'),
      );
      final container = containerWith(auth: auth, deviceId: deviceId);
      addTearDown(container.dispose);

      // Bootstraps the real chain: auth → profile → sync session.
      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();

      final session = container.read(syncSessionProvider);
      expect(session.phase, SyncSessionPhase.active);
      expect(session.cloudConfirmed, isTrue);
      expect(session.deviceId, deviceId);
      expect(await syncRepository.hasDevice(deviceId), isTrue);
      expect(remote.rows.keys, [deviceId]);
      expect(remote.rows[deviceId]!.userId, 'owner-1');
      expect(remote.rows[deviceId]!.shopId, 'shop-1');
    });

    test('sign-out drops the session back to idle', () async {
      DeviceIdentity.resetForTest();
      const deviceId = 'aaaaaaaa-0000-0000-0000-000000000002';
      await seedUser(
        authUserId: 'owner-1',
        email: 'owner@shop.co',
        shopId: 'shop-1',
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'owner-1', email: 'owner@shop.co'),
      );
      final container = containerWith(auth: auth, deviceId: deviceId);
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();
      expect(
        container.read(syncSessionProvider).phase,
        SyncSessionPhase.active,
      );

      // Real sign-out path: auth stream event cascades into the profile.
      auth.user = null;
      auth.emit(null);
      await pumpEventQueue();

      expect(container.read(syncSessionProvider).phase, SyncSessionPhase.idle);
    });

    test('a profile without a shop scope never registers', () async {
      DeviceIdentity.resetForTest();
      await seedUser(authUserId: 'u-x', email: 'ghost@shop.co', shopId: null);
      final auth = FakeAuthRepository(
        user: const AuthUser(id: 'u-x', email: 'ghost@shop.co'),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'aaaaaaaa-0000-0000-0000-000000000003',
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();

      expect(container.read(syncSessionProvider).phase, SyncSessionPhase.idle);
      expect(remote.rows, isEmpty);
    });
  });
}
