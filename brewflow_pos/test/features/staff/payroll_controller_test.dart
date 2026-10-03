import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Payroll Controller Regression
///
/// Locks the provider wiring: the monthly summary serves the staff profile's
/// own shop scope, daily salary mutations sum into the calculated salary,
/// manual-salary mutations override the sum, advances reduce the final
/// payable, and clock in/out flow through to worked minutes. Pure
/// calculation rules live in payroll_math_test; persistence rules live in
/// payroll_repository_test.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;

  const cafeShop = 'shop-cafe';
  const staffId = 'staff-1';

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        staffPayrollRepositoryProvider.overrideWithValue(
          DriftStaffPayrollRepository(database),
        ),
        // Payroll reads are session-gated: an unresolved profile fails closed,
        // so the fixture has to declare who is signed in. An OWNER may read
        // any staff member's payroll, scoped to that member's own business.
        ...businessScopeOverrides(profile: testOwnerProfile(shopId: cafeShop)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    for (final shop in [cafeShop, 'shop-truck']) {
      await database
          .into(database.shops)
          .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
    }
    await database
        .into(database.users)
        .insert(
          UsersCompanion.insert(
            id: const Value(staffId),
            email: '$staffId@brewflow.example',
            shopId: const Value(cafeShop),
            role: const Value('STAFF'),
          ),
        );
  });

  test('summary starts unset then reflects the manual salary', () async {
    final c = container();
    var summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.manualSalaryPaise, isNull);
    expect(summary.payablePaise, isNull);

    await c
        .read(payrollSummaryProvider(staffId).notifier)
        .setMonthlySalary(1200000);
    summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.manualSalaryPaise, 1200000);
    expect(summary.payablePaise, 1200000);
  });

  test('advances reduce the payable through the controller', () async {
    final c = container();
    final notifier = c.read(payrollSummaryProvider(staffId).notifier);
    await notifier.setMonthlySalary(1200000);
    final now = DateTime.now();
    await notifier.addAdvance(
      amountPaise: 200000,
      advanceDate: DateTime.utc(now.year, now.month, 5),
    );

    final summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.advancePaise, 200000);
    expect(summary.payablePaise, 1000000);
  });

  test('clock in/out through the controller feeds worked minutes', () async {
    final c = container();
    final notifier = c.read(payrollSummaryProvider(staffId).notifier);
    // Mid-month dates always fall inside the controller's selected month.
    final now = DateTime.now().toUtc();
    final inAt = DateTime.utc(now.year, now.month, 15, 3, 30);
    await notifier.clockIn(inAt: inAt);
    var summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.openShift, isNotNull);

    await notifier.clockOut(outAt: inAt.add(const Duration(hours: 8)));
    summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.openShift, isNull);
    expect(summary.totalMinutes, 480);
  });

  test(
    'daily salary edits recalculate the calculated monthly salary',
    () async {
      final c = container();
      final notifier = c.read(payrollSummaryProvider(staffId).notifier);
      final now = DateTime.now();
      final day1 = DateTime.utc(now.year, now.month, 5);
      final day2 = DateTime.utc(now.year, now.month, 10);
      await notifier.setDailySalary(day1, 30000);
      await notifier.setDailySalary(day2, 45000);
      var summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.calculatedSalaryPaise, 75000);
      expect(summary.effectiveSalaryPaise, 75000);
      expect(summary.payablePaise, 75000);

      // A corrected day updates the month's calculated salary and payable.
      await notifier.setDailySalary(day1, 35000);
      summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.calculatedSalaryPaise, 80000);
      expect(summary.effectiveSalaryPaise, 80000);
      expect(summary.payablePaise, 80000);
    },
  );

  test('advances reduce the payable derived from daily salaries', () async {
    final c = container();
    final notifier = c.read(payrollSummaryProvider(staffId).notifier);
    final now = DateTime.now();
    await notifier.setDailySalary(DateTime.utc(now.year, now.month, 5), 100000);
    await notifier.addAdvance(
      amountPaise: 40000,
      advanceDate: DateTime.utc(now.year, now.month, 6),
    );

    final summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.calculatedSalaryPaise, 100000);
    expect(summary.payablePaise, 60000);
  });

  test('manual monthly salary overrides the daily-derived sum', () async {
    final c = container();
    final notifier = c.read(payrollSummaryProvider(staffId).notifier);
    final now = DateTime.now();
    await notifier.setDailySalary(DateTime.utc(now.year, now.month, 5), 30000);
    await notifier.setMonthlySalary(1200000);

    final summary = await c.read(payrollSummaryProvider(staffId).future);
    expect(summary.manualSalaryPaise, 1200000);
    expect(summary.calculatedSalaryPaise, 30000);
    expect(summary.effectiveSalaryPaise, 1200000);
    expect(summary.payablePaise, 1200000);
  });

  group('attendance deletion', () {
    /// A container whose signed-in identity resolves to [role] through
    /// [FakeStaffRepository], exactly like production.
    ProviderContainer containerAs(UserRole role) {
      final staff = FakeStaffRepository();
      staff.profilesByAuthId['a-1'] = const UserProfile(
        id: 'owner-1',
        email: 'o@brewflow.example',
        authUserId: 'a-1',
        role: UserRole.owner,
        isActive: true,
        permissions: {},
      );
      staff.profilesByAuthId['a-2'] = const UserProfile(
        id: 'staff-2',
        email: 's@brewflow.example',
        authUserId: 'a-2',
        role: UserRole.staff,
        isActive: true,
        permissions: {},
      );
      final authId = role == UserRole.owner ? 'a-1' : 'a-2';
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          staffPayrollRepositoryProvider.overrideWithValue(
            DriftStaffPayrollRepository(database),
          ),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              user: AuthUser(id: authId, email: '$authId@x.co'),
            ),
          ),
          staffRepositoryProvider.overrideWithValue(staff),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    /// Records a closed shift in the controller's selected month and returns
    /// its id.
    Future<String> seedMonthShift(
      ProviderContainer c, {
      required int dayOfMonth,
    }) async {
      final notifier = c.read(payrollSummaryProvider(staffId).notifier);
      final now = DateTime.now();
      final start = DateTime.utc(now.year, now.month, dayOfMonth, 3, 30);
      await notifier.clockIn(inAt: start);
      await notifier.clockOut(outAt: start.add(const Duration(hours: 8)));
      final summary = await c.read(payrollSummaryProvider(staffId).future);
      return summary.shifts.last.id;
    }

    test('the owner can delete a shift and the month recalculates', () async {
      final c = containerAs(UserRole.owner);
      await c.read(userProfileProvider.future);
      final notifier = c.read(payrollSummaryProvider(staffId).notifier);
      final now = DateTime.now();
      final first = await seedMonthShift(c, dayOfMonth: 5);
      await seedMonthShift(c, dayOfMonth: 12);
      // A daily salary and an advance make the payable depend on the reload.
      await notifier.setDailySalary(
        DateTime.utc(now.year, now.month, 5),
        30000,
      );
      await notifier.setDailySalary(
        DateTime.utc(now.year, now.month, 12),
        40000,
      );
      await notifier.addAdvance(
        amountPaise: 10000,
        advanceDate: DateTime.utc(now.year, now.month, 6),
      );

      var summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.totalWorkingDays, 2);
      expect(summary.totalMinutes, 960);
      expect(summary.calculatedSalaryPaise, 70000);
      expect(summary.payablePaise, 60000);

      await notifier.deleteAttendance(first);

      summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.shifts, hasLength(1));
      expect(summary.totalWorkingDays, 1);
      expect(summary.totalMinutes, 480);
      // The owner's per-day salary inputs are not silently destroyed by
      // removing a shift; salary and payable are recomputed from what
      // remains, and the removed shift no longer counts anywhere.
      expect(summary.calculatedSalaryPaise, 70000);
      expect(summary.payablePaise, 60000);
    });

    test(
      'deleting the last shift empties the working days and hours',
      () async {
        final c = containerAs(UserRole.owner);
        await c.read(userProfileProvider.future);
        final id = await seedMonthShift(c, dayOfMonth: 5);

        await c
            .read(payrollSummaryProvider(staffId).notifier)
            .deleteAttendance(id);

        final summary = await c.read(payrollSummaryProvider(staffId).future);
        expect(summary.shifts, isEmpty);
        expect(summary.totalWorkingDays, 0);
        expect(summary.totalMinutes, 0);
      },
    );

    test('a staff session cannot delete an attendance shift', () async {
      final ownerContainer = containerAs(UserRole.owner);
      await ownerContainer.read(userProfileProvider.future);
      final id = await seedMonthShift(ownerContainer, dayOfMonth: 5);

      final c = containerAs(UserRole.staff);
      final profile = await c.read(userProfileProvider.future);
      expect(profile!.isOwner, isFalse);
      final notifier = c.read(payrollSummaryProvider(staffId).notifier);

      await expectLater(
        notifier.deleteAttendance(id),
        throwsA(isA<PermissionDeniedFailure>()),
      );

      // The row survives the refused delete. Verified through the owner
      // session, because a staff session may only read its OWN payroll.
      final ownerSummary = await ownerContainer.read(
        payrollSummaryProvider(staffId).future,
      );
      expect(ownerSummary.shifts.map((s) => s.id), [id]);

      // A staff session cannot even read another member's payroll.
      final staffView = await c.read(payrollSummaryProvider(staffId).future);
      expect(staffView.shifts, isEmpty);
    });
  });

  // Regression: the scope resolver used to return null — the repositories'
  // "every business" value — for a staff row with no shop_id AND for any
  // exception while reading the profile. Payroll carries attendance hours,
  // salary and advances, so a failed lookup silently widened the read across
  // Cafe and Food Truck. Every unresolvable case must now yield no rows.
  group('payroll read scope', () {
    const truckShop = 'shop-truck';

    /// A container whose session profile is exactly [profile].
    ProviderContainer sessionAs(UserProfile profile) {
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          staffPayrollRepositoryProvider.overrideWithValue(
            DriftStaffPayrollRepository(database),
          ),
          ...businessScopeOverrides(profile: profile),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    Future<void> addShift(
      String shopId,
      String day, {
      String forStaff = staffId,
    }) async {
      // The summary provider defaults to the current month, so the shift has to
      // land inside it.
      final now = DateTime.now();
      final d = int.parse(day);
      await database
          .into(database.staffAttendance)
          .insert(
            StaffAttendanceCompanion.insert(
              id: Value('a-$forStaff-$shopId-$day'),
              staffUserId: forStaff,
              shopId: Value(shopId),
              inAt: DateTime.utc(now.year, now.month, d, 9),
              outAt: Value(DateTime.utc(now.year, now.month, d, 17)),
              workedMinutes: const Value(480),
              attendanceDate: DateTime.utc(now.year, now.month, d),
            ),
          );
    }

    test('an owner reads payroll scoped to the staff member business', () async {
      await addShift(cafeShop, '5');
      await addShift(truckShop, '6');

      final c = sessionAs(testOwnerProfile(shopId: cafeShop));
      await c.read(payrollSummaryProvider(staffId).future);

      // `staff-1` belongs to the Cafe, so the truck shift must not appear even
      // though the owner could switch to Combined. `StaffAttendanceRecord`
      // carries no shop, so the count is what proves the scoping.
      final summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.shifts, hasLength(1));
      expect(summary.totalMinutes, 480);
    });

    test(
      'a staff row with no shop resolves to no rows, not every shop',
      () async {
        // A legacy staff row whose shop_id is NULL.
        await database
            .into(database.users)
            .insert(
              UsersCompanion.insert(
                id: const Value('legacy-staff'),
                email: 'legacy@brewflow.example',
                shopId: const Value(null),
                role: const Value('STAFF'),
              ),
            );
        await addShift(cafeShop, '5', forStaff: 'legacy-staff');

        final c = sessionAs(testOwnerProfile(shopId: cafeShop));
        final summary = await c.read(
          payrollSummaryProvider('legacy-staff').future,
        );
        // The row really exists, so an empty result proves the scope refused to
        // widen: failing wide here would show this member the Cafe's payroll.
        expect(
          summary.shifts,
          isEmpty,
          reason:
              'a staff row with no shop_id must read as no rows, not all rows',
        );
      },
    );

    test('an unresolved session profile reads no payroll', () async {
      await addShift(cafeShop, '5');

      // No profile override at all: the session cannot be classified as owner
      // or staff, so it must not be trusted with a payroll read.
      final c = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          staffPayrollRepositoryProvider.overrideWithValue(
            DriftStaffPayrollRepository(database),
          ),
        ],
      );
      addTearDown(c.dispose);

      final summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.shifts, isEmpty);
    });

    test('a staff session reads only its own payroll', () async {
      // `self-staff` is assigned to the Cafe and signs in as itself.
      await database
          .into(database.users)
          .insert(
            UsersCompanion.insert(
              id: const Value('self-staff'),
              email: 'self@brewflow.example',
              shopId: const Value(cafeShop),
              role: const Value('STAFF'),
            ),
          );
      await addShift(cafeShop, '5', forStaff: 'self-staff');
      await addShift(cafeShop, '6', forStaff: staffId);

      final own = sessionAs(
        const UserProfile(
          id: 'self-staff',
          email: 'self@brewflow.example',
          role: UserRole.staff,
          isActive: true,
          permissions: {},
          shopId: cafeShop,
        ),
      );
      final ownSummary = await own.read(
        payrollSummaryProvider('self-staff').future,
      );
      expect(ownSummary.shifts, isNotEmpty);

      final other = sessionAs(
        const UserProfile(
          id: 'self-staff',
          email: 'self@brewflow.example',
          role: UserRole.staff,
          isActive: true,
          permissions: {},
          shopId: cafeShop,
        ),
      );
      final otherSummary = await other.read(
        payrollSummaryProvider(staffId).future,
      );
      expect(otherSummary.shifts, isEmpty);
    });
  });
}
