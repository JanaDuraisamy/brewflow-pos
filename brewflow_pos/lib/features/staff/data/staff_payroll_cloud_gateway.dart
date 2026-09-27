import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Cloud Gateway
///
/// Cloud-authoritative adapter for attendance shifts, advances and manual
/// monthly salaries (supabase/migrations/0023, re-keyed in 0028). Direct-table
/// access with shop RLS (`is_shop_member(shop_id)`); the client never sends
/// credentials and never weakens RLS. Timestamps cross as ISO-8601 UTC;
/// business-day cookies cross as `yyyy-MM-dd` dates.
///
/// Every row is keyed on `auth_user_id` (the cross-device identity), never on
/// the device-local `users.id` — see [StaffPayrollCloudGateway].
///
/// Salary is manual per staff/month — never derived from an hourly rate.
/// ---------------------------------------------------------------------------

/// One manual monthly salary row.
final class CloudMonthlySalary {
  const CloudMonthlySalary({
    required this.id,
    required this.shopId,
    required this.staffUserId,
    required this.monthDate,
    required this.salaryPaise,
  });

  final String id;
  final String shopId;
  final String staffUserId;

  /// First of the month (UTC midnight cookie).
  final DateTime monthDate;
  final int salaryPaise;
}

/// One daily salary amount recorded against one staff member's business day.
/// Day-level (not per shift), matching the local [StaffDailySalary] domain
/// model: the month's CALCULATED salary is the SUM of these daily amounts.
final class CloudDailySalary {
  const CloudDailySalary({
    required this.id,
    required this.shopId,
    required this.staffUserId,
    required this.attendanceDate,
    required this.salaryPaise,
  });

  final String id;
  final String shopId;
  final String staffUserId;

  /// Local business-day cookie (UTC midnight) this salary covers.
  final DateTime attendanceDate;

  /// Owner-entered salary amount in integer paise (>= 0).
  final int salaryPaise;
}

/// The cloud payroll tables this gateway reads and writes.
enum StaffPayrollTable { attendance, advances, monthlySalaries, dailySalaries }

/// ---------------------------------------------------------------------------
/// Identity contract for the cloud payroll tables.
///
/// Every read is FILTERED by [authUserId] and every write STAMPS it, because
/// that is the only identity shared by all devices for one human. The
/// device-local `users.id` is not: it is a fresh `Uuid().v4()` per device, so
/// keying the cloud on it meant a second device asked for attendance under an
/// id the cloud had never seen and silently received nothing.
///
/// [staffUserId] is still carried on the models because the LOCAL Drift mirror
/// is keyed by the local id. Reads therefore stamp the local id the caller
/// asked about and never echo the cloud's `staff_user_id`, which on a
/// multi-device install is some other device's local id.
/// ---------------------------------------------------------------------------
abstract interface class StaffPayrollCloudGateway {
  Future<List<StaffAttendanceRecord>> fetchAttendance({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  });

  Future<void> upsertAttendance({
    required String shopId,
    required String authUserId,
    required StaffAttendanceRecord record,
  });

  /// Removes one attendance shift so it reads back as gone on every device
  /// for the shop. A real row DELETE scoped to the shop and staff member.
  Future<void> deleteAttendance({
    required String shopId,
    required String authUserId,
    required String shiftId,
  });

  Future<List<StaffAdvanceEntry>> fetchAdvances({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  });

  Future<void> insertAdvance({
    required String shopId,
    required String authUserId,
    required StaffAdvanceEntry entry,
  });

  Future<CloudMonthlySalary?> fetchSalary({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime monthDate,
  });

  Future<void> upsertSalary({
    required String authUserId,
    required CloudMonthlySalary salary,
  });

  /// Removes the salary row so the month reads back as unset everywhere.
  Future<void> deleteSalary({
    required String shopId,
    required String authUserId,
    required DateTime monthDate,
  });

  Future<List<CloudDailySalary>> fetchDailySalaries({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  });

  Future<void> upsertDailySalary({
    required String shopId,
    required String authUserId,
    required CloudDailySalary salary,
  });

