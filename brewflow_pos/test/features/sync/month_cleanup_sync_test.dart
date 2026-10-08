import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Month cleanup + report-confirmation sync contract.
///
/// Report confirmations sync as ordinary UPSERT rows through the existing
/// engine, so every owner device agrees a month is report-backed. Cleanup
/// markers converge the other way: the atomic server delete writes the
/// marker, peers pull it and delete their local month mirrors in dependency
/// order — no per-row tombstone floods.
///
/// Covered:
///   1. confirmation A -> cloud -> B (same id, same month).
///   2. a pulled marker deletes B's month scope and records the marker.
///   3. markers defer while transactional outbox rows are still queued, then
///      apply once the queue drains (no resurrection without a tombstone).
///   4. markers never cross shops.
///   5. replaying a marker is a no-op.
///   6. a deferred marker holds the cursor until it applies, then cloud
///      records it deleted are re-pulled (sales + customer payments).
/// ---------------------------------------------------------------------------

void main() {
  const shopA = 'shop-a';
  const shopB = 'shop-b';
  final september = DateTime.utc(2026, 9);

  Future<
    ({
      AppDatabase db,
      DriftSyncRepository sync,
      SyncEngine engine,
      DriftStorageCleanupRepository cleanup,
    })
  >
  device(
    FakeRemoteStore cloud, {
    required String deviceId,
    required String viewerShopId,
    String shopId = shopA,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: Value(shopId), name: shopId));
    final sync = DriftSyncRepository(db);
    final gateway = FakeRemoteMasterDataGateway(
      cloud,
      viewerShopId: viewerShopId,
    );
    final engine = SyncEngine(sync, gateway, LocalMasterDataApplier(db));
    final coordinator = SyncOutboxCoordinator(
      sync,
      () async => SyncSessionContext(
        deviceId: deviceId,
        shopId: shopId,
        userId: 'owner',
      ),
    );
    return (
      db: db,
      sync: sync,
      engine: engine,
      cleanup: DriftStorageCleanupRepository(db, outbox: coordinator),
    );
  }

  Future<void> cycle(
    SyncEngine engine, {
    String deviceId = 'A',
    String shopId = shopA,
  }) => engine.runCycle(deviceId: deviceId, shopId: shopId);

  Future<void> seedSale(
    AppDatabase db,
    String shopId,
    String id,
    DateTime createdAt,
  ) => db
      .into(db.sales)
      .insert(
        SalesCompanion.insert(
          id: Value(id),
          shopId: Value(shopId),
          receiptNumber: 'R-$id',
          subtotalPaise: 100,
          totalPaise: 100,
          paymentStatus: const Value('PAID'),
          createdAt: Value(createdAt),
          updatedAt: Value(createdAt),
        ),
      );

  group('report confirmations', () {
    test('confirm on A is visible on B after sync', () async {
      final cloud = FakeRemoteStore();
      final a = await device(cloud, deviceId: 'A', viewerShopId: shopA);
      final b = await device(cloud, deviceId: 'B', viewerShopId: shopA);

      final confirmation = await a.cleanup.confirmReport(
        shopId: shopA,
        month: september,
      );
      expect(await a.sync.pendingOutboxCount(), 1);

      await cycle(a.engine);
      expect(cloud.monthlyReportConfirmations, hasLength(1));

      await cycle(b.engine, deviceId: 'B');
      final pulled = await b.cleanup.confirmationFor(shopA, september);
      expect(pulled, isNotNull);
      expect(pulled!.id, confirmation.id);
      expect(pulled.month, september);
    });

    test('re-confirming refreshes the same month row', () async {
      final cloud = FakeRemoteStore();
      final a = await device(cloud, deviceId: 'A', viewerShopId: shopA);

      final first = await a.cleanup.confirmReport(
        shopId: shopA,
        month: september,
      );
      final second = await a.cleanup.confirmReport(
        shopId: shopA,
        month: september,
      );
      expect(second.id, first.id);
      await cycle(a.engine);
      expect(cloud.monthlyReportConfirmations, hasLength(1));
    });
  });

  group('cleanup markers', () {
    Future<void> pushMarker(FakeRemoteMasterDataGateway gateway, String id) =>
        gateway.upsertMonthCleanupMarkers([
          SyncMonthCleanupMarker(
            id: id,
            shopId: shopA,
            month: september,
            tables: const ['sales'],
            deletedCounts: const {'sales': 1},
            completedAt: DateTime.utc(2026, 10, 1),
            createdAt: DateTime.utc(2026, 10, 1),
          ),
        ]);

    test('a pulled marker deletes the peer month scope', () async {
      final cloud = FakeRemoteStore();
      final b = await device(cloud, deviceId: 'B', viewerShopId: shopA);
      await seedSale(b.db, shopA, 'sale-sep', DateTime.utc(2026, 9, 10));
      await seedSale(b.db, shopA, 'sale-aug', DateTime.utc(2026, 8, 10));
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
      await pushMarker(gatewayA, 'marker-1');

      await cycle(b.engine, deviceId: 'B');

      final remaining = await b.db.select(b.db.sales).get();
      expect(remaining.map((s) => s.id), ['sale-aug']);
      expect(await b.cleanup.markerApplied('marker-1'), isTrue);
    });

    test('replaying a marker is a no-op', () async {
      final cloud = FakeRemoteStore();
      final b = await device(cloud, deviceId: 'B', viewerShopId: shopA);
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
      await pushMarker(gatewayA, 'marker-1');

      await cycle(b.engine, deviceId: 'B');
      await cycle(b.engine, deviceId: 'B');

      expect(await b.cleanup.markerApplied('marker-1'), isTrue);
      expect(await b.db.select(b.db.sales).get(), isEmpty);
    });

    test('markers defer while transactional writes are queued', () async {
      final cloud = FakeRemoteStore();
      final b = await device(cloud, deviceId: 'B', viewerShopId: shopA);
      await seedSale(b.db, shopA, 'sale-sep', DateTime.utc(2026, 9, 10));
      // A queued sale for the same device: applying the marker now would let
      // a later push resurrect it server-side with no tombstone.
      await b.db
          .into(b.db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'B',
              shopId: shopA,
              entity: 'SALE',
              entityId: 'sale-sep',
              payload: '{}',
            ),
          );
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
      await pushMarker(gatewayA, 'marker-1');

      await cycle(b.engine, deviceId: 'B');
      expect(
        (await b.db.select(b.db.sales).get()).map((s) => s.id),
        ['sale-sep'],
        reason: 'queued rows must not be deleted under',
      );
      expect(await b.cleanup.markerApplied('marker-1'), isFalse);

      // Once the queue drains, the next cycle applies the marker.
      final pending = await (b.db.select(
        b.db.syncOutbox,
      )..where((t) => t.entityId.equals('sale-sep'))).getSingle();
      await b.sync.markDone(pending.id);
      await cycle(b.engine, deviceId: 'B');
      expect(await b.db.select(b.db.sales).get(), isEmpty);
      expect(await b.cleanup.markerApplied('marker-1'), isTrue);
    });

    test('markers never cross shops', () async {
      final cloud = FakeRemoteStore();
      final other = await device(
        cloud,
        deviceId: 'O',
        viewerShopId: shopB,
        shopId: shopB,
      );
      await seedSale(other.db, shopB, 'sale-o', DateTime.utc(2026, 9, 10));
      final gatewayA = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
      await pushMarker(gatewayA, 'marker-1');

      await cycle(other.engine, deviceId: 'O', shopId: shopB);

      expect((await other.db.select(other.db.sales).get()).map((s) => s.id), [
        'sale-o',
      ]);
      expect(await other.cleanup.markerApplied('marker-1'), isFalse);
    });

    test('deferred marker holds the cursor, then cloud sales + payments are '
        're-pulled after it applies', () async {
      final cloud = FakeRemoteStore();
      final b = await device(cloud, deviceId: 'B', viewerShopId: shopA);
      const customerId = 'cust-oct';
      const saleId = 'sale-oct';
      const paymentId = 'pay-oct';
      const markerId = 'marker-oct';
      final saleTime = DateTime.utc(2026, 10, 5);
      final paymentTime = DateTime.utc(2026, 10, 6);
      final markerTime = DateTime.utc(2026, 10, 10);
      final october = DateTime.utc(2026, 10);

      // The cloud holds a customer, an October credit sale and a partial
      // payment against it: the month's records are still valid upstream.
      cloud.customers[customerId] = StoredRow(
        SyncCustomer(
          id: customerId,
          shopId: shopA,
          name: 'October Credit',
          isActive: true,
          membershipActive: false,
          whatsappStatus: 'UNKNOWN',
          createdAt: DateTime.utc(2026, 10, 1),
        ),
        shopA,
        DateTime.utc(2026, 10, 1),
      );
      cloud.sales[saleId] = StoredRow(
        SyncSale(
          id: saleId,
          shopId: shopA,
          customerId: customerId,
          receiptNumber: 'R-$saleId',
          subtotalPaise: 1000,
          totalPaise: 1000,
          paymentStatus: 'NOT_PAID',
          createdAt: saleTime,
        ),
        shopA,
        saleTime,
      );
      cloud.customerPayments[paymentId] = StoredRow(
        SyncCustomerPayment(
          id: paymentId,
          shopId: shopA,
          customerId: customerId,
          saleId: saleId,
          amountPaise: 400,
          paymentMethod: 'CASH',
          paidAt: paymentTime,
          reversed: false,
          createdAt: paymentTime,
        ),
        shopA,
        paymentTime,
      );

      // The cloud also holds an October cleanup marker created after the
      // sale and payment.
      cloud.clock = markerTime;
      final gatewayCloud = FakeRemoteMasterDataGateway(
        cloud,
        viewerShopId: shopA,
      );
      await gatewayCloud.upsertMonthCleanupMarkers([
        SyncMonthCleanupMarker(
          id: markerId,
          shopId: shopA,
          month: october,
          tables: const ['sales'],
          deletedCounts: const {'sales': 1},
          completedAt: markerTime,
          createdAt: markerTime,
        ),
      ]);

      // Device B has a pending transactional outbox entry, forcing the
      // marker to defer. A DIFFERENT entity id keeps the pull guard from
      // suppressing the cloud sale, and an invalid payload keeps the push
      // failing so the entry stays PENDING across cycles.
      await b.db
          .into(b.db.syncOutbox)
          .insert(
            SyncOutboxCompanion.insert(
              deviceId: 'B',
              shopId: shopA,
              entity: 'SALE',
              entityId: 'pending-oct',
              payload: '{}',
            ),
          );

      // Cycle 1: the marker defers (queue busy) and the shared cursor must
      // NOT advance past it. The cloud bill + payment pull through.
      await cycle(b.engine, deviceId: 'B');
      expect(
        (await b.db.select(b.db.sales).get()).map((s) => s.id),
        [saleId],
        reason: 'deferred marker must not delete local rows',
      );
      expect(
        (await b.db.select(b.db.customerPayments).get()).length,
        1,
        reason: 'deferred marker must not delete local payments',
      );
      expect(await b.cleanup.markerApplied(markerId), isFalse);
      expect(
        (await b.sync.stateFor('B'))!.lastPulledAt!.isBefore(markerTime),
        isTrue,
        reason: 'cursor must not advance past an unapplied marker',
      );

      // Drain the outbox so the marker can apply.
      final pending = await (b.db.select(
        b.db.syncOutbox,
      )..where((t) => t.entityId.equals('pending-oct'))).getSingle();
      await b.sync.markDone(pending.id);

      // Cycle 2: the marker applies (deleting the local month mirrors) and
      // the SAME cycle re-pulls the cloud records the delete removed — the
      // cursor had never moved past them.
      await cycle(b.engine, deviceId: 'B');
      expect(await b.cleanup.markerApplied(markerId), isTrue);
      expect(
        (await b.db.select(b.db.sales).get()).map((s) => s.id),
        [saleId],
        reason: 'sale must be re-pulled after the marker applies',
      );
      expect(
        (await b.db.select(b.db.customerPayments).get()).length,
        1,
        reason: 'payment must be re-pulled after the marker applies',
      );
      expect(
        (await b.sync.stateFor('B'))!.lastPulledAt!.isBefore(markerTime),
        isFalse,
        reason: 'cursor only advances once the marker has applied',
      );

      // Cycle 3: stable — nothing is re-pulled or re-deleted.
      await cycle(b.engine, deviceId: 'B');
      expect((await b.db.select(b.db.sales).get()).map((s) => s.id), [saleId]);
      expect((await b.db.select(b.db.customerPayments).get()).length, 1);
    });
  });
}
