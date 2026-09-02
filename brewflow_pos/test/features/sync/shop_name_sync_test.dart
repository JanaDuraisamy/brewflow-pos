import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/settings/data/drift_shop_name_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BUG 4 — cross-device shop-name sync.
///
/// The shop display name must converge across devices: a local rename lands
/// in the authoritative `shops` row, enqueues a SHOP outbox entry, pushes to
/// the cloud `shops.name`, and any other device pulls it into its own `shops`
/// row — never duplicating the shop nor changing its id (single-shop
/// contract). Offline renames stay PENDING locally and retry later.
/// ---------------------------------------------------------------------------

const _shopRowId = 'shop-row-0001';
const _shopId = 'shop-1';

final class _Device {
  _Device._({
    required this.deviceId,
    required this.database,
    required this.sync,
    required this.gateway,
    required this.engine,
    required this.shopName,
  });

  final String deviceId;
  final db.AppDatabase database;
  final DriftSyncRepository sync;
  final FakeRemoteMasterDataGateway gateway;
  final SyncEngine engine;
  final DriftShopNameRepository shopName;

  Future<void> runCycle() =>
      engine.runCycle(deviceId: deviceId, shopId: _shopId);

  Future<int> pending() => sync.pendingOutboxCount();

  Future<String?> localShopName() async {
    final row = await database.select(database.shops).getSingleOrNull();
    return row?.name;
  }

  Future<int> localShopCount() async =>
      (await database.select(database.shops).get()).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRemoteStore cloud;

  Future<_Device> makeDevice(String id) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    final sync = DriftSyncRepository(database);
    final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: _shopId);
    Future<SyncSessionContext> contextResolver() async =>
        SyncSessionContext(deviceId: id, shopId: _shopId, userId: 'u-$id');
    final coordinator = SyncOutboxCoordinator(sync, contextResolver);
    final engine = SyncEngine(sync, gateway, LocalMasterDataApplier(database));
    // Seed the canonical single-shop row, exactly as owner bootstrap does.
    await database
        .into(database.shops)
        .insert(
          db.ShopsCompanion.insert(
            id: const Value(_shopRowId),
            name: 'BrewFlow POS',
            createdAt: Value(DateTime.utc(2026, 1, 1)),
          ),
        );
    final device = _Device._(
      deviceId: id,
      database: database,
      sync: sync,
      gateway: gateway,
      engine: engine,
      shopName: DriftShopNameRepository(database, coordinator),
    );
    addTearDown(database.close);
    return device;
  }

  setUp(() {
    cloud = FakeRemoteStore();
  });

  group('shop-name sync', () {
    test(
      'local rename persists to shops.name and enqueues a PENDING SHOP row',
      () async {
        final a = await makeDevice('A');

        await a.shopName.persist('Cafe Marina');

        expect(await a.localShopName(), 'Cafe Marina');
        expect(
          await a.pending(),
          1,
          reason: 'rename must enter the FIFO outbox',
        );
        final entry =
            (await a.database.select(a.database.syncOutbox).get()).single;
        expect(entry.entity, 'SHOP');
        expect(entry.entityId, _shopRowId);
        expect(entry.status, 'PENDING');
      },
    );

    test('rename pushes to cloud; other device pulls and converges', () async {
      final a = await makeDevice('A');
      final b = await makeDevice('B');

      await a.shopName.persist('Cafe Marina');
      await a.runCycle();
      expect(await a.pending(), 0);
      expect(cloud.shops[_shopRowId]!.row.name, 'Cafe Marina');

      await b.runCycle();
      expect(await b.localShopName(), 'Cafe Marina');
      expect(await b.localShopCount(), 1, reason: 'single-shop contract');
      final bRow = (await b.database.select(b.database.shops).get()).single;
      expect(bRow.id, _shopRowId, reason: 'id must never change/duplicate');
    });

    test(
      'offline rename stays PENDING locally; retry syncs to other device',
      () async {
        final a = await makeDevice('A');
        final b = await makeDevice('B');

        a.gateway.pushesFail = true;
        await a.shopName.persist('Airport Express');
        await a.runCycle();
        expect(await a.pending(), 1, reason: 'nothing lost while offline');
        expect(await a.localShopName(), 'Airport Express');

        a.gateway.pushesFail = false;
        await a.runCycle();
        expect(await a.pending(), 0);

        await b.runCycle();
        expect(await b.localShopName(), 'Airport Express');
      },
    );

    test('repeated cycles never duplicate the shop or change its id', () async {
      final a = await makeDevice('A');
      final b = await makeDevice('B');

      await a.shopName.persist('Round 1');
      await a.runCycle();
      await a.shopName.persist('Round 2');
      await a.runCycle();
      await b.runCycle();
      await b.runCycle();

      expect(await b.localShopName(), 'Round 2');
      expect(await b.localShopCount(), 1);
      expect(
        (await b.database.select(b.database.shops).get()).single.id,
        _shopRowId,
      );
    });

    test('BUG 3: manual rename on an empty tablet creates the shop row, '
        'enqueues SHOP, syncs, and never duplicates', () async {
      // Tablet without a bootstrapped `shops` row — the failing path.
      final database = db.AppDatabase(NativeDatabase.memory());
      final sync = DriftSyncRepository(database);
      final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: _shopId);
      Future<SyncSessionContext> contextResolver() async =>
          SyncSessionContext(deviceId: 'TAB', shopId: _shopId, userId: 'u-T');
      final coordinator = SyncOutboxCoordinator(sync, contextResolver);
      final engine = SyncEngine(
        sync,
        gateway,
        LocalMasterDataApplier(database),
      );
      final repository = DriftShopNameRepository(database, coordinator);
      addTearDown(database.close);

      // No row exists → persist must CREATE it, not silently drop.
      await repository.persist('Tablet Cafe');

      expect(await repository.currentName(), 'Tablet Cafe');
      final rows = await database.select(database.shops).get();
      expect(rows.length, 1, reason: 'must not duplicate the shop row');
      final row = rows.single;
      expect(row.name, 'Tablet Cafe');

      // SHOP outbox entry becomes PENDING against the created row id.
      final entry = (await database.select(database.syncOutbox).get()).single;
      expect(entry.entity, 'SHOP');
      expect(entry.entityId, row.id);
      expect(entry.status, 'PENDING');

      // Validates local id pushes to the cloud.
      await engine.runCycle(deviceId: 'TAB', shopId: _shopId);
      expect(await sync.pendingOutboxCount(), 0);
      expect(cloud.shops[row.id]!.row.name, 'Tablet Cafe');

      // Re-saving the same name is a no-op (no extra outbox entries / rows).
      await repository.persist('Tablet Cafe');
      expect(await sync.pendingOutboxCount(), 0);
      expect((await database.select(database.shops).get()).length, 1);
    });
  });
}