  /// Removes the daily salary row for the business day so the day reads back
  /// as unset everywhere.
  Future<void> deleteDailySalary({
    required String shopId,
    required String authUserId,
    required DateTime attendanceDate,
  });

  /// Attaches [authUserId] to the pre-re-key rows this device itself wrote,
  /// so history recorded before the cloud was re-keyed becomes visible to
  /// every device instead of being stranded under a device-local id.
  ///
  /// Matched on `staff_user_id = localStaffUserId AND auth_user_id IS NULL`,
  /// which makes it safe by construction: it can only claim rows this device
  /// authored, it is idempotent (a second call matches nothing), and it can
  /// never resurrect a row an owner genuinely deleted, because a deleted row
  /// no longer exists to match.
  Future<void> claimLegacyRows({
    required StaffPayrollTable table,
    required String shopId,
    required String localStaffUserId,
    required String authUserId,
  });
}

final class SupabaseStaffPayrollGateway implements StaffPayrollCloudGateway {
  SupabaseStaffPayrollGateway(this._client);

  final SupabaseClient _client;

  static String _day(DateTime cookie) =>
      cookie.toUtc().toIso8601String().substring(0, 10);

  static String _table(StaffPayrollTable table) => switch (table) {
    StaffPayrollTable.attendance => 'staff_attendance',
    StaffPayrollTable.advances => 'staff_advances',
    StaffPayrollTable.monthlySalaries => 'staff_monthly_salaries',
    StaffPayrollTable.dailySalaries => 'staff_daily_salaries',
  };

  @override
  Future<void> claimLegacyRows({
    required StaffPayrollTable table,
    required String shopId,
    required String localStaffUserId,
    required String authUserId,
  }) async {
    await _client
        .from(_table(table))
        .update(<String, dynamic>{'auth_user_id': authUserId})
        .eq('shop_id', shopId)
        .eq('staff_user_id', localStaffUserId)
        .isFilter('auth_user_id', null);
  }

