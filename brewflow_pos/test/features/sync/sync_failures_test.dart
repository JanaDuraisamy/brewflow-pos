import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/domain/sync_failures.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Failures (domain + controller) Focused Tests
///
/// Verifies:
/// - [classifySyncFailure] separates transient (retryable) from permanent
///   (blocked) gateway failures using safe substring heuristics.
/// - [describeSyncOperation] produces friendly, safe labels.
/// - [SyncFailuresController] lists FAILED entries newest first and retries
///   one or all through the repository (requeued as fresh PENDING).
/// ---------------------------------------------------------------------------

void main() {
  group('classifySyncFailure', () {
    test('null and transient network errors are retryable', () {
      expect(classifySyncFailure(null), SyncFailureKind.retryable);
      expect(
        classifySyncFailure('Network is unreachable'),
        SyncFailureKind.retryable,
      );
      expect(
        classifySyncFailure('Connection reset by peer'),
        SyncFailureKind.retryable,
      );
      expect(
        classifySyncFailure('handshake timed out'),
        SyncFailureKind.retryable,
      );
      expect(
        classifySyncFailure('500 Internal Server Error'),
        SyncFailureKind.retryable,
      );
    });

    test('auth and permission errors are blocked', () {
      expect(classifySyncFailure('JWT expired'), SyncFailureKind.blocked);
      expect(classifySyncFailure('unauthorized'), SyncFailureKind.blocked);
      expect(
        classifySyncFailure('permission denied for table products'),
        SyncFailureKind.blocked,
      );
    });

    test('SQL constraint / schema errors are blocked', () {
      expect(
        classifySyncFailure(
          '23505: duplicate key value violates unique constraint',
        ),
        SyncFailureKind.blocked,
      );
      expect(
        classifySyncFailure('relation "sales" does not exist'),
        SyncFailureKind.blocked,
      );
      expect(
        classifySyncFailure('column products.name does not exist'),
        SyncFailureKind.blocked,
      );
    });
  });

  group('describeSyncOperation', () {
    test('maps known entities to friendly labels', () {
      expect(describeSyncOperation('PRODUCT', 'UPSERT'), 'Product upload');
      expect(
        describeSyncOperation('SALE_ITEM', 'DELETE'),
        'Sale item deletion',
      );
      expect(describeSyncOperation('EXPENSE', 'UPSERT'), 'Expense upload');
      expect(
        describeSyncOperation('STAFF_ATTENDANCE', 'UPSERT'),
        'Staff attendance upload',
      );
    });

    test('unknown entities fall back to the raw name', () {
      expect(describeSyncOperation('WHATEVER', 'UPSERT'), 'WHATEVER upload');
    });
  });

  group('SyncFailuresController', () {
    late ProviderContainer container;
    late AppDatabase db;
    late DriftSyncRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftSyncRepository(db);
      container = ProviderContainer(
        overrides: [
          ...businessScopeOverrides(),
          connectivityServiceProvider.overrideWithValue(
            fakeConnectivityService(),
          ),
          appDatabaseProvider.overrideWithValue(db),
          syncRepositoryProvider.overrideWithValue(repo),
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
      );
    });

    tearDown(() async {
      container.dispose();
      await db.close();
    });

    Future<void> seedFailed(
      String id,
      String entityId, [
      String error = 'Network is unreachable',
    ]) async {
      await repo.insertOutbox(
        SyncOutboxEntry(
          id: id,
          deviceId: 'device-a',
          shopId: 'shop-1',
          entity: 'PRODUCT',
          entityId: entityId,
          operation: 'UPSERT',
          payload: '{"id":"$entityId"}',
          status: 'PENDING',
          attemptCount: 0,
        ),
      );
      await repo.parkFailed(id, error);
    }

    test('provider lists FAILED entries newest attempt first', () async {
      await seedFailed('obx-1', 'p1');
      // Distinct timestamps so the desc ordering is deterministic.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await seedFailed('obx-2', 'p2', 'JWT expired');

      final list = await container.read(syncFailuresProvider.future);
      expect(list.map((f) => f.id).toList(), ['obx-2', 'obx-1']);
      expect(list.first.title, 'Product upload');
      expect(list.first.reason, contains('server'));
      expect(list.first.kind, SyncFailureKind.blocked);
    });

    test('retryOne requeues only the selected FAILED entry', () async {
      await seedFailed('obx-1', 'p1');
      await seedFailed('obx-2', 'p2');
      await container.read(syncFailuresProvider.future);

      await container.read(syncFailuresProvider.notifier).retryOne('obx-2');

      expect((await repo.pendingOutboxBatch()).single.id, 'obx-2');
      expect((await repo.failedOutboxBatch()).single.id, 'obx-1');
      final list = await container.read(syncFailuresProvider.future);
      expect(list.map((f) => f.id).toList(), ['obx-1']);
    });

    test('retryAll requeues every FAILED entry and clears the list', () async {
      await seedFailed('obx-1', 'p1');
      await seedFailed('obx-2', 'p2');
      await container.read(syncFailuresProvider.future);

      await container.read(syncFailuresProvider.notifier).retryAll();

      expect(await repo.failedOutboxBatch(), isEmpty);
      expect(await repo.pendingOutboxBatch(), hasLength(2));
      final list = await container.read(syncFailuresProvider.future);
      expect(list, isEmpty);
    });

    test('retryAll requeues only retryable entries in a mixed batch', () async {
      await seedFailed('obx-retry', 'p1', 'Network is unreachable');
      await seedFailed('obx-blocked', 'p2', 'JWT expired');
      await container.read(syncFailuresProvider.future);

      await container.read(syncFailuresProvider.notifier).retryAll();

      // The transient entry is back in the outbox; the blocked entry stays
      // FAILED with its error intact instead of being pointlessly re-pushed.
      expect((await repo.pendingOutboxBatch()).single.id, 'obx-retry');
      final failed = await repo.failedOutboxBatch();
      expect(failed.single.id, 'obx-blocked');
      expect(failed.single.lastError, 'JWT expired');
      final list = await container.read(syncFailuresProvider.future);
      expect(list.map((f) => f.id).toList(), ['obx-blocked']);
    });

    test('retryAll with only blocked entries requeues nothing', () async {
      await seedFailed('obx-b1', 'p1', 'permission denied for table products');
      await seedFailed('obx-b2', 'p2', '23505 duplicate key value');
      await container.read(syncFailuresProvider.future);

      await container.read(syncFailuresProvider.notifier).retryAll();

      expect(await repo.pendingOutboxBatch(), isEmpty);
      final failed = await repo.failedOutboxBatch();
      expect(failed.map((f) => f.id).toSet(), {'obx-b1', 'obx-b2'});
      final list = await container.read(syncFailuresProvider.future);
      expect(list, hasLength(2));
    });
  });
}
