import 'dart:io';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
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
/// BrewFlow POS — Attendance local-first + durable sync contract.
///
/// Locks the Check In / Check Out target flow:
///
///   press → local validation → local Drift commit → UI-ready immediately →
///   durable outbox entry → background engine push → cloud → peers pull.
///
/// Every test below runs against a real in-memory Drift database and the
/// shared in-memory cloud ([FakeRemoteStore]), so queue durability, retry
/// bookkeeping, tombstones and cross-device identity resolution behave
/// exactly as in production. The cloud double is controllable (push/pull
/// failure flags), never real network timing.
///
/// Covered:
///   1-2. local commit lands before the cloud round trip (in + out),
///   3.   successful background sync with a STABLE uuid,
///   4.   cloud failure retries, then parks FAILED without losing the row,
///   5-6. offline check-in AND check-out work,
///   7.   pending attendance survives an app restart (file-backed database),
///   8-9. stable uuid + idempotent retry (no duplicate cloud rows),
///   10.  duplicate check-in stays blocked (including cross-device),
///   11.  invalid check-out stays blocked,
///   12.  cross-device pull shows the same shift + correct payroll minutes,
///   13.  shop isolation holds on push and pull,
///   14.  attendance deletion syncs as a real delete everywhere,
///   15.  a stale cloud event never overwrites an unresolved local edit.
/// ---------------------------------------------------------------------------

