import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// PHASE 7.1 — FAST SYNC kickoff contract.
///
/// The coordinator must fire its [SyncOutboxCoordinator.onEnqueue] hook
/// exactly once per committed mutation (and never when degraded to plain
/// local writes) so the session layer can schedule one debounced engine
/// cycle. Engine reentrancy/duplicate protection is covered by the seed
/// round-trip suite.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase db;
  late DriftSyncRepository sync;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    sync = DriftSyncRepository(db);
  });

  tearDown(() => db.close());

  test('onEnqueue fires once per successful mutation', () async {
    var kicks = 0;
    final coordinator = SyncOutboxCoordinator(
      sync,
      () async => const SyncSessionContext(
        deviceId: 'A',
        shopId: 'shop-1',
        userId: 'u',
      ),
      onEnqueue: () => kicks++,
    );

    await coordinator.run<int>(
      write: () async => 1,
      snapshots: (_, context) async => [
        OutboxAppend(
          entity: MasterEntity.category,
          entityId: 'c1',
          payload: const {},
        ),
      ],
    );
    expect(kicks, 1);
    expect(await sync.pendingOutboxCount(), 1);
  });

  test('degraded (no session) writes never fire the hook', () async {
    var kicks = 0;
    final coordinator = SyncOutboxCoordinator(
      sync,
      () async => null,
      onEnqueue: () => kicks++,
    );
    await coordinator.run<String>(
      write: () async => 'plain',
      snapshots: (_, _) async => const [],
    );
    expect(kicks, 0);
    expect(await sync.pendingOutboxCount(), 0);
  });
}
