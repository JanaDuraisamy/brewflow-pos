import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/storage_cleanup/data/drift_storage_cleanup_repository.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Monthly-report-confirmation push-conflict regression tests.
///
/// `monthly_report_confirmations` is unique on (shop_id, month) while pushes
/// upsert on `id`. When two devices confirm the same month, the second push
/// fails with PostgreSQL 23505 on
/// `monthly_report_confirmations_shop_id_month_key` — even though the month
/// IS report-backed. The engine must treat exactly that conflict as
/// converged (entry DONE), while unrelated 23505s and other errors keep the
/// normal retry path (entry stays PENDING, never silently DONE).
/// ---------------------------------------------------------------------------

/// The exact server error for a duplicate (shop_id, month) confirmation.
PostgrestException confirmationConflict() => PostgrestException(
  message:
      'duplicate key value violates unique constraint '
      '"monthly_report_confirmations_shop_id_month_key"',
  code: '23505',
  details: 'Conflict',
);

void main() {
  const shopA = 'shop-a';
  final october = DateTime.utc(2026, 10);

  Future<
    ({
      AppDatabase db,
      DriftSyncRepository sync,
      FakeRemoteMasterDataGateway gateway,
      SyncEngine engine,
      DriftStorageCleanupRepository cleanup,
    })
  >
  device(FakeRemoteStore cloud) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: Value(shopA), name: shopA));
    final sync = DriftSyncRepository(db);
    final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
    final engine = SyncEngine(sync, gateway, LocalMasterDataApplier(db));
    final coordinator = SyncOutboxCoordinator(
      sync,
      () async =>
          SyncSessionContext(deviceId: 'A', shopId: shopA, userId: 'owner'),
    );
    return (
      db: db,
      sync: sync,
      gateway: gateway,
      engine: engine,
      cleanup: DriftStorageCleanupRepository(db, outbox: coordinator),
    );
  }

  group('monthly report confirmation push conflict', () {
    test(
      'exact shop+month 23505 converges the entry DONE without a cloud write',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(cloud);

        await a.cleanup.confirmReport(shopId: shopA, month: october);
        expect(await a.sync.pendingOutboxCount(), 1);

        a.gateway.failConfirmationUpsertWith = confirmationConflict();
        await a.engine.runCycle(deviceId: 'A', shopId: shopA);

        // Converged: nothing queued, nothing parked, nothing written —
        // the month was already confirmed under a different id.
        expect(await a.sync.pendingOutboxCount(), 0);
        expect(await a.sync.failedOutboxCount(), 0);
        expect(cloud.monthlyReportConfirmations, isEmpty);
        // The local confirmation row is untouched (no id rewrite, no delete).
        final kept = await a.cleanup.confirmationFor(shopA, october);
        expect(kept, isNotNull);
      },
    );

    test('23505 on another constraint keeps the normal retry path', () async {
      final cloud = FakeRemoteStore();
      final a = await device(cloud);

      await a.cleanup.confirmReport(shopId: shopA, month: october);
      a.gateway.failConfirmationUpsertWith = PostgrestException(
        message:
            'duplicate key value violates unique constraint '
            '"ux_categories_shop_name"',
        code: '23505',
      );
      await a.engine.runCycle(deviceId: 'A', shopId: shopA);

      expect(a.gateway.pushAttempts, 1);
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(await a.sync.failedOutboxCount(), 0);
    });

    test('non-23505 errors keep the normal retry path', () async {
      final cloud = FakeRemoteStore();
      final a = await device(cloud);

      await a.cleanup.confirmReport(shopId: shopA, month: october);
      a.gateway.failConfirmationUpsertWith = PostgrestException(
        message: 'connection reset',
        code: 'XX000',
      );
      await a.engine.runCycle(deviceId: 'A', shopId: shopA);

      expect(a.gateway.pushAttempts, 1);
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(await a.sync.failedOutboxCount(), 0);
    });
  });
}
