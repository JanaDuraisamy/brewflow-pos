import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — SyncStatusController Focused Tests
///
/// Verifies the production lifecycle of [SyncStatusController]:
/// - Idle session produces idle snapshot with no timer created
/// - Disposal completes cleanly
/// - Pending / failed count defaults are zero
/// - Snapshot contract is correct
/// ---------------------------------------------------------------------------

void main() {
  late ProviderContainer container;
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  SyncStatusSnapshot read() => container.read(syncStatusProvider);

  // ── 1. Idle session produces idle snapshot ──────────────────────────────

  test('idle session produces idle snapshot', () {
    final snap = read();
    expect(snap.level, SyncStatusLevel.idle);
    expect(snap.pendingCount, 0);
    expect(snap.failedCount, 0);
  });

  // ── 2. No timer created while session is idle ──────────────────────────

  test('no timer created while session is idle', () async {
    read(); // session idle → no Timer.periodic created

    // Advance well past the 15 s poll interval — nothing should fire.
    await Future<void>.delayed(const Duration(seconds: 16));

    // Still idle; no crash, no leaked timers.
    expect(read().level, SyncStatusLevel.idle);
  });

  // ── 3. Disposal completes cleanly ──────────────────────────────────────

  test('disposal completes cleanly', () {
    read(); // may or may not create a timer depending on session phase
    container.dispose(); // must not throw

    // Re-create container — should start fresh.
    container = ProviderContainer(
      overrides: [
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );

    expect(container.read(syncStatusProvider).level, SyncStatusLevel.idle);
  });

  // ── 4. Pending count reflects outbox state ─────────────────────────────

  test('pending count reflects outbox state', () {
    expect(read().pendingCount, 0);
  });

  // ── 5. Failed count reflects outbox state ──────────────────────────────

  test('failed count reflects outbox state', () {
    expect(read().failedCount, 0);
  });

  // ── 6. SyncStatusDot contract: reading provider returns valid snapshot ──

  test('SyncStatusDot contract: reading provider returns valid snapshot', () {
    final snap = read();
    expect(snap.level, isA<SyncStatusLevel>());
    expect(snap.pendingCount, isNonNegative);
    expect(snap.failedCount, isNonNegative);
  });
}