void main() {
  const shopA = 'shop-a';
  const shopB = 'shop-b';

  /// One device: its own database, outbox, engine view and payroll repo, all
  /// sharing one [FakeRemoteStore] as the cloud.
  Future<
    ({
      AppDatabase db,
      DriftSyncRepository sync,
      SyncEngine engine,
      DriftStaffPayrollRepository payroll,
    })
  >
  device(
    FakeRemoteStore cloud, {
    required String deviceId,
    required String viewerShopId,
    required String staffLocalId,
    String authId = 'auth-1',
    String shopId = shopA,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: Value(shopId), name: shopId));
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(staffLocalId),
            email: '$staffLocalId@x.co',
            shopId: Value(shopId),
            role: const Value('STAFF'),
            authUserId: Value(authId),
          ),
        );
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
    final payroll = DriftStaffPayrollRepository(
      db,
      outboxCoordinator: coordinator,
    );
    return (db: db, sync: sync, engine: engine, payroll: payroll);
  }

  Future<void> cycle(
    SyncEngine engine, {
    String deviceId = 'A',
    String shopId = shopA,
  }) => engine.runCycle(deviceId: deviceId, shopId: shopId);

  DateTime day(DateTime instant) {
    final local = instant.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  group('local-first commit', () {
    test('check-in commits locally before the cloud round trip', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final inAt = DateTime.utc(2026, 9, 1, 3, 30);

      // The cloud is reachable but slow: the repository must NOT wait for it.
      // (The coordinator only queues; nothing pushes until a cycle runs.)
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);

      final open = await a.payroll.openShiftFor('u-a');
      expect(open, isNotNull, reason: 'UI-ready immediately after Check In');
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(
        cloud.staffAttendance,
        isEmpty,
        reason: 'no cloud round trip happened inside clockIn',
      );

      // Background sync converges on the SAME uuid.
      await cycle(a.engine);
      expect(await a.sync.pendingOutboxCount(), 0);
      expect(cloud.staffAttendance.keys, [open!.id]);
      expect(cloud.staffAttendance[open.id]!.row.inAt, inAt);
    });

    test('check-out commits locally before the cloud round trip', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final inAt = DateTime.utc(2026, 9, 1, 3, 30);
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      await cycle(a.engine);

      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 8, minutes: 15)),
      );

      final open = await a.payroll.openShiftFor('u-a');
      expect(open, isNull, reason: 'closed locally at once');
      final month = await a.payroll.attendanceFor(
        staffUserId: 'u-a',
        startDate: day(inAt),
        endExclusiveDate: day(inAt).add(const Duration(days: 1)),
        shopIds: const [shopA],
      );
      expect(month.single.workedMinutes, 8 * 60 + 15);
      expect(await a.sync.pendingOutboxCount(), 1);

      await cycle(a.engine);
      expect(await a.sync.pendingOutboxCount(), 0);
      // One converged cloud row: the clock-out collapsed onto the clock-in's
      // deterministic outbox id, never a second row.
      expect(cloud.staffAttendance, hasLength(1));
      expect(cloud.staffAttendance.values.single.row.workedMinutes, 495);
      expect(cloud.staffAttendance.values.single.row.outAt, isNotNull);
    });
  });

  group('retry and failure visibility', () {
    test(
      'a failing push retries, then parks FAILED with the row kept',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(
          cloud,
          deviceId: 'A',
          viewerShopId: shopA,
          staffLocalId: 'u-a',
        );
        final gateway = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA)
          ..pushesFail = true;
        final failingEngine = SyncEngine(
          a.sync,
          gateway,
          LocalMasterDataApplier(a.db),
        );

        await a.payroll.clockIn(
          staffUserId: 'u-a',
          inAt: DateTime.utc(2026, 9, 2, 3, 30),
        );

        await cycle(failingEngine);
        expect(await a.sync.pendingOutboxCount(), 1);
        expect(cloud.staffAttendance, isEmpty);

        // Exhaust the attempts: 7 more cycles park it as FAILED (maxAttempts 8).
        for (var i = 0; i < 7; i++) {
          await cycle(failingEngine);
        }
        expect(await a.sync.pendingOutboxCount(), 0);
        expect(await a.sync.failedOutboxCount(), 1);
        // The user's shift is NOT lost with the parked entry.
        expect(await a.payroll.openShiftFor('u-a'), isNotNull);

        // Recovery retries the same stable uuid — still exactly one cloud row.
        final openId = (await a.payroll.openShiftFor('u-a'))!.id;
        await a.sync.reviveFailedEntries(shopA);
        await cycle(a.engine);
        expect(await a.sync.failedOutboxCount(), 0);
        expect(cloud.staffAttendance.keys, [openId]);
      },
    );
  });

  group('offline', () {
    test('check-in and check-out both work with no connectivity', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final offline = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA)
        ..pushesFail = true
        ..pullsFail = true;
      final offlineEngine = SyncEngine(
        a.sync,
        offline,
        LocalMasterDataApplier(a.db),
      );
      final inAt = DateTime.utc(2026, 9, 3, 3, 30);

      // No OnlineGuard is wired (offline-first), and the coordinator degrades
      // to durable local queueing — neither call throws.
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      expect(await a.payroll.openShiftFor('u-a'), isNotNull);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 6)),
      );
      expect(await a.payroll.openShiftFor('u-a'), isNull);
      expect(await a.sync.pendingOutboxCount(), 1);

      // A cycle while still offline changes nothing durable except attempts.
      await cycle(offlineEngine);
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(cloud.staffAttendance, isEmpty);

      // Back online: one row, closed, correct minutes.
      await cycle(a.engine);
      expect(cloud.staffAttendance, hasLength(1));
      expect(cloud.staffAttendance.values.single.row.workedMinutes, 360);
      expect(cloud.staffAttendance.values.single.row.outAt, isNotNull);
    });
  });

  group('restart durability', () {
    test('pending attendance survives an app restart', () async {
      final dir = await Directory.systemTemp.createTemp('brewflow-attendance-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}pos.sqlite';
      final cloud = FakeRemoteStore();

      String shiftId;
      {
        final db = AppDatabase(NativeDatabase(File(path)));
        await db
            .into(db.shops)
            .insert(ShopsCompanion.insert(id: Value(shopA), name: shopA));
        await db
            .into(db.users)
            .insert(
              UsersCompanion.insert(
                id: const Value('u-a'),
                email: 'u-a@x.co',
                shopId: const Value(shopA),
                role: const Value('STAFF'),
                authUserId: const Value('auth-1'),
              ),
            );
        final sync = DriftSyncRepository(db);
        final coordinator = SyncOutboxCoordinator(
          sync,
          () async => const SyncSessionContext(
            deviceId: 'A',
            shopId: shopA,
            userId: 'owner',
          ),
        );
        final payroll = DriftStaffPayrollRepository(
          db,
          outboxCoordinator: coordinator,
        );
        await payroll.clockIn(
          staffUserId: 'u-a',
          inAt: DateTime.utc(2026, 9, 4, 3, 30),
        );
        shiftId = (await payroll.openShiftFor('u-a'))!.id;
        expect(await sync.pendingOutboxCount(), 1);
        await db.close();
      }

      // "Restart": a fresh database object over the same file.
      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      final sync = DriftSyncRepository(db);
      final payroll = DriftStaffPayrollRepository(db);
      expect((await payroll.openShiftFor('u-a'))?.id, shiftId);
      expect(await sync.pendingOutboxCount(), 1);

      final engine = SyncEngine(
        sync,
        FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA),
        LocalMasterDataApplier(db),
      );
      await cycle(engine);
      expect(cloud.staffAttendance.keys, [shiftId]);
      expect(await sync.pendingOutboxCount(), 0);
    });
  });

  group('validation is unchanged', () {
    test('duplicate check-in stays blocked while offline', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.clockIn(
        staffUserId: 'u-a',
        inAt: DateTime.utc(2026, 9, 5, 3, 30),
      );
      await expectLater(
        a.payroll.clockIn(
          staffUserId: 'u-a',
          inAt: DateTime.utc(2026, 9, 5, 4, 30),
        ),
        throwsA(isA<StaffPayrollShiftAlreadyOpenFailure>()),
      );
      // Exactly one local row and one queued change — the rejected tap queued
      // nothing.
      expect(await a.sync.pendingOutboxCount(), 1);
    });

    test('invalid check-out stays blocked', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await expectLater(
        a.payroll.clockOut(
          staffUserId: 'u-a',
          outAt: DateTime.utc(2026, 9, 5, 4, 30),
        ),
        throwsA(isA<StaffPayrollNoOpenShiftFailure>()),
      );
      await a.payroll.clockIn(
        staffUserId: 'u-a',
        inAt: DateTime.utc(2026, 9, 5, 3, 30),
      );
      await expectLater(
        a.payroll.clockOut(
          staffUserId: 'u-a',
          outAt: DateTime.utc(2026, 9, 5, 2, 30),
        ),
        throwsA(isA<StaffPayrollClockOutBeforeClockInFailure>()),
      );
      expect(await a.sync.pendingOutboxCount(), 1);
    });
  });

  group('cross-device', () {
    test('phone B pulls the same shift and payroll minutes', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      // Phone B minted its OWN local profile id for the same human.
      final b = await device(
        cloud,
        deviceId: 'B',
        viewerShopId: shopA,
        staffLocalId: 'u-b',
      );
      final inAt = DateTime.utc(2026, 9, 6, 3, 30);

      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 7, minutes: 45)),
      );
      await cycle(a.engine);

      await cycle(b.engine, deviceId: 'B');

      final shifts = await b.payroll.attendanceFor(
        staffUserId: 'u-b',
        startDate: day(inAt),
        endExclusiveDate: day(inAt).add(const Duration(days: 1)),
        shopIds: const [shopA],
      );
      expect(shifts, hasLength(1));
      // Same shared truth, re-attributed to B's own profile id.
      expect(shifts.single.id, cloud.staffAttendance.keys.single);
      expect(shifts.single.staffUserId, 'u-b');
      expect(shifts.single.workedMinutes, 7 * 60 + 45);
      expect(shifts.single.isOpen, isFalse);
    });

    test(
      'an open shift pulled cross-device blocks a second check-in',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(
          cloud,
          deviceId: 'A',
          viewerShopId: shopA,
          staffLocalId: 'u-a',
        );
        final b = await device(
          cloud,
          deviceId: 'B',
          viewerShopId: shopA,
          staffLocalId: 'u-b',
        );

        await a.payroll.clockIn(
          staffUserId: 'u-a',
          inAt: DateTime.utc(2026, 9, 7, 3, 30),
        );
        await cycle(a.engine);
        await cycle(b.engine, deviceId: 'B');

        // B sees the open shift through the pull and refuses a double clock-in.
        expect((await b.payroll.openShiftFor('u-b'))?.isOpen, isTrue);
        await expectLater(
          b.payroll.clockIn(
            staffUserId: 'u-b',
            inAt: DateTime.utc(2026, 9, 7, 4, 30),
          ),
          throwsA(isA<StaffPayrollShiftAlreadyOpenFailure>()),
        );
      },
    );

    test('a second device never needs the first phone online', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.clockIn(
        staffUserId: 'u-a',
        inAt: DateTime.utc(2026, 9, 8, 3, 30),
      );
      await cycle(a.engine);
      await a.db.close();

      final c = await device(
        cloud,
        deviceId: 'C',
        viewerShopId: shopA,
        staffLocalId: 'u-c',
      );
      await cycle(c.engine, deviceId: 'C');
      expect(await c.payroll.openShiftFor('u-c'), isNotNull);
    });
  });

  group('isolation', () {
    test('another shop neither receives nor leaks attendance', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.clockIn(
        staffUserId: 'u-a',
        inAt: DateTime.utc(2026, 9, 9, 3, 30),
      );
      await cycle(a.engine);
      expect(cloud.staffAttendance, hasLength(1));

      // A viewer scoped to shop B pulls nothing of shop A's shift.
      final other = await device(
        cloud,
        deviceId: 'O',
        viewerShopId: shopB,
        staffLocalId: 'u-o',
        shopId: shopB,
      );
      await cycle(other.engine, deviceId: 'O', shopId: shopB);
      final shifts = await other.payroll.attendanceFor(
        staffUserId: 'u-o',
        startDate: DateTime.utc(2026, 9, 9),
        endExclusiveDate: DateTime.utc(2026, 9, 10),
        shopIds: const [shopB],
      );
      expect(shifts, isEmpty);
    });
  });

  group('deletion sync', () {
    test('an owner delete removes the shift on every device', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final b = await device(
        cloud,
        deviceId: 'B',
        viewerShopId: shopA,
        staffLocalId: 'u-b',
      );
      final inAt = DateTime.utc(2026, 9, 10, 3, 30);

      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 8)),
      );
      await cycle(a.engine);
      await cycle(b.engine, deviceId: 'B');
      final shiftId = cloud.staffAttendance.keys.single;
      expect(
        await b.payroll.attendanceFor(
          staffUserId: 'u-b',
          startDate: day(inAt),
          endExclusiveDate: day(inAt).add(const Duration(days: 1)),
          shopIds: const [shopA],
        ),
        hasLength(1),
      );

      await a.payroll.deleteAttendance('u-a', shiftId);
      // Local-first delete: gone here at once, queued for the cloud.
      expect(
        await a.payroll.attendanceFor(
          staffUserId: 'u-a',
          startDate: day(inAt),
          endExclusiveDate: day(inAt).add(const Duration(days: 1)),
          shopIds: const [shopA],
        ),
        isEmpty,
      );
      await cycle(a.engine);
      expect(cloud.staffAttendance, isEmpty);

      await cycle(b.engine, deviceId: 'B');
      expect(
        await b.payroll.attendanceFor(
          staffUserId: 'u-b',
          startDate: day(inAt),
          endExclusiveDate: day(inAt).add(const Duration(days: 1)),
          shopIds: const [shopA],
        ),
        isEmpty,
      );

      // Repeating the delete stays a no-op (idempotent, never an error).
      await a.payroll.deleteAttendance('u-a', shiftId);
    });
  });

  group('stale events', () {
    test(
      'a stale cloud row never overwrites an unresolved local edit',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(
          cloud,
          deviceId: 'A',
          viewerShopId: shopA,
          staffLocalId: 'u-a',
        );
        final inAt = DateTime.utc(2026, 9, 11, 3, 30);
        await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
        final shiftId = (await a.payroll.openShiftFor('u-a'))!.id;

        // A rogue/stale cloud event for the same shift arrives (e.g. a replayed
        // close from elsewhere) while the local clock-in has not pushed yet.
        // The push keeps failing, so the entry stays PENDING while the pull
        // still runs in the same cycle — exactly the race the guard exists for.
        final failingPush = FakeRemoteMasterDataGateway(
          cloud,
          viewerShopId: shopA,
        )..pushesFail = true;
        final stalledEngine = SyncEngine(
          a.sync,
          failingPush,
          LocalMasterDataApplier(a.db),
        );
        final direct = FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA);
        await direct.upsertStaffAttendance([_staleClosedRow(shiftId, inAt)]);

        await cycle(stalledEngine);
        final open = await a.payroll.openShiftFor('u-a');
        expect(open, isNotNull, reason: 'unresolved local edit wins the pull');
        expect(open!.id, shiftId);
        expect(open.outAt, isNull);
        expect(await a.sync.pendingOutboxCount(), 1);
      },
    );
  });

  group('cursor integrity with late profiles', () {
    test(
      'a shift for an unarrived profile is re-pulled once the profile lands',
      () async {
        final cloud = FakeRemoteStore();
        // Phone B authors a shift for a staff identity this device has never
        // seen (a different auth id).
        final b = await device(
          cloud,
          deviceId: 'B',
          viewerShopId: shopA,
          staffLocalId: 'u-b',
          authId: 'auth-2',
        );
        final inAt = DateTime.utc(2026, 9, 12, 3, 30);
        await b.payroll.clockIn(staffUserId: 'u-b', inAt: inAt);
        await b.payroll.clockOut(
          staffUserId: 'u-b',
          outAt: inAt.add(const Duration(hours: 8)),
        );
        await cycle(b.engine, deviceId: 'B');

        // Phone D holds only its OWN profile, so the pulled row cannot be
        // attributed yet.
        final d = await device(
          cloud,
          deviceId: 'D',
          viewerShopId: shopA,
          staffLocalId: 'u-d',
          authId: 'auth-1',
        );
        await cycle(d.engine, deviceId: 'D');

        // Nothing was written (never invent a profile)…
        expect(
          await d.payroll.attendanceFor(
            staffUserId: 'u-d',
            startDate: day(inAt),
            endExclusiveDate: day(inAt).add(const Duration(days: 1)),
            shopIds: const [shopA],
          ),
          isEmpty,
        );
        // …and, crucially, the cursor did NOT advance past the skipped row:
        // it is parked at the initial cursor so the next pull re-reads it.
        expect(
          (await d.sync.stateFor('D'))!.lastPulledAt!.toUtc(),
          SyncEngine.initialCursor.toUtc(),
        );
        // A repeat cycle while the profile is still absent changes nothing —
        // the row is not silently dropped behind a moving cursor.
        await cycle(d.engine, deviceId: 'D');
        expect(
          (await d.sync.stateFor('D'))!.lastPulledAt!.toUtc(),
          SyncEngine.initialCursor.toUtc(),
        );

        // The profile arrives through the owner-login path (not this pull).
        await d.db
            .into(d.db.users)
            .insert(
              UsersCompanion.insert(
                id: const Value('u-recovered'),
                email: 'recovered@x.co',
                shopId: const Value(shopA),
                role: const Value('STAFF'),
                authUserId: const Value('auth-2'),
              ),
            );
        await cycle(d.engine, deviceId: 'D');

        final recovered = await d.payroll.attendanceFor(
          staffUserId: 'u-recovered',
          startDate: day(inAt),
          endExclusiveDate: day(inAt).add(const Duration(days: 1)),
          shopIds: const [shopA],
        );
        expect(recovered, hasLength(1));
        expect(recovered.single.workedMinutes, 8 * 60);
        // Same shared truth, now attributed to the arrived profile.
        expect(recovered.single.id, cloud.staffAttendance.keys.single);
      },
    );
  });
}

/// A stale replay injected directly into the cloud: the same shift id but
/// closed with minutes no local edit ever produced.
SyncStaffAttendance _staleClosedRow(String shiftId, DateTime inAt) {
  final local = inAt.toLocal();
  return SyncStaffAttendance(
    id: shiftId,
    shopId: 'shop-a',
    staffUserId: 'some-other-device-local-id',
    authUserId: 'auth-1',
    inAt: inAt,
    outAt: inAt.add(const Duration(minutes: 1)),
    attendanceDate: DateTime.utc(local.year, local.month, local.day),
    workedMinutes: 1,
    createdAt: inAt,
    updatedAt: inAt.add(const Duration(minutes: 1)),
  );
}
