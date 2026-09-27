import 'package:brewflow_pos/features/staff/data/staff_payroll_cloud_gateway.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — In-memory fake of [StaffPayrollCloudGateway]: acts as the
/// "second device" cloud store. Keyed by shop so business isolation is
/// testable. Set [failNext] to simulate offline/cloud errors (repository must
/// fall back to the local mirror).
///
/// Rows are keyed by the CROSS-DEVICE auth id, exactly like the real tables
/// (supabase/migrations/0028). The parallel `*AuthIds` lists hold a null for a
/// row written before the re-key, which is how a pre-migration cloud row is
/// simulated: it is invisible to an auth-keyed fetch until [claimLegacyRows]
/// attaches the identity. Filtering these by the device-local staff id instead
/// is what previously let the tests pass while real devices saw nothing.
/// ---------------------------------------------------------------------------

final class FakeStaffPayrollCloudGateway implements StaffPayrollCloudGateway {
  final List<StaffAttendanceRecord> storedShifts = [];
  final List<String> shiftShopIds = [];
  final List<String?> shiftAuthIds = [];
  final List<StaffAdvanceEntry> storedAdvances = [];
  final List<String> advanceShopIds = [];
  final List<String?> advanceAuthIds = [];
  final List<CloudMonthlySalary> storedSalaries = [];
  final List<String?> salaryAuthIds = [];
  final List<CloudDailySalary> storedDailySalaries = [];
  final List<String> dailySalaryShopIds = [];
  final List<String?> dailySalaryAuthIds = [];

  /// When true, the next cloud call throws (then resets to false).
  bool failNext = false;

  /// Every method call, in order, for behavior assertions.
  final List<String> calls = [];

  void _maybeFail(String call) {
    calls.add(call);
    if (failNext) {
      failNext = false;
      throw StateError('cloud unavailable');
    }
  }

  static bool _inRange(DateTime day, DateTime start, DateTime end) =>
      !day.isBefore(start) && day.isBefore(end);

  @override
  Future<void> claimLegacyRows({
    required StaffPayrollTable table,
    required String shopId,
    required String localStaffUserId,
    required String authUserId,
  }) async {
    _maybeFail('claimLegacyRows');
    // Only unclaimed rows written by this device, mirroring the real
    // `auth_user_id IS NULL AND staff_user_id = :localId` predicate.
    switch (table) {
      case StaffPayrollTable.attendance:
        for (var i = 0; i < shiftAuthIds.length; i++) {
          if (shiftAuthIds[i] == null &&
              shiftShopIds[i] == shopId &&
              storedShifts[i].staffUserId == localStaffUserId) {
            shiftAuthIds[i] = authUserId;
          }
        }
      case StaffPayrollTable.advances:
        for (var i = 0; i < advanceAuthIds.length; i++) {
          if (advanceAuthIds[i] == null &&
              advanceShopIds[i] == shopId &&
              storedAdvances[i].staffUserId == localStaffUserId) {
            advanceAuthIds[i] = authUserId;
          }
        }
      case StaffPayrollTable.monthlySalaries:
        for (var i = 0; i < salaryAuthIds.length; i++) {
          if (salaryAuthIds[i] == null &&
              storedSalaries[i].shopId == shopId &&
              storedSalaries[i].staffUserId == localStaffUserId) {
            salaryAuthIds[i] = authUserId;
          }
        }
      case StaffPayrollTable.dailySalaries:
        for (var i = 0; i < dailySalaryAuthIds.length; i++) {
          if (dailySalaryAuthIds[i] == null &&
              dailySalaryShopIds[i] == shopId &&
              storedDailySalaries[i].staffUserId == localStaffUserId) {
            dailySalaryAuthIds[i] = authUserId;
          }
        }
    }
  }

