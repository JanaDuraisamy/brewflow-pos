import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_payroll_page.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Standalone Staff Attendance Page
///
/// Locks the standalone contract: the route opens without any entry staff
/// and defaults to the first roster member, the roster selector switches
/// between members, and the daily summary (date, clock-in/out, working hours,
/// status) plus the monthly "Total Working Days" surface the recorded data.
/// ---------------------------------------------------------------------------

void main() {
  late AppDatabase database;
  late DriftStaffPayrollRepository payroll;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    payroll = DriftStaffPayrollRepository(database);
    addTearDown(database.close);
    await database
        .into(database.shops)
        .insert(
          ShopsCompanion.insert(id: const Value('shop-1'), name: 'shop-1'),
        );
  });

  Future<FakeStaffRepository> staffRepoWith(List<String> emails) async {
    final repo = FakeStaffRepository();
    await repo.claimOwnership(const AuthUser(id: 'o-1', email: 'o@x.co'));
    for (final email in emails) {
      final profile = await repo.createStaffProfile(
        identity: AuthUser(id: 'u-$email', email: email),
        shopId: 'shop-1',
      );
      await database
          .into(database.users)
          .insert(
            UsersCompanion.insert(
              id: Value(profile.id),
              email: profile.email,
              shopId: const Value('shop-1'),
              role: const Value('STAFF'),
            ),
          );
    }
    return repo;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    FakeStaffRepository staffRepo,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(database),
          staffPayrollRepositoryProvider.overrideWithValue(payroll),
          // Session-gated payroll read; `staff` supplies the roster override
          // (Riverpod forbids overriding the same provider twice).
          ...businessScopeOverrides(
            staff: staffRepo,
            profile: testOwnerProfile(),
          ),
        ],
        child: const MaterialApp(home: StaffPayrollPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('standalone route defaults to the first member and shows the '
      'daily + monthly summary cards', (tester) async {
    final staffRepo = await staffRepoWith(['a@x.co', 'b@x.co']);
    await pumpPage(tester, staffRepo);

    expect(tester.takeException(), isNull);

    // Default selection is the first roster member, shown in the selector.
    expect(find.text('a@x.co'), findsWidgets);

    // Daily summary card: date, clock-in/out, working hours and status. The
    // Clock In/Clock Out row labels share text with the toggle buttons below,
    // so they are assertable via findsWidgets.
    expect(find.text('Daily summary'), findsOneWidget);
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Clock In'), findsWidgets);
    expect(find.text('Clock Out'), findsWidgets);
    expect(find.text('Working Hours'), findsOneWidget);
    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Absent'), findsOneWidget);

    // Monthly summary card surfaces Total Working Days next to hours.
    expect(find.text('Total Working Days'), findsOneWidget);
    expect(find.text('Total Working Hours'), findsOneWidget);
    expect(find.text('0 h'), findsWidgets);
  });

  testWidgets('a recorded day shows Present with hours and working days', (
    tester,
  ) async {
    final staffRepo = await staffRepoWith(['a@x.co', 'b@x.co']);
    final now = DateTime.now();
    await payroll.clockIn(
      staffUserId: staffRepo.storedProfiles[1].id,
      inAt: now,
    );
    await payroll.clockOut(
      staffUserId: staffRepo.storedProfiles[1].id,
      outAt: now.add(const Duration(hours: 8)),
    );
    await pumpPage(tester, staffRepo);

    expect(tester.takeException(), isNull);
    expect(find.text('Present'), findsOneWidget);
    // 8h in the daily card and 8h in the monthly total.
    expect(find.text('8 h'), findsWidgets);
    // The month has exactly one working day.
    final labels = find.text('Total Working Days');
    expect(
      find.descendant(
        of: find.ancestor(of: labels, matching: find.byType(Padding)).first,
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the roster selector switches the viewed member', (tester) async {
    final staffRepo = await staffRepoWith(['a@x.co', 'b@x.co']);
    await pumpPage(tester, staffRepo);
    expect(find.text('a@x.co'), findsWidgets);

    await tester.tap(find.byType(DropdownButton<UserProfile>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('b@x.co').last);
    await tester.pumpAndSettle();

    expect(find.text('b@x.co'), findsWidgets);
    expect(find.text('Absent'), findsOneWidget);
  });

  testWidgets('an empty roster shows the no-staff empty state', (tester) async {
    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(const AuthUser(id: 'o-1', email: 'o@x.co'));
    await pumpPage(tester, staffRepo);

    expect(find.text('No staff yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('salary rows clearly present unset daily and monthly values', (
    tester,
  ) async {
    final staffRepo = await staffRepoWith(['a@x.co']);
    await pumpPage(tester, staffRepo);

    // Daily card carries the per-day salary row; the monthly card breaks the
    // salary into the calculated sum and the effective monthly salary.
    expect(find.text('Daily Salary'), findsOneWidget);
    expect(find.text('Calculated Salary'), findsOneWidget);
    expect(find.text('Monthly Salary'), findsOneWidget);
    // Nothing set yet: the daily row and the monthly row both notify the owner.
    expect(find.text('Not set'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a daily salary feeds the calculated monthly salary', (
    tester,
  ) async {
    final staffRepo = await staffRepoWith(['a@x.co', 'b@x.co']);
    final now = DateTime.now();
    await payroll.clockIn(
      staffUserId: staffRepo.storedProfiles[1].id,
      inAt: now,
    );
    await payroll.clockOut(
      staffUserId: staffRepo.storedProfiles[1].id,
      outAt: now.add(const Duration(hours: 8)),
    );
    await payroll.setDailySalary(
      staffRepo.storedProfiles[1].id,
      DateTime.utc(now.year, now.month, now.day),
      30000,
    );
    await pumpPage(tester, staffRepo);

    expect(tester.takeException(), isNull);
    // ₹300 for the day appears on the daily card, the calculated monthly
    // row, the effective monthly row and the attendance history.
    expect(find.text('₹300.00'), findsWidgets);
    // The monthly salary follows the daily entries (not an owner override).
    expect(find.text('Auto-calculated from daily entries'), findsOneWidget);
    // Final payable resolves to the calculated amount.
    expect(find.text('Final Payable'), findsOneWidget);
    expect(find.text('₹300.00'), findsWidgets);
  });

  group('attendance deletion', () {
    /// The owner's own id: [staffRepoWith] claims ownership for it.
    const ownerAuth = AuthUser(id: 'o-1', email: 'o@x.co');

    Future<void> pumpSession(
      WidgetTester tester,
      FakeStaffRepository staffRepo,
      AuthUser user, {
      UserProfile? profile,
    }) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1200, 1600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            staffRepositoryProvider.overrideWithValue(staffRepo),
            staffPayrollRepositoryProvider.overrideWithValue(payroll),
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(user: user),
            ),
            // Payroll reads are session-gated and fail closed on an unresolved
            // profile. Owner sessions therefore state the profile outright;
            // a staff session omits it so the real derivation (own id + own
            // shop) is exercised instead.
            if (profile != null)
              userProfileProvider.overrideWithBuild((ref, notifier) => profile),
          ],
          child: const MaterialApp(home: StaffPayrollPage()),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Records one closed 8h shift for the first roster member.
    Future<String> recordShift(FakeStaffRepository staffRepo) async {
      final memberId = staffRepo.storedProfiles[1].id;
      final now = DateTime.now();
      await payroll.clockIn(staffUserId: memberId, inAt: now);
      await payroll.clockOut(
        staffUserId: memberId,
        outAt: now.add(const Duration(hours: 8)),
      );
      return memberId;
    }

    testWidgets('the owner gets one Delete action per attendance entry', (
      tester,
    ) async {
      final staffRepo = await staffRepoWith(['a@x.co']);
      await recordShift(staffRepo);
      await pumpSession(
        tester,
        staffRepo,
        ownerAuth,
        profile: testOwnerProfile(),
      );

      // The owner session resolved for real, so the action is shown because
      // the owner check passed.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StaffPayrollPage)),
        listen: false,
      );
      final profile = await container.read(userProfileProvider.future);
      expect(profile!.isOwner, isTrue);
      expect(find.text('Attendance'), findsOneWidget);
      expect(find.byTooltip('Delete attendance'), findsOneWidget);
    });

    testWidgets('a staff session never sees the Delete action', (tester) async {
      final staffRepo = await staffRepoWith(['a@x.co']);
      await recordShift(staffRepo);
      // 'a@x.co' was created as a staff profile by staffRepoWith.
      await pumpSession(
        tester,
        staffRepo,
        const AuthUser(id: 'u-a@x.co', email: 'a@x.co'),
      );

      expect(tester.takeException(), isNull);
      // The session really resolved to a non-owner, so the action is hidden by
      // the owner check and not merely because no profile was available.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(StaffPayrollPage)),
        listen: false,
      );
      final profile = await container.read(userProfileProvider.future);
      expect(profile, isNotNull);
      expect(profile!.isOwner, isFalse);
      // The history row is visible to the staff member...
      expect(find.text('Attendance'), findsOneWidget);
      // ...but there is no Delete affordance anywhere on the page.
      expect(find.byTooltip('Delete attendance'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('deleting asks for confirmation first', (tester) async {
      final staffRepo = await staffRepoWith(['a@x.co']);
      final memberId = await recordShift(staffRepo);
      await pumpSession(
        tester,
        staffRepo,
        ownerAuth,
        profile: testOwnerProfile(),
      );

      await tester.tap(find.byTooltip('Delete attendance'));
      await tester.pumpAndSettle();

      // A named, explicit confirmation — not an instant delete.
      expect(find.text('Delete attendance'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Delete'), findsOneWidget);
      expect(
        find.textContaining('This cannot be undone', findRichText: true),
        findsOneWidget,
      );

      // Cancelling keeps the shift.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete attendance'), findsOneWidget);
      final kept = await database.select(database.staffAttendance).get();
      expect(kept, hasLength(1));
      expect(kept.single.staffUserId, memberId);
    });

    testWidgets('confirming removes the entry and recalculates the month', (
      tester,
    ) async {
      final staffRepo = await staffRepoWith(['a@x.co']);
      final memberId = await recordShift(staffRepo);
      await payroll.setDailySalary(
        memberId,
        DateTime.utc(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        ),
        30000,
      );
      await pumpSession(
        tester,
        staffRepo,
        ownerAuth,
        profile: testOwnerProfile(),
      );

      // The recorded month: one working day, 8h, ₹300 payable.
      expect(find.byTooltip('Delete attendance'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete attendance'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // The entry is gone from the history and from the local mirror.
      expect(find.text('No attendance recorded this month.'), findsOneWidget);
      expect(find.byTooltip('Delete attendance'), findsNothing);
      expect(await database.select(database.staffAttendance).get(), isEmpty);
      // Working days and hours were recalculated to zero.
      expect(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('Total Working Days'),
                matching: find.byType(Padding),
              )
              .first,
          matching: find.text('0'),
        ),
        findsOneWidget,
      );
      expect(find.text('0 h'), findsWidgets);
    });
  });
}