  @override
  Future<List<StaffAttendanceRecord>> fetchAttendance({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    final data = await _client
        .from('staff_attendance')
        .select()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .gte('attendance_date', _day(startDate))
        .lt('attendance_date', _day(endExclusiveDate))
        .order('in_at', ascending: true);
    return [
      for (final json in data)
        StaffAttendanceRecord(
          id: json['id'] as String,
          // Stamped with the LOCAL id the caller asked about, never the cloud's
          // staff_user_id (which is another device's local id).
          staffUserId: staffUserId,
          inAt: DateTime.parse(json['in_at'] as String).toUtc(),
          outAt: json['out_at'] == null
              ? null
              : DateTime.parse(json['out_at'] as String).toUtc(),
          attendanceDate: DateTime.parse(
            '${json['attendance_date']}T00:00:00Z',
          ),
          workedMinutes: (json['worked_minutes'] as num).toInt(),
        ),
    ];
  }

  @override
  Future<void> upsertAttendance({
    required String shopId,
    required String authUserId,
    required StaffAttendanceRecord record,
  }) async {
    await _client.from('staff_attendance').upsert(<String, dynamic>{
      'id': record.id,
      'shop_id': shopId,
      'staff_user_id': record.staffUserId,
      'auth_user_id': authUserId,
      'in_at': record.inAt.toUtc().toIso8601String(),
      'out_at': record.outAt?.toUtc().toIso8601String(),
      'attendance_date': _day(record.attendanceDate),
      'worked_minutes': record.workedMinutes,
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteAttendance({
    required String shopId,
    required String authUserId,
    required String shiftId,
  }) async {
    await _client
        .from('staff_attendance')
        .delete()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .eq('id', shiftId);
  }

  @override
  Future<List<StaffAdvanceEntry>> fetchAdvances({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    final data = await _client
        .from('staff_advances')
        .select()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .gte('advance_date', _day(startDate))
        .lt('advance_date', _day(endExclusiveDate))
        .order('advance_date', ascending: true);
    return [
      for (final json in data)
        StaffAdvanceEntry(
          id: json['id'] as String,
          staffUserId: staffUserId,
          amountPaise: (json['amount_paise'] as num).toInt(),
          advanceDate: DateTime.parse('${json['advance_date']}T00:00:00Z'),
          note: json['note'] as String?,
        ),
    ];
  }

  @override
  Future<void> insertAdvance({
    required String shopId,
    required String authUserId,
    required StaffAdvanceEntry entry,
  }) async {
    await _client.from('staff_advances').upsert(<String, dynamic>{
      'id': entry.id,
      'shop_id': shopId,
      'staff_user_id': entry.staffUserId,
      'auth_user_id': authUserId,
      'amount_paise': entry.amountPaise,
      'advance_date': _day(entry.advanceDate),
      'note': entry.note,
    }, onConflict: 'id');
  }

  @override
  Future<CloudMonthlySalary?> fetchSalary({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime monthDate,
  }) async {
    final data = await _client
        .from('staff_monthly_salaries')
        .select()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .eq('month_date', _day(monthDate))
        .limit(1);
    if (data.isEmpty) return null;
    final json = data.first;
    return CloudMonthlySalary(
      id: json['id'] as String,
      shopId: json['shop_id'] as String,
      staffUserId: staffUserId,
      monthDate: DateTime.parse('${json['month_date']}T00:00:00Z'),
      salaryPaise: (json['salary_paise'] as num).toInt(),
    );
  }

  @override
  Future<void> upsertSalary({
    required String authUserId,
    required CloudMonthlySalary salary,
  }) async {
    await _client.from('staff_monthly_salaries').upsert(<String, dynamic>{
      'id': salary.id,
      'shop_id': salary.shopId,
      'staff_user_id': salary.staffUserId,
      'auth_user_id': authUserId,
      'month_date': _day(salary.monthDate),
      'salary_paise': salary.salaryPaise,
    }, onConflict: 'id');
  }

  @override
  Future<void> deleteSalary({
    required String shopId,
    required String authUserId,
    required DateTime monthDate,
  }) async {
    await _client
        .from('staff_monthly_salaries')
        .delete()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .eq('month_date', _day(monthDate));
  }

  @override
  Future<List<CloudDailySalary>> fetchDailySalaries({
    required String shopId,
    required String staffUserId,
    required String authUserId,
    required DateTime startDate,
    required DateTime endExclusiveDate,
  }) async {
    final data = await _client
        .from('staff_daily_salaries')
        .select()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .gte('attendance_date', _day(startDate))
        .lt('attendance_date', _day(endExclusiveDate))
        .order('attendance_date', ascending: true);
    return [
      for (final json in data)
        CloudDailySalary(
          id: json['id'] as String,
          shopId: json['shop_id'] as String,
          staffUserId: staffUserId,
          attendanceDate: DateTime.parse(
            '${json['attendance_date']}T00:00:00Z',
          ),
          salaryPaise: (json['salary_paise'] as num).toInt(),
        ),
    ];
  }

  @override
  Future<void> upsertDailySalary({
    required String shopId,
    required String authUserId,
    required CloudDailySalary salary,
  }) async {
    // Composite-key upsert: one row per (shop, staff, day) is the business
    // invariant, so a second device editing the same day converges instead of
    // duplicating (idempotent cross-device cloud write). The key is the
    // cross-device auth identity — keying it on the local id would let two
    // devices insert two rows for one person-day and double their payable.
    await _client.from('staff_daily_salaries').upsert(<String, dynamic>{
      'id': salary.id,
      'shop_id': shopId,
      'staff_user_id': salary.staffUserId,
      'auth_user_id': authUserId,
      'attendance_date': _day(salary.attendanceDate),
      'salary_paise': salary.salaryPaise,
    }, onConflict: 'shop_id,auth_user_id,attendance_date');
  }

  @override
  Future<void> deleteDailySalary({
    required String shopId,
    required String authUserId,
    required DateTime attendanceDate,
  }) async {
    await _client
        .from('staff_daily_salaries')
        .delete()
        .eq('shop_id', shopId)
        .eq('auth_user_id', authUserId)
        .eq('attendance_date', _day(attendanceDate));
  }
}
