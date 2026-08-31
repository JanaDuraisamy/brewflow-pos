import 'dart:async';
import 'dart:convert';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart'
    show DeviceIdentity, deviceIdProvider;
import 'package:brewflow_pos/core/services/connectivity_service.dart'
    show ConnectivityService;
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart'
    show AuthUser;
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/domain/device_registration.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';

/// ---------------------------------------------------------------------------
/// Phase 7.3 — Hardware Identity Recovery regression tests.
///
/// Covers F1 (authoritative cloud identity resolution + migration), F2
/// (authoritative shop_id used downstream: device registration, outbox
/// revival, sync session) and F3 (durable, idempotent, retryable cloud
/// identity push).
/// ---------------------------------------------------------------------------

/// In-memory remote device registry standing in for Supabase `devices`.
final class FakeRemoteDeviceGateway implements RemoteDeviceGateway {
  final Map<String, DeviceRegistration> rows = {};
  int failedCalls = 0;
  int failingCallsLeft = 0;

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

const String kAuthUserId = 'owner-1';
const String kEmail = 'owner@shop.co';
const String kLocalOrphan = 'a0e0845d-953e-49fd-8046-84271a5c212f';
const String kCloudAuthoritative = '85437772-a082-44b9-824e-69562356928e';

void main() {
  late AppDatabase db;
  late FakeRemoteDeviceGateway remote;

  setUp(() async {
    DeviceIdentity.resetForTest();
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeRemoteDeviceGateway();
  });

  tearDown(() => db.close());

  Future<void> seedShop(String id) => db
      .into(db.shops)
      .insert(ShopsCompanion.insert(id: Value(id), name: 'Shop $id'));

  Future<void> seedUser({
    required String authUserId,
    required String email,
    required String? shopId,
    String role = 'OWNER',
  }) async {
    // The local `shops` table is the FK target for users.shop_id.
    if (shopId != null) await seedShop(shopId);
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            email: email,
            authUserId: Value(authUserId),
            shopId: Value(shopId),
            role: Value(role),
          ),
        );
  }

  Future<void> seedFailedOutbox({
    required String shopId,
    required String deviceId,
    int n = 3,
  }) async {
    for (var i = 0; i < n; i++) {
      await db
          .into(db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: deviceId,
              shopId: shopId,
              entity: 'CATEGORY',
              entityId: 'ent-$i',
              payload: jsonEncode({'shopId': shopId, 'name': 'Cat $i'}),
              status: const Value('FAILED'),
              attemptCount: const Value(7),
              lastError: const Value('fk violation'),
            ),
          );
    }
  }

  ProviderContainer containerWith({
    required FakeAuthRepository auth,
    required String deviceId,
    required FakeCloudShopResolver resolver,
    ConnectivityService? connectivity,
  }) => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      authRepositoryProvider.overrideWithValue(auth),
      deviceIdProvider.overrideWith((ref) => deviceId),
      remoteDeviceGatewayProvider.overrideWithValue(remote),
      connectivityServiceProvider.overrideWithValue(
        connectivity ?? fakeConnectivityService(),
      ),
      cloudShopResolverProvider.overrideWithValue(resolver),
    ],
  );

  group('F1 — authoritative cloud identity resolution', () {
    test('existing local profile + valid cloud shop (different id) migrates '
        'local identity', () async {
      await seedUser(
        authUserId: kAuthUserId,
        email: kEmail,
        shopId: kLocalOrphan,
      );
      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: kCloudAuthoritative,
          shopName: 'My Shop',
          email: kEmail,
          role: 'OWNER',
          isActive: true,
        ),
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: kAuthUserId, email: kEmail),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'dev-1',
        resolver: resolver,
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);

      final migrated = await db.select(db.users).get();
      expect(migrated.single.shopId, kCloudAuthoritative);
    });

    test('orphan local shop + valid cloud shop → migration occurs', () async {
      await seedUser(
        authUserId: kAuthUserId,
        email: kEmail,
        shopId: kLocalOrphan,
      );
      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: kCloudAuthoritative,
          shopName: 'My Shop',
          email: kEmail,
          role: 'OWNER',
          isActive: true,
        ),
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: kAuthUserId, email: kEmail),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'dev-2',
        resolver: resolver,
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);

      final row = await db.select(db.users).get();
      expect(row.single.shopId, kCloudAuthoritative);
    });

    test(
      'cloud profile points to a missing shop → local identity untouched',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        // Cloud shop existence check reports false → do NOT migrate onto it.
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: 'cloud-missing',
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
          shopExistsResult: false,
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-3',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);

        final row = await db.select(db.users).get();
        expect(row.single.shopId, kLocalOrphan);
      },
    );

    test(
      'existing valid local/cloud identity → no unnecessary migration',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kCloudAuthoritative,
        );
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-4',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);

        final row = await db.select(db.users).get();
        expect(row.single.shopId, kCloudAuthoritative);
      },
    );
  });

  group('F2 — authoritative shop_id downstream', () {
    test(
      'FAILED outbox entries revived with cloud shop_id (not orphan)',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        await seedFailedOutbox(shopId: kLocalOrphan, deviceId: 'dev-5');
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-5',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);
        container.listen(syncSessionProvider, (_, _) {});
        await pumpEventQueue();

        final rows = await db.select(db.syncOutbox).get();
        expect(rows, isNotEmpty);
        expect(
          rows.every((r) => r.status == 'PENDING'),
          isTrue,
          reason: 'all entries revived to PENDING',
        );
        expect(
          rows.every((r) => r.shopId == kCloudAuthoritative),
          isTrue,
          reason: 'outbox column re-stamped to cloud shop',
        );
      },
    );

    test('JSON payload.shopId updated to cloud shop', () async {
      await seedUser(
        authUserId: kAuthUserId,
        email: kEmail,
        shopId: kLocalOrphan,
      );
      await seedFailedOutbox(shopId: kLocalOrphan, deviceId: 'dev-6');
      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: kCloudAuthoritative,
          shopName: 'My Shop',
          email: kEmail,
          role: 'OWNER',
          isActive: true,
        ),
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: kAuthUserId, email: kEmail),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'dev-6',
        resolver: resolver,
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();

      final rows = await db.select(db.syncOutbox).get();
      for (final r in rows) {
        final decoded = jsonDecode(r.payload) as Map<String, dynamic>;
        expect(decoded['shopId'], kCloudAuthoritative);
      }
    });

    test('device registration uses authoritative cloud shop_id', () async {
      await seedUser(
        authUserId: kAuthUserId,
        email: kEmail,
        shopId: kLocalOrphan,
      );
      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: kCloudAuthoritative,
          shopName: 'My Shop',
          email: kEmail,
          role: 'OWNER',
          isActive: true,
        ),
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: kAuthUserId, email: kEmail),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'dev-7',
        resolver: resolver,
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();

      expect(
        container.read(syncSessionProvider).phase,
        SyncSessionPhase.active,
      );
      expect(remote.rows['dev-7']!.shopId, kCloudAuthoritative);
    });

    test('sync session uses authoritative cloud shop_id', () async {
      await seedUser(
        authUserId: kAuthUserId,
        email: kEmail,
        shopId: kLocalOrphan,
      );
      final resolver = FakeCloudShopResolver(
        profile: CloudUserProfile(
          shopId: kCloudAuthoritative,
          shopName: 'My Shop',
          email: kEmail,
          role: 'OWNER',
          isActive: true,
        ),
      );
      final auth = FakeAuthRepository(
        user: const AuthUser(id: kAuthUserId, email: kEmail),
      );
      final container = containerWith(
        auth: auth,
        deviceId: 'dev-8',
        resolver: resolver,
      );
      addTearDown(container.dispose);

      await container.read(userProfileProvider.future);
      container.listen(syncSessionProvider, (_, _) {});
      await pumpEventQueue();

      final session = container.read(syncSessionProvider);
      expect(session.phase, SyncSessionPhase.active);
      expect(session.cloudConfirmed, isTrue);
    });
  });

  group('F3 — durable / retryable cloud identity push', () {
    test(
      'cloud identity unavailable → safe fallback, local state intact',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        final resolver = FakeCloudShopResolver(
          fetchThrows: true,
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-9',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);
        container.listen(syncSessionProvider, (_, _) {});
        await pumpEventQueue();

        // No crash; session still resolves locally and local identity is kept.
        expect(
          container.read(syncSessionProvider).phase,
          SyncSessionPhase.active,
        );
        final row = await db.select(db.users).get();
        expect(row.single.shopId, kLocalOrphan);
      },
    );

    test(
      'pushIdentity failure is tracked and retried on app restart',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
          pushIdentityFailures: 1,
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-10',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);
        container.listen(syncSessionProvider, (_, _) {});
        await pumpEventQueue();

        // First attempt failed; simulate app restart by re-resolving profile.
        container.refresh(userProfileProvider);
        await container.read(userProfileProvider.future);
        await pumpEventQueue();

        expect(resolver.pushedShopIds, contains(kCloudAuthoritative));
        // First failed, second (restart) succeeded → at least 2 attempts.
        expect(resolver.pushedShopIds.length, greaterThanOrEqualTo(2));
      },
    );

    test(
      'pushIdentity success never creates a duplicate identity record',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
          pushIdentityResult: true,
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-11',
          resolver: resolver,
        );
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);
        container.listen(syncSessionProvider, (_, _) {});
        await pumpEventQueue();
        // Multiple session ensure passes (mirrors restarts) — still one id.
        container.refresh(userProfileProvider);
        await container.read(userProfileProvider.future);
        await pumpEventQueue();

        expect(
          resolver.pushedShopIds.every((s) => s == kCloudAuthoritative),
          isTrue,
          reason: 'idempotent upsert always targets the same cloud shop',
        );
        expect(
          resolver.pushedAuthUserIds.every((u) => u == kAuthUserId),
          isTrue,
        );
      },
    );

    test(
      'connectivity restore after failed bootstrap retries the push',
      () async {
        await seedUser(
          authUserId: kAuthUserId,
          email: kEmail,
          shopId: kLocalOrphan,
        );
        final resolver = FakeCloudShopResolver(
          profile: CloudUserProfile(
            shopId: kCloudAuthoritative,
            shopName: 'My Shop',
            email: kEmail,
            role: 'OWNER',
            isActive: true,
          ),
          pushIdentityFailures: 1,
        );
        var online = false;
        final transport =
            StreamController<List<ConnectivityResult>>.broadcast();
        final reachability = StreamController<InternetStatus>.broadcast();
        final connectivity = ConnectivityService(
          transportStream: transport.stream,
          checkTransport: () async =>
              online ? [ConnectivityResult.wifi] : [ConnectivityResult.none],
          reachabilityStream: reachability.stream,
          checkReachability: () async =>
              online ? InternetStatus.connected : InternetStatus.disconnected,
        );
        final auth = FakeAuthRepository(
          user: const AuthUser(id: kAuthUserId, email: kEmail),
        );
        final container = containerWith(
          auth: auth,
          deviceId: 'dev-12',
          resolver: resolver,
          connectivity: connectivity,
        );
        addTearDown(() {
          container.dispose();
          transport.close();
          reachability.close();
        });

        await container.read(userProfileProvider.future);
        container.listen(syncSessionProvider, (_, _) {});
        await pumpEventQueue();

        // First push failed while offline; bring connectivity back.
        online = true;
        transport.add([ConnectivityResult.wifi]);
        reachability.add(InternetStatus.connected);
        await pumpEventQueue();

        expect(resolver.pushedShopIds, contains(kCloudAuthoritative));
        expect(resolver.pushedShopIds.length, greaterThanOrEqualTo(2));
      },
    );
  });
}
