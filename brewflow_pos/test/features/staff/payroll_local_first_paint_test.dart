import 'dart:async';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/data/staff_payroll_cloud_gateway.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_staff_repository.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Payroll local-first paint contract.
///
/// Taps must paint from the device mirror immediately while cloud
/// reconciliation continues behind: Clock In returns with the shift already
/// visible even though the cloud fetch it triggered has not answered yet.
/// The sync architecture (pulls, conflict rules, retry) is unchanged — it
/// just runs asynchronously after the paint.
/// ---------------------------------------------------------------------------

/// Cloud gateway double that blocks every read behind [fetchGate] while
/// letting writes through immediately.
final class _GatedCloudGateway implements StaffPayrollCloudGateway {
  _GatedCloudGateway();

  final Completer<void> fetchGate = Completer<void>();
  int fetchCalls = 0;

  Future<void> _wait() => fetchGate.future;

  @override
  Future<void> claimLegacyRows({
    required StaffPayrollTable table,
    required String shopId,
    required String localStaffUserId,
    required String authUserId,
  }) async {}

  @override
  Future<List<StaffAttendanceRecord>> fetchAttendance({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    fetchCalls++;
    await _wait();
    return const [];
  }

  @override
  Future<void> upsertAttendance({
    required String shopId,
    required String authUserId,
    required StaffAttendanceRecord record,
  }) async {}

  @override
  Future<void> deleteAttendance({
    required String shopId,
    required String authUserId,
    required String shiftId,
  }) async {}

  @override
  Future<List<StaffAdvanceEntry>> fetchAdvances({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    await _wait();
    return const [];
  }

  @override
  Future<void> insertAdvance({
    required String shopId,
    required String authUserId,
    required StaffAdvanceEntry entry,
  }) async {}

  @override
  Future<CloudMonthlySalary?> fetchSalary({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime monthDate,
  }) async {
    await _wait();
    return null;
  }

  @override
  Future<void> upsertSalary({
    required String authUserId,
    required CloudMonthlySalary salary,
  }) async {}

  @override
  Future<void> deleteSalary({
    required String shopId,
    required String authUserId,
    required DateTime monthDate,
  }) async {}

  @override
  Future<List<CloudDailySalary>> fetchDailySalaries({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    await _wait();
    return const [];
  }

  @override
  Future<void> upsertDailySalary({
    required String shopId,
    required String authUserId,
    required CloudDailySalary salary,
  }) async {}

  @override
  Future<void> deleteDailySalary({
    required String shopId,
    required String authUserId,
    required DateTime attendanceDate,
  }) async {}
}

void main() {
  const cafeShop = 'shop-cafe';
  const staffId = 'staff-1';

  late AppDatabase database;
  late _GatedCloudGateway cloud;

  ProviderContainer container() => ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      staffPayrollRepositoryProvider.overrideWithValue(
        DriftStaffPayrollRepository(database, cloudGateway: cloud),
      ),
      ...businessScopeOverrides(profile: testOwnerProfile(shopId: cafeShop)),
    ],
  );

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    cloud = _GatedCloudGateway();
    await database
        .into(database.shops)
        .insert(ShopsCompanion.insert(id: const Value(cafeShop), name: 'Cafe'));
    await database
        .into(database.users)
        .insert(
          UsersCompanion.insert(
            id: const Value(staffId),
            email: '$staffId@brewflow.example',
            shopId: const Value(cafeShop),
            role: const Value('STAFF'),
            authUserId: const Value('auth-1'),
          ),
        );
  });

  test(
    'clock in paints immediately while cloud fetch is still pending',
    () async {
      final c = container();
      addTearDown(c.dispose);

      // Prime the summary; its background reconciliation blocks on the gate.
      await c.read(payrollSummaryProvider(staffId).future);

      final inAt = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await c
          .read(payrollSummaryProvider(staffId).notifier)
          .clockIn(inAt: inAt);

      // The mutation returned with the shift already visible — the summary did
      // not wait for the still-blocked cloud fetch.
      final summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(
        summary.shifts.where((s) => !s.isLeave),
        hasLength(1),
        reason: 'the clocked-in shift paints from the local mirror at once',
      );
      expect(
        cloud.fetchGate.isCompleted,
        isFalse,
        reason: 'the cloud fetch genuinely had not answered yet',
      );
    },
  );

  test(
    'background reconciliation still pulls once the cloud answers',
    () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(payrollSummaryProvider(staffId).future);
      final callsBefore = cloud.fetchCalls;
      cloud.fetchGate.complete();

      // Let the pending background reconciliation run to completion.
      for (var i = 0; i < 200 && cloud.fetchCalls == callsBefore; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(cloud.fetchCalls, greaterThan(callsBefore));
      // The view refreshes after reconciliation without losing local data.
      final summary = await c.read(payrollSummaryProvider(staffId).future);
      expect(summary.shifts, isEmpty);
    },
  );
}