  @override
  Future<List<StaffAttendanceRecord>> fetchAttendance({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    _maybeFail('fetchAttendance');
    final result = <StaffAttendanceRecord>[];
    for (var i = 0; i < storedShifts.length; i++) {
      final shift = storedShifts[i];
      if (shiftShopIds[i] != shopId) continue;
      if (shiftAuthIds[i] != authUserId) continue;
      if (!_inRange(shift.attendanceDate, startDate, endExclusiveDate)) {
        continue;
      }
      // Re-stamped with the CALLER's local id, exactly like the real gateway:
      // the row was written by another device under its own local id, and the
      // local mirror is keyed by (and FK-constrained to) this device's users.
      result.add(
        StaffAttendanceRecord(
          id: shift.id,
          staffUserId: staffUserId,
          inAt: shift.inAt,
          outAt: shift.outAt,
          attendanceDate: shift.attendanceDate,
          workedMinutes: shift.workedMinutes,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> upsertAttendance({
    required String shopId,
    required String authUserId,
    required StaffAttendanceRecord record,
  }) async {
    _maybeFail('upsertAttendance');
    for (var i = 0; i < storedShifts.length; i++) {
      if (storedShifts[i].id == record.id) {
        storedShifts[i] = record;
        shiftShopIds[i] = shopId;
        shiftAuthIds[i] = authUserId;
        return;
      }
    }
    storedShifts.add(record);
    shiftShopIds.add(shopId);
    shiftAuthIds.add(authUserId);
  }

  @override
  Future<void> deleteAttendance({
    required String shopId,
    required String authUserId,
    required String shiftId,
  }) async {
    _maybeFail('deleteAttendance');
    for (var i = storedShifts.length - 1; i >= 0; i--) {
      if (storedShifts[i].id == shiftId &&
          shiftShopIds[i] == shopId &&
          shiftAuthIds[i] == authUserId) {
        storedShifts.removeAt(i);
        shiftShopIds.removeAt(i);
        shiftAuthIds.removeAt(i);
      }
    }
  }

  @override
  Future<List<StaffAdvanceEntry>> fetchAdvances({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    _maybeFail('fetchAdvances');
    final result = <StaffAdvanceEntry>[];
    for (var i = 0; i < storedAdvances.length; i++) {
      final advance = storedAdvances[i];
      if (advanceShopIds[i] != shopId) continue;
      if (advanceAuthIds[i] != authUserId) continue;
      if (!_inRange(advance.advanceDate, startDate, endExclusiveDate)) {
        continue;
      }
      result.add(
        StaffAdvanceEntry(
          id: advance.id,
          staffUserId: staffUserId,
          amountPaise: advance.amountPaise,
          advanceDate: advance.advanceDate,
          note: advance.note,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> insertAdvance({
    required String shopId,
    required String authUserId,
    required StaffAdvanceEntry entry,
  }) async {
    _maybeFail('insertAdvance');
    storedAdvances.add(entry);
    advanceShopIds.add(shopId);
    advanceAuthIds.add(authUserId);
  }

  @override
  Future<CloudMonthlySalary?> fetchSalary({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime monthDate,
  }) async {
    _maybeFail('fetchSalary');
    for (var i = 0; i < storedSalaries.length; i++) {
      final salary = storedSalaries[i];
      if (salary.shopId == shopId &&
          salaryAuthIds[i] == authUserId &&
          salary.monthDate == monthDate) {
        return salary;
      }
    }
    return null;
  }

  @override
  Future<void> upsertSalary({
    required String authUserId,
    required CloudMonthlySalary salary,
  }) async {
    _maybeFail('upsertSalary');
    for (var i = 0; i < storedSalaries.length; i++) {
      final existing = storedSalaries[i];
      if (existing.shopId == salary.shopId &&
          salaryAuthIds[i] == authUserId &&
          existing.monthDate == salary.monthDate) {
        storedSalaries[i] = salary;
        return;
      }
    }
    storedSalaries.add(salary);
    salaryAuthIds.add(authUserId);
  }

  @override
  Future<void> deleteSalary({
    required String shopId,
    required String authUserId,
    required DateTime monthDate,
  }) async {
    _maybeFail('deleteSalary');
    for (var i = storedSalaries.length - 1; i >= 0; i--) {
      final salary = storedSalaries[i];
      if (salary.shopId == shopId &&
          salaryAuthIds[i] == authUserId &&
          salary.monthDate == monthDate) {
        storedSalaries.removeAt(i);
        salaryAuthIds.removeAt(i);
      }
    }
  }

  @override
  Future<List<CloudDailySalary>> fetchDailySalaries({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    _maybeFail('fetchDailySalaries');
    final result = <CloudDailySalary>[];
    for (var i = 0; i < storedDailySalaries.length; i++) {
      final salary = storedDailySalaries[i];
      if (dailySalaryShopIds[i] != shopId) continue;
      if (dailySalaryAuthIds[i] != authUserId) continue;
      if (!_inRange(salary.attendanceDate, startDate, endExclusiveDate)) {
        continue;
      }
      result.add(
        CloudDailySalary(
          id: salary.id,
          shopId: salary.shopId,
          staffUserId: staffUserId,
          attendanceDate: salary.attendanceDate,
          salaryPaise: salary.salaryPaise,
        ),
      );
    }
    return result;
  }

  @override
  Future<void> upsertDailySalary({
    required String shopId,
    required String authUserId,
    required CloudDailySalary salary,
  }) async {
    _maybeFail('upsertDailySalary');
    for (var i = 0; i < storedDailySalaries.length; i++) {
      final existing = storedDailySalaries[i];
      if (existing.shopId == salary.shopId &&
          dailySalaryAuthIds[i] == authUserId &&
          existing.attendanceDate == salary.attendanceDate) {
        storedDailySalaries[i] = salary;
        dailySalaryShopIds[i] = shopId;
        dailySalaryAuthIds[i] = authUserId;
        return;
      }
    }
    storedDailySalaries.add(salary);
    dailySalaryShopIds.add(shopId);
    dailySalaryAuthIds.add(authUserId);
  }

  @override
  Future<void> deleteDailySalary({
    required String shopId,
    required String authUserId,
    required DateTime attendanceDate,
  }) async {
    _maybeFail('deleteDailySalary');
    for (var i = storedDailySalaries.length - 1; i >= 0; i--) {
      final salary = storedDailySalaries[i];
      if (dailySalaryShopIds[i] == shopId &&
          dailySalaryAuthIds[i] == authUserId &&
          salary.attendanceDate == attendanceDate) {
        storedDailySalaries.removeAt(i);
        dailySalaryShopIds.removeAt(i);
        dailySalaryAuthIds.removeAt(i);
      }
    }
  }
}
