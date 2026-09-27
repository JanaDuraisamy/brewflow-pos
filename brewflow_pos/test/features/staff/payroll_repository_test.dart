import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_staff_payroll_cloud_gateway.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Repository Regression
///
/// Locks the persistence contract: In/Out times, automatic working-hour
/// calculation, attendance history, monthly hour accumulation, daily salary
/// amounts summed into the CALCULATED monthly salary (never hourly-rate
/// derived), manual monthly salary override, advance history/totals and
/// final payable = effective salary − advances.
///
/// Also locks cloud behavior: writes push to the gateway, reads pull first
/// (cloud-authoritative), failures fall back to the local mirror, business
/// isolation holds on both sides, and a second device (fresh database +
/// same cloud) sees the first device's records.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late FakeStaffPayrollCloudGateway cloud;
  late DriftStaffPayrollRepository repository;

  const cafeShop = 'shop-cafe';
  const truckShop = 'shop-truck';
  const staffId = 'staff-1';

  /// The auth identity the cloud is keyed on. Stable across devices, unlike the
  /// local [Users.id] which is a fresh uuid per device.
  const authId = 'auth-staff-1';

  Future<void> seedProfile({
    required AppDatabase db,
    String userId = staffId,
    String? shopId = cafeShop,
    String? authUserId = authId,
  }) async {
    for (final shop in [cafeShop, truckShop]) {
      final existing = await (db.select(
        db.shops,
      )..where((t) => t.id.equals(shop))).getSingleOrNull();
      if (existing == null) {
        await db
            .into(db.shops)
            .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
      }
    }
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            id: Value(userId),
            email: '$userId@brewflow.example',
            authUserId: Value(authUserId),
            shopId: Value(shopId),
            role: const Value('STAFF'),
          ),
        );
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    cloud = FakeStaffPayrollCloudGateway();
    repository = DriftStaffPayrollRepository(database, cloudGateway: cloud);
    await seedProfile(db: database);
  });

  tearDown(() async {
    await database.close();
  });

  DateTime day(int d) => DateTime.utc(2025, 7, d);
  DateTime month() => DateTime.utc(2025, 7);

  group('attendance', () {
    test('clock in/out records a shift with automatic working hours', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 3, 30), // 09:00 IST
      );
      expect(await repository.openShiftFor(staffId), isNotNull);

      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, 3, 14, 30), // 20:00 IST
      );
      expect(await repository.openShiftFor(staffId), isNull);

      final shifts = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      expect(shifts, hasLength(1));
      expect(shifts.single.workedMinutes, 660); // 11h
      expect(shifts.single.attendanceDate, day(3));
    });

    test('monthly total working hours accumulate across shifts', () async {
      for (final d in [1, 2, 3]) {
        await repository.clockIn(
          staffUserId: staffId,
          inAt: DateTime.utc(2025, 7, d, 3, 30),
        );
        await repository.clockOut(
          staffUserId: staffId,
          outAt: DateTime.utc(2025, 7, d, 11, 30),
        );
      }
      final shifts = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      final total = shifts.fold(0, (sum, s) => sum + s.workedMinutes);
      expect(total, 480 * 3);
    });

    test(
      'double clock-in is rejected; clock-out without open is rejected',
      () async {
        await repository.clockIn(
          staffUserId: staffId,
          inAt: DateTime.utc(2025, 7, 3, 3, 30),
        );
        expect(
          repository.clockIn(
            staffUserId: staffId,
            inAt: DateTime.utc(2025, 7, 3, 4),
          ),
          throwsA(isA<StaffPayrollShiftAlreadyOpenFailure>()),
        );
        await repository.clockOut(
          staffUserId: staffId,
          outAt: DateTime.utc(2025, 7, 3, 5),
        );
        expect(
          repository.clockOut(
            staffUserId: staffId,
            outAt: DateTime.utc(2025, 7, 3, 6),
          ),
          throwsA(isA<StaffPayrollNoOpenShiftFailure>()),
        );
      },
    );

    test('clock-out before clock-in is rejected', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 5),
      );
      expect(
        repository.clockOut(
          staffUserId: staffId,
          outAt: DateTime.utc(2025, 7, 3, 4),
        ),
        throwsA(isA<StaffPayrollClockOutBeforeClockInFailure>()),
      );
    });
  });

  group('attendance deletion', () {
    Future<String> closedShift(int dayOfMonth, {int hours = 8}) async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, dayOfMonth, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, dayOfMonth, 3, 30 + hours),
      );
      final shifts = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      return shifts.firstWhere((s) => s.attendanceDate == day(dayOfMonth)).id;
    }

    Future<List<StaffAttendanceRecord>> monthShifts() =>
        repository.attendanceFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
          shopIds: [cafeShop],
        );

    test('deletes the shift from the cloud and the local mirror', () async {
      final id = await closedShift(3);
      expect(cloud.storedShifts.map((s) => s.id), contains(id));

      await repository.deleteAttendance(staffId, id);

      expect(await monthShifts(), isEmpty);
      expect(cloud.storedShifts.map((s) => s.id), isNot(contains(id)));
      final local = await database.select(database.staffAttendance).get();
      expect(local, isEmpty);
    });

    test(
      'the cloud delete happens before the local mirror is touched',
      () async {
        final id = await closedShift(3);
        cloud.calls.clear();

        await repository.deleteAttendance(staffId, id);

        // One authoritative cloud delete, and no read in between that could
        // resurrect the row from a stale local mirror.
        expect(cloud.calls, ['deleteAttendance']);
      },
    );

    test('is idempotent: deleting an already-gone shift is a no-op', () async {
      final id = await closedShift(3);
      await repository.deleteAttendance(staffId, id);

      await repository.deleteAttendance(staffId, id);

      expect(await monthShifts(), isEmpty);
    });

    test('a cloud refusal keeps the local shift', () async {
      final id = await closedShift(3);
      cloud.failNext = true;

      await expectLater(
        repository.deleteAttendance(staffId, id),
        throwsA(isA<StaffPayrollCloudWriteFailure>()),
      );

      // Cloud-first: nothing was deleted locally, so both mirrors still agree.
      expect(cloud.storedShifts.map((s) => s.id), contains(id));
      final local = await database.select(database.staffAttendance).get();
      expect(local.map((r) => r.id), contains(id));
    });

    test(
      'a shift deleted on another device disappears on the next read',
      () async {
        final id = await closedShift(3);
        await closedShift(4);

        // A second device with its own database and the same cloud: it has
        // already pulled the shift, exactly like a real second tablet. Its
        // local profile id is DIFFERENT (a per-device uuid) while the auth id
        // matches, which is precisely the case that used to silently return
        // nothing.
        const otherDeviceStaffId = 'staff-1-on-device-2';
        final otherDb = AppDatabase(NativeDatabase.memory());
        addTearDown(otherDb.close);
        await seedProfile(db: otherDb, userId: otherDeviceStaffId);
        final secondDevice = DriftStaffPayrollRepository(
          otherDb,
          cloudGateway: cloud,
        );
        Future<List<StaffAttendanceRecord>> otherMonth() =>
            secondDevice.attendanceFor(
              staffUserId: otherDeviceStaffId,
              startDate: DateTime.utc(2025, 7, 1),
              endExclusiveDate: DateTime.utc(2025, 8, 1),
              shopIds: [cafeShop],
            );

        expect((await otherMonth()).map((s) => s.id), contains(id));

        // The delete is made on device A, in the cloud first.
        await repository.deleteAttendance(staffId, id);

        // Device B needs no explicit sync call: the cloud is authoritative for
        // the window it pulls, so the row is gone on its next read.
        final after = await otherMonth();
        expect(after.map((s) => s.id), isNot(contains(id)));
        expect(after.map((s) => s.attendanceDate), [day(4)]);
        final otherLocal = await otherDb.select(otherDb.staffAttendance).get();
        expect(otherLocal.map((r) => r.id), isNot(contains(id)));
        // Device B keeps the row under ITS OWN local id, never device A's.
        expect(
          after.map((s) => s.staffUserId),
          everyElement(otherDeviceStaffId),
        );
      },
    );

    test(
      'an empty cloud answer never wipes attendance recorded on this device',
      () async {
        // This device records a shift: the cloud is written first, then the
        // local mirror, so the row is genuinely cloud-backed.
        final id = await closedShift(5);

        // Now the cloud answers with nothing for this member — exactly what a
        // device sees when its member key does not match the cloud's, or when
        // the gateway reports success but returns no rows. That is an
        // unconfirmed answer, not proof the attendance was deleted, so the
        // local row must survive rather than being wiped.
        cloud.storedShifts.clear();

        final after = await repository.attendanceFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
          shopIds: [cafeShop],
        );

        expect(after.map((s) => s.id), contains(id));
        final local = await database.select(database.staffAttendance).get();
        expect(local.map((r) => r.id), contains(id));
      },
    );

    test('deleting one shift leaves the rest of the month intact', () async {
      final first = await closedShift(3);
      await closedShift(4);

      await repository.deleteAttendance(staffId, first);

      final remaining = await monthShifts();
      expect(remaining.map((s) => s.attendanceDate), [day(4)]);
    });

    test('deleting another member shift is refused', () async {
      final id = await closedShift(3);

      await repository.deleteAttendance('someone-else', id);

      expect((await monthShifts()).map((s) => s.id), [id]);
    });
  });

  group('manual salary + advances + payable', () {
    test('salary is stored per month and loads back', () async {
      expect(await repository.salaryForMonth(staffId, month()), isNull);
      await repository.setMonthlySalary(staffId, month(), 1200000);
      expect(await repository.salaryForMonth(staffId, month()), 1200000);
      // A different month stays unset (monthly, not global).
      expect(
        await repository.salaryForMonth(staffId, DateTime.utc(2025, 8)),
        isNull,
      );
    });

    test('salary can be cleared back to unset', () async {
      await repository.setMonthlySalary(staffId, month(), 1200000);
      await repository.setMonthlySalary(staffId, month(), null);
      expect(await repository.salaryForMonth(staffId, month()), isNull);
    });

    test('negative salary is rejected', () {
      expect(
        repository.setMonthlySalary(staffId, month(), -100),
        throwsA(isA<StaffPayrollNegativeSalaryFailure>()),
      );
    });

    test('advance history is saved with a visible total', () async {
      await repository.addAdvance(
        staffUserId: staffId,
        amountPaise: 50000,
        advanceDate: day(5),
        note: 'Festival',
      );
      await repository.addAdvance(
        staffUserId: staffId,
        amountPaise: 25000,
        advanceDate: day(12),
      );
      final advances = await repository.advancesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      expect(advances, hasLength(2));
      expect(advances.fold(0, (sum, a) => sum + a.amountPaise), 75000);
    });

    test('negative advance is rejected', () {
      expect(
        repository.addAdvance(
          staffUserId: staffId,
          amountPaise: -100,
          advanceDate: day(5),
        ),
        throwsA(isA<StaffPayrollNegativeAdvanceFailure>()),
      );
    });

    test('final payable = manual salary minus advances', () async {
      await repository.setMonthlySalary(staffId, month(), 1200000);
      await repository.addAdvance(
        staffUserId: staffId,
        amountPaise: 200000,
        advanceDate: day(5),
      );
      final salary = await repository.salaryForMonth(staffId, month());
      final advances = await repository.advancesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      final summary = MonthlyPayrollSummary(
        shifts: const [],
        advances: advances,
        manualSalaryPaise: salary,
        openShift: null,
      );
      expect(summary.payablePaise, 1000000);
    });
  });

  group('daily salary → calculated monthly salary', () {
    test('daily salaries are stored per day and load back', () async {
      expect(
        await repository.dailySalariesFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
        ),
        isEmpty,
      );
      await repository.setDailySalary(staffId, day(1), 30000);
      await repository.setDailySalary(staffId, day(2), 30000);
      await repository.setDailySalary(staffId, day(3), 45000);

      final daily = await repository.dailySalariesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      expect(daily, hasLength(3));
      expect(daily.fold(0, (sum, d) => sum + d.salaryPaise), 105000);
    });

    test(
      'setting a day twice keeps ONE row and updates the last amount',
      () async {
        await repository.setDailySalary(staffId, day(1), 30000);
        await repository.setDailySalary(staffId, day(1), 35000);

        final daily = await repository.dailySalariesFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
        );
        expect(daily, hasLength(1));
        expect(daily.single.salaryPaise, 35000);
      },
    );

    test('updating a day recalculates the monthly sum', () async {
      await repository.setDailySalary(staffId, day(1), 30000);
      await repository.setDailySalary(staffId, day(2), 40000);
      await repository.setDailySalary(staffId, day(1), 35000);

      final daily = await repository.dailySalariesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      expect(daily.fold(0, (sum, d) => sum + d.salaryPaise), 75000);
    });

    test('clearing a daily salary removes the row', () async {
      await repository.setDailySalary(staffId, day(1), 30000);
      await repository.setDailySalary(staffId, day(1), null);

      final daily = await repository.dailySalariesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      expect(daily, isEmpty);
    });

    test('negative daily salary is rejected', () {
      expect(
        repository.setDailySalary(staffId, day(1), -100),
        throwsA(isA<StaffPayrollNegativeSalaryFailure>()),
      );
    });

    test('summary derives the monthly salary from the daily amounts', () async {
      await repository.setDailySalary(staffId, day(1), 30000);
      await repository.setDailySalary(staffId, day(2), 45000);

      final daily = await repository.dailySalariesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      final summary = MonthlyPayrollSummary(
        shifts: const [],
        advances: const [],
        manualSalaryPaise: null,
        openShift: null,
        dailySalaries: daily,
      );
      expect(summary.calculatedSalaryPaise, 75000);
      expect(summary.effectiveSalaryPaise, 75000);
      expect(summary.payablePaise, 75000);
    });

    test('manual override still wins over the daily-derived sum', () async {
      await repository.setDailySalary(staffId, day(1), 30000);
      await repository.setMonthlySalary(staffId, month(), 1200000);

      final daily = await repository.dailySalariesFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
      );
      final summary = MonthlyPayrollSummary(
        shifts: const [],
        advances: const [],
        manualSalaryPaise: await repository.salaryForMonth(staffId, month()),
        openShift: null,
        dailySalaries: daily,
      );
      expect(summary.calculatedSalaryPaise, 30000);
      expect(summary.effectiveSalaryPaise, 1200000);
      expect(summary.payablePaise, 1200000);
    });

    test(
      'daily salaries sync to the cloud and a second device sees them',
      () async {
        await repository.setDailySalary(staffId, day(1), 30000);
        await repository.setDailySalary(staffId, day(2), 45000);
        expect(cloud.calls, contains('upsertDailySalary'));

        // A fresh owner device against the same cloud reads both amounts back.
        final database2 = AppDatabase(NativeDatabase.memory());
        addTearDown(database2.close);
        await seedProfile(db: database2);
        final repository2 = DriftStaffPayrollRepository(
          database2,
          cloudGateway: cloud,
        );
        final daily = await repository2.dailySalariesFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
          shopIds: [cafeShop],
        );
        expect(daily, hasLength(2));
        expect(daily.fold(0, (sum, d) => sum + d.salaryPaise), 75000);
      },
    );

    test(
      'cross-device same-day edits converge to ONE row with the newest amount',
      () async {
        await repository.setDailySalary(staffId, day(1), 30000);

        final database2 = AppDatabase(NativeDatabase.memory());
        addTearDown(database2.close);
        await seedProfile(db: database2);
        final repository2 = DriftStaffPayrollRepository(
          database2,
          cloudGateway: cloud,
        );
        await repository2.setDailySalary(staffId, day(1), 50000);

        final daily = await repository.dailySalariesFor(
          staffUserId: staffId,
          startDate: DateTime.utc(2025, 7, 1),
          endExclusiveDate: DateTime.utc(2025, 8, 1),
          shopIds: [cafeShop],
        );
        expect(daily, hasLength(1));
        expect(daily.single.salaryPaise, 50000);
      },
    );
  });

  group('business isolation', () {
    test('reads scoped to one shop hide the other shop rows', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, 3, 11, 30),
      );

      final cafe = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(cafe, hasLength(1));

      final truck = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [truckShop],
      );
      expect(truck, isEmpty);
    });
  });

  group('cloud behavior', () {
    Future<String> closedShift(int dayOfMonth) async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, dayOfMonth, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, dayOfMonth, 11, 30),
      );
      final shifts = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      return shifts.firstWhere((s) => s.attendanceDate == day(dayOfMonth)).id;
    }

    test('writes push attendance, advances and salary to the cloud', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, 3, 11, 30),
      );
      await repository.addAdvance(
        staffUserId: staffId,
        amountPaise: 50000,
        advanceDate: day(5),
      );
      await repository.setMonthlySalary(staffId, month(), 1200000);

      expect(cloud.storedShifts, hasLength(1));
      expect(cloud.shiftShopIds.single, cafeShop);
      expect(cloud.storedAdvances, hasLength(1));
      expect(cloud.advanceShopIds.single, cafeShop);
      expect(cloud.storedSalaries, hasLength(1));
      expect(cloud.storedSalaries.single.salaryPaise, 1200000);
    });

    test('a second device loads the first device records from cloud', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, 3, 11, 30),
      );
      await repository.setMonthlySalary(staffId, month(), 1200000);

      // A real second device mints its OWN local profile id for the same human
      // while sharing the auth id. Keying the cloud on the local id made this
      // exact scenario return nothing on hardware, so the local id is
      // deliberately different here.
      const device2StaffId = 'staff-1-on-device-2';
      final device2 = AppDatabase(NativeDatabase.memory());
      addTearDown(device2.close);
      await seedProfile(db: device2, userId: device2StaffId);
      final repo2 = DriftStaffPayrollRepository(device2, cloudGateway: cloud);

      final shifts = await repo2.attendanceFor(
        staffUserId: device2StaffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(shifts, hasLength(1));
      expect(shifts.single.workedMinutes, 480);
      // Mirrored under device 2's own local id, so its own local reads work.
      expect(shifts.single.staffUserId, device2StaffId);
      expect(await repo2.salaryForMonth(device2StaffId, month()), 1200000);
    });

    test('a shift opened on one device is seen as open on the other', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.now().toUtc(),
      );

      // Device 2 has its own local id but the same auth id. An open shift is
      // live state, so device 2 must see it rather than let the same person
      // clock in a second time.
      const device2StaffId = 'staff-1-on-device-2';
      final device2 = AppDatabase(NativeDatabase.memory());
      addTearDown(device2.close);
      await seedProfile(db: device2, userId: device2StaffId);
      final repo2 = DriftStaffPayrollRepository(device2, cloudGateway: cloud);

      final open = await repo2.openShiftFor(device2StaffId);
      expect(open, isNotNull);
      expect(open!.staffUserId, device2StaffId);

      // And a second clock-in for that person is refused, not duplicated.
      await expectLater(
        repo2.clockIn(
          staffUserId: device2StaffId,
          inAt: DateTime.now().toUtc(),
        ),
        throwsA(isA<StaffPayrollFailure>()),
      );
      expect(cloud.storedShifts, hasLength(1));
    });

    test('pre-re-key history is re-claimed and becomes visible', () async {
      // A row written before the cloud was keyed on auth_user_id: same
      // primary key, but no auth id, so an auth-keyed fetch cannot see it.
      final legacyShiftId = await closedShift(6);
      cloud.shiftAuthIds[0] = null;
      expect(cloud.shiftAuthIds.single, isNull);

      // The originating device re-claims its own rows during the pull, which
      // is what recovers history stranded under a device-local id.
      final after = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(after.map((s) => s.id), contains(legacyShiftId));
      expect(cloud.shiftAuthIds.single, authId);
    });

    test('a re-claim never revives a genuinely deleted shift', () async {
      final id = await closedShift(7);
      await repository.deleteAttendance(staffId, id);

      // The row is gone from the cloud, so there is nothing to claim and the
      // repair must not bring it back on the next read.
      expect(cloud.storedShifts, isEmpty);
      final after = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(after.map((s) => s.id), isNot(contains(id)));
    });

    test('cloud failure falls back to the local mirror', () async {
      await repository.clockIn(
        staffUserId: staffId,
        inAt: DateTime.utc(2025, 7, 3, 3, 30),
      );
      await repository.clockOut(
        staffUserId: staffId,
        outAt: DateTime.utc(2025, 7, 3, 11, 30),
      );

      cloud.failNext = true;
      final shifts = await repository.attendanceFor(
        staffUserId: staffId,
        startDate: DateTime.utc(2025, 7, 1),
        endExclusiveDate: DateTime.utc(2025, 8, 1),
        shopIds: [cafeShop],
      );
      expect(shifts, hasLength(1));
    });
  });
}
