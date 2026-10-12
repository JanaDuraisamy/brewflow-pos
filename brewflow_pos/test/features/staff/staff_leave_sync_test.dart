import 'dart:io';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/data/local_master_data_applier.dart';
import 'package:brewflow_pos/features/sync/data/sync_engine.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_remote_master_data_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Leave local-first + durable sync contract.
///
/// Leave is a day-level state on the SAME staff_attendance row (same
/// STAFF_ATTENDANCE entity, same outbox, same pull): isLeave is the source of
/// truth, never the timestamps. A Leave row carries the day cookie with 0
/// minutes and an optional reason.
///
/// Covered:
///   1. online Leave appears immediately from local Drift with queued outbox.
///   2. offline Leave works and converges when back online.
///   3. pending Leave survives an app restart (file-backed database).
///   4. cross-device pull shows the same Leave with reason.
///   5. shop isolation holds on push and pull.
///   6. duplicate Leave for the same day updates the reason, never duplicates.
///   7. Leave vs worked-shift conflicts stay blocked in both directions.
///   8. existing Check In/Out behavior is unchanged (regression).
///   9. clearing Leave removes it locally at once and everywhere after sync.
/// ---------------------------------------------------------------------------

void main() {
  const shopA = 'shop-a';
  const shopB = 'shop-b';

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

  DateTime day(int d) => DateTime.utc(2026, 9, d);
  DateTime endOfDay(DateTime d) => d.add(const Duration(days: 1));

  Future<List<StaffAttendanceRecord>> month(
    DriftStaffPayrollRepository payroll,
    String staffId,
    DateTime dayCookie,
  ) => payroll.attendanceFor(
    staffUserId: staffId,
    startDate: DateTime.utc(2026, 9, 1),
    endExclusiveDate: DateTime.utc(2026, 10, 1),
    shopIds: const [shopA],
  );

  group('online Leave', () {
    test('marks locally at once and queues a durable outbox entry', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );

      await a.payroll.markLeave(
        staffUserId: 'u-a',
        attendanceDate: day(1),
        reason: 'Sick',
      );

      // Immediate local rendering: no cloud round trip happened yet.
      final local = await month(a.payroll, 'u-a', day(1));
      expect(local, hasLength(1));
      expect(local.single.isLeave, isTrue);
      expect(local.single.leaveReason, 'Sick');
      expect(local.single.workedMinutes, 0);
      expect(local.single.attendanceDate, day(1));
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(cloud.staffAttendance, isEmpty);

      // Open-shift semantics are untouched: Leave is never an open shift.
      expect(await a.payroll.openShiftFor('u-a'), isNull);

      // Background sync converges on the same id.
      await cycle(a.engine);
      expect(await a.sync.pendingOutboxCount(), 0);
      expect(cloud.staffAttendance, hasLength(1));
      final pushed = cloud.staffAttendance.values.single.row;
      expect(pushed.isLeave, isTrue);
      expect(pushed.leaveReason, 'Sick');
      expect(pushed.workedMinutes, 0);
    });

    test('Leave without a reason syncs with a null reason', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );

      await a.payroll.markLeave(staffUserId: 'u-a', attendanceDate: day(2));
      await cycle(a.engine);

      expect(cloud.staffAttendance, hasLength(1));
      expect(cloud.staffAttendance.values.single.row.leaveReason, isNull);
    });
  });

  group('offline Leave', () {
    test('works offline and converges when back online', () async {
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

      await a.payroll.markLeave(
        staffUserId: 'u-a',
        attendanceDate: day(3),
        reason: 'Family',
      );
      expect((await month(a.payroll, 'u-a', day(3))).single.isLeave, isTrue);

      await cycle(offlineEngine);
      expect(await a.sync.pendingOutboxCount(), 1);
      expect(cloud.staffAttendance, isEmpty);

      await cycle(a.engine);
      expect(cloud.staffAttendance, hasLength(1));
      expect(cloud.staffAttendance.values.single.row.leaveReason, 'Family');
    });
  });

  group('restart durability', () {
    test('pending Leave survives an app restart', () async {
      final dir = await Directory.systemTemp.createTemp('brewflow-leave-');
      addTearDown(() => dir.delete(recursive: true));
      final path = '${dir.path}${Platform.pathSeparator}pos.sqlite';
      final cloud = FakeRemoteStore();

      String leaveId;
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
        await payroll.markLeave(
          staffUserId: 'u-a',
          attendanceDate: day(4),
          reason: 'Travel',
        );
        final rows = await payroll.attendanceFor(
          staffUserId: 'u-a',
          startDate: DateTime.utc(2026, 9, 1),
          endExclusiveDate: DateTime.utc(2026, 10, 1),
          shopIds: const [shopA],
        );
        leaveId = rows.single.id;
        expect(await sync.pendingOutboxCount(), 1);
        await db.close();
      }

      final db = AppDatabase(NativeDatabase(File(path)));
      addTearDown(db.close);
      final sync = DriftSyncRepository(db);
      final payroll = DriftStaffPayrollRepository(db);
      final rows = await payroll.attendanceFor(
        staffUserId: 'u-a',
        startDate: DateTime.utc(2026, 9, 1),
        endExclusiveDate: DateTime.utc(2026, 10, 1),
        shopIds: const [shopA],
      );
      expect(rows.single.id, leaveId);
      expect(rows.single.isLeave, isTrue);
      expect(await sync.pendingOutboxCount(), 1);

      final engine = SyncEngine(
        sync,
        FakeRemoteMasterDataGateway(cloud, viewerShopId: shopA),
        LocalMasterDataApplier(db),
      );
      await cycle(engine);
      expect(cloud.staffAttendance.keys, [leaveId]);
    });
  });

  group('cross-device sync', () {
    test('phone B pulls the same Leave with reason', () async {
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

      await a.payroll.markLeave(
        staffUserId: 'u-a',
        attendanceDate: day(5),
        reason: 'Festival',
      );
      await cycle(a.engine);
      await cycle(b.engine, deviceId: 'B');

      final shifts = await b.payroll.attendanceFor(
        staffUserId: 'u-b',
        startDate: DateTime.utc(2026, 9, 1),
        endExclusiveDate: DateTime.utc(2026, 10, 1),
        shopIds: const [shopA],
      );
      expect(shifts, hasLength(1));
      expect(shifts.single.id, cloud.staffAttendance.keys.single);
      expect(shifts.single.staffUserId, 'u-b');
      expect(shifts.single.isLeave, isTrue);
      expect(shifts.single.leaveReason, 'Festival');
      expect(shifts.single.workedMinutes, 0);
      // Leave never counts as working time.
      expect(shifts.single.isOpen, isFalse);
    });

    test('clearing Leave on A removes it on B after sync', () async {
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

      await a.payroll.markLeave(staffUserId: 'u-a', attendanceDate: day(6));
      await cycle(a.engine);
      await cycle(b.engine, deviceId: 'B');
      expect(
        await b.payroll.attendanceFor(
          staffUserId: 'u-b',
          startDate: day(6),
          endExclusiveDate: endOfDay(day(6)),
          shopIds: const [shopA],
        ),
        hasLength(1),
      );

      await a.payroll.clearLeave(staffUserId: 'u-a', attendanceDate: day(6));
      // Immediate local removal.
      expect(
        await a.payroll.attendanceFor(
          staffUserId: 'u-a',
          startDate: day(6),
          endExclusiveDate: endOfDay(day(6)),
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
          startDate: day(6),
          endExclusiveDate: endOfDay(day(6)),
          shopIds: const [shopA],
        ),
        isEmpty,
      );
    });
  });

  group('shop isolation', () {
    test('another shop neither receives nor leaks Leave', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.markLeave(
        staffUserId: 'u-a',
        attendanceDate: day(7),
        reason: 'Sick',
      );
      await cycle(a.engine);
      expect(cloud.staffAttendance, hasLength(1));

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
        startDate: DateTime.utc(2026, 9, 1),
        endExclusiveDate: DateTime.utc(2026, 10, 1),
        shopIds: const [shopB],
      );
      expect(shifts, isEmpty);
    });
  });

  group('duplicate and conflicting dates', () {
    test(
      'marking the same day twice updates the reason, never duplicates',
      () async {
        final cloud = FakeRemoteStore();
        final a = await device(
          cloud,
          deviceId: 'A',
          viewerShopId: shopA,
          staffLocalId: 'u-a',
        );

        await a.payroll.markLeave(
          staffUserId: 'u-a',
          attendanceDate: day(8),
          reason: 'First',
        );
        final firstId = (await month(a.payroll, 'u-a', day(8))).single.id;

        await a.payroll.markLeave(
          staffUserId: 'u-a',
          attendanceDate: day(8),
          reason: 'Updated',
        );
        final rows = await month(a.payroll, 'u-a', day(8));
        expect(rows, hasLength(1));
        expect(rows.single.id, firstId);
        expect(rows.single.leaveReason, 'Updated');

        await cycle(a.engine);
        expect(cloud.staffAttendance, hasLength(1));
        expect(cloud.staffAttendance.values.single.row.leaveReason, 'Updated');
      },
    );

    test('Leave on a day with a worked shift stays blocked', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final inAt = DateTime.utc(2026, 9, 9, 3, 30);
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 8)),
      );

      await expectLater(
        a.payroll.markLeave(staffUserId: 'u-a', attendanceDate: day(9)),
        throwsA(isA<StaffPayrollLeaveConflictFailure>()),
      );
      // The worked shift is untouched and no Leave was queued.
      final rows = await month(a.payroll, 'u-a', day(9));
      expect(rows, hasLength(1));
      expect(rows.single.isLeave, isFalse);
    });

    test('clock-in on a Leave day stays blocked', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.markLeave(staffUserId: 'u-a', attendanceDate: day(10));

      await expectLater(
        a.payroll.clockIn(
          staffUserId: 'u-a',
          inAt: DateTime.utc(2026, 9, 10, 3, 30),
        ),
        throwsA(isA<StaffPayrollAlreadyOnLeaveFailure>()),
      );
      expect(await a.payroll.openShiftFor('u-a'), isNull);
    });

    test('Leave while an open shift exists stays blocked', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.clockIn(
        staffUserId: 'u-a',
        inAt: DateTime.utc(2026, 9, 11, 3, 30),
      );

      await expectLater(
        a.payroll.markLeave(staffUserId: 'u-a', attendanceDate: day(11)),
        throwsA(isA<StaffPayrollShiftAlreadyOpenFailure>()),
      );
    });

    test('clearing a day without Leave is a no-op', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      await a.payroll.clearLeave(staffUserId: 'u-a', attendanceDate: day(12));
      expect(await a.sync.pendingOutboxCount(), 0);
    });
  });

  group('Check In/Out regression', () {
    test('worked shifts still record hours and sync unchanged', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final inAt = DateTime.utc(2026, 9, 13, 3, 30);
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      expect(await a.payroll.openShiftFor('u-a'), isNotNull);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 8, minutes: 15)),
      );
      expect(await a.payroll.openShiftFor('u-a'), isNull);

      final rows = await month(a.payroll, 'u-a', day(13));
      expect(rows, hasLength(1));
      expect(rows.single.isLeave, isFalse);
      expect(rows.single.workedMinutes, 8 * 60 + 15);

      await cycle(a.engine);
      expect(cloud.staffAttendance, hasLength(1));
      expect(
        cloud.staffAttendance.values.single.row.workedMinutes,
        8 * 60 + 15,
      );
    });

    test('Leave days never count toward working days or hours', () async {
      final cloud = FakeRemoteStore();
      final a = await device(
        cloud,
        deviceId: 'A',
        viewerShopId: shopA,
        staffLocalId: 'u-a',
      );
      final inAt = DateTime.utc(2026, 9, 14, 3, 30);
      await a.payroll.clockIn(staffUserId: 'u-a', inAt: inAt);
      await a.payroll.clockOut(
        staffUserId: 'u-a',
        outAt: inAt.add(const Duration(hours: 8)),
      );
      await a.payroll.markLeave(
        staffUserId: 'u-a',
        attendanceDate: day(15),
        reason: 'Sick',
      );

      final rows = await a.payroll.attendanceFor(
        staffUserId: 'u-a',
        startDate: DateTime.utc(2026, 9, 1),
        endExclusiveDate: DateTime.utc(2026, 10, 1),
        shopIds: const [shopA],
      );
      final summary = MonthlyPayrollSummary(
        shifts: rows,
        advances: const [],
        manualSalaryPaise: null,
        openShift: null,
      );
      expect(summary.totalWorkingDays, 1);
      expect(summary.totalLeaveDays, 1);
      expect(summary.totalMinutes, 8 * 60);
    });
  });
}
