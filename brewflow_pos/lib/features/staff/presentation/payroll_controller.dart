import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/features/staff/data/drift_staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/data/staff_payroll_cloud_gateway.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_repository.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll (Riverpod)
///
/// Supplies the repository, the selected month and the monthly attendance +
/// salary summary for one staff member. The monthly salary is CALCULATED as
/// the SUM of the daily salary amounts the owner enters per day, overridden
/// by the owner-entered manual monthly salary when set (never derived from an
/// hourly rate): final payable is effective salary minus advances. Hours are
/// display-only.
///
/// Reads are scoped to the staff profile's own shop so Cafe and Food Truck
/// stay isolated even from the "All businesses" view.
/// ---------------------------------------------------------------------------

/// Cloud gateway provider (null in tests where Supabase is not initialized).
final staffPayrollCloudGatewayProvider = Provider<StaffPayrollCloudGateway?>((
  ref,
) {
  try {
    final client = Supabase.instance.client;
    return SupabaseStaffPayrollGateway(client);
  } catch (_) {
    return null;
  }
});

/// The payroll repository for the app scope. Attendance writes are local-first:
/// the shared [syncOutboxCoordinatorProvider] commits the local row and its
/// durable queue entry atomically and kicks a fast background sync, so Check
/// In/Out never wait for the cloud round trip. Reads serve the local mirror
/// with best-effort scoped pulls; override with a fake in tests.
final staffPayrollRepositoryProvider = Provider<StaffPayrollRepository>((ref) {
  return DriftStaffPayrollRepository(
    ref.watch(appDatabaseProvider),
    cloudGateway: ref.watch(staffPayrollCloudGatewayProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
  );
});

/// The selected month (cookie, first of the month) for a staff member.
final class PayrollMonthNotifier extends Notifier<DateTime> {
  PayrollMonthNotifier(this.staffUserId);

  final String staffUserId;

  @override
  DateTime build() {
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  /// Moves the selected month by [months] and returns the new selection.
  DateTime shift(int months) {
    final current = state;
    final total = current.year * 12 + (current.month - 1) + months;
    state = DateTime(total ~/ 12, total % 12 + 1);
    return state;
  }
}

final payrollMonthProvider =
    NotifierProvider.family<PayrollMonthNotifier, DateTime, String>(
      PayrollMonthNotifier.new,
    );

/// The monthly attendance + manual-salary summary for one staff member.
///
/// Local-first paint: [build] serves the device mirror immediately (no
/// network), then reconciles with the cloud in the background and refreshes
/// when it lands — the Daily Closing pattern (tap → local save → immediate
/// UI, cloud continues behind). The repository's own reads stay
/// cloud-authoritative for every other caller; only this summary takes the
/// local-first path, and reconciliation (pulls, conflict rules, retry) is
/// unchanged, just asynchronous.
final class PayrollSummaryController
    extends AsyncNotifier<MonthlyPayrollSummary> {
  PayrollSummaryController(this.staffUserId);

  final String staffUserId;

  /// Set whenever the view (re)builds for a reason that may have moved cloud
  /// state: first paint and every mutation. Consumed exactly once per build
  /// so background reconciliations can never chase each other.
  bool _reconcileArmed = true;

  /// False once the provider is disposed; background work must never touch
  /// a dead ref.
  bool _alive = true;

  @override
  Future<MonthlyPayrollSummary> build() async {
    ref.onDispose(() => _alive = false);
    final repository = ref.watch(staffPayrollRepositoryProvider);
    final month = ref.watch(payrollMonthProvider(staffUserId));
    final summary = await _load(
      repository: repository,
      month: month,
      localOnly: true,
    );
    if (_reconcileArmed) {
      _reconcileArmed = false;
      _reconcileInBackground(repository: repository, month: month);
    }
    return summary;
  }

  /// Cloud reconciliation behind the painted mirror: pulls the authoritative
  /// reads (same calls, same conflict/prune rules as before) and refreshes
  /// the view when they land. Best-effort and fully guarded — a failure or
  /// a disposed provider leaves the already-painted local state alone.
  Future<void> _reconcileInBackground({
    required StaffPayrollRepository repository,
    required DateTime month,
  }) async {
    try {
      await _load(repository: repository, month: month, localOnly: false);
    } catch (_) {
      // Local DB failures surface on the next foreground build; cloud-pull
      // failures are already best-effort inside the repository.
    }
    if (!_alive) return;
    try {
      ref.invalidateSelf();
    } catch (_) {
      // Disposed between the guard and the call: nothing to refresh.
    }
  }

  Future<MonthlyPayrollSummary> _load({
    required StaffPayrollRepository repository,
    required DateTime month,
    required bool localOnly,
  }) async {
    final start = DateTime.utc(month.year, month.month);
    final end = DateTime.utc(month.year, month.month + 1);
    final shopIds = await _scopeShopIds();
    final shifts = await repository.attendanceFor(
      staffUserId: staffUserId,
      startDate: start,
      endExclusiveDate: end,
      shopIds: shopIds,
      localOnly: localOnly,
    );
    final advances = await repository.advancesFor(
      staffUserId: staffUserId,
      startDate: start,
      endExclusiveDate: end,
      shopIds: shopIds,
      localOnly: localOnly,
    );
    final salary = await repository.salaryForMonth(
      staffUserId,
      month,
      localOnly: localOnly,
    );
    final dailySalaries = await repository.dailySalariesFor(
      staffUserId: staffUserId,
      startDate: start,
      endExclusiveDate: end,
      shopIds: shopIds,
      localOnly: localOnly,
    );
    final open = await repository.openShiftFor(
      staffUserId,
      localOnly: localOnly,
    );
    return MonthlyPayrollSummary(
      shifts: shifts,
      advances: advances,
      manualSalaryPaise: salary,
      openShift: open,
      dailySalaries: dailySalaries,
    );
  }

  /// The shops whose payroll rows may be read for [staffUserId].
  ///
  /// Always returns a list, never null. `null` is the repositories' "every
  /// business" scope, so the previous `null` fallbacks — for a staff row with
  /// no `shop_id`, and for *any* exception while reading the profile — turned a
  /// lookup failure into a cross-business payroll read. Payroll carries
  /// attendance hours, salary and advances, so that leak is not acceptable;
  /// both paths now resolve to "no rows" instead.
  ///
  /// Two rules decide the scope:
  ///  1. A STAFF session may read only its OWN payroll, and only inside the shop
  ///     its authenticated profile is assigned to.
  ///  2. An OWNER may read any staff member's payroll, but only scoped to that
  ///     staff member's own business — so Cafe and Food Truck payroll stay
  ///     separate even from the "All businesses" view.
  Future<List<String>> _scopeShopIds() async {
    // An unresolved profile cannot be classified as owner or staff, so it must
    // not be trusted with a payroll read.
    final profile = ref.read(userProfileProvider).value;
    if (profile == null) {
      AppTrace.warn('payroll.read_scope', {
        'reason': 'profile_unresolved',
        'staffRef': staffUserId,
      });
      return const [];
    }

    if (!profile.isOwner) {
      // Staff are single-shop by contract: never another member's payroll, and
      // never a shop other than the one the profile is assigned to.
      if (profile.id != staffUserId) {
        AppTrace.warn('payroll.read_scope', {
          'reason': 'staff_other_member',
          'shopRef': AppTrace.userRef(profile.shopId),
        });
        return const [];
      }
      final own = profile.shopId;
      if (own == null || own.isEmpty) return const [];
      return [own];
    }

    final targetShopId = await _staffShopId();
    if (targetShopId == null || targetShopId.isEmpty) {
      AppTrace.warn('payroll.read_scope', {
        'reason': 'target_shop_unresolved',
        'staffRef': staffUserId,
      });
      return const [];
    }
    return [targetShopId];
  }

  /// The shop the viewed staff member belongs to, or null when the row is
  /// missing or carries no business. Never throws.
  Future<String?> _staffShopId() async {
    try {
      final database = ref.read(appDatabaseProvider);
      final query = database.select(database.users)
        ..where((t) => t.id.equals(staffUserId))
        ..limit(1);
      final profile = await query.getSingleOrNull();
      return profile?.shopId;
    } on Object {
      // A failed lookup must not widen the scope; the caller treats null as
      // "no rows".
      return null;
    }
  }

  Future<void> clockIn({required DateTime inAt}) => _mutate(
    (repository) => repository.clockIn(staffUserId: staffUserId, inAt: inAt),
  );

  Future<void> clockOut({required DateTime outAt}) => _mutate(
    (repository) => repository.clockOut(staffUserId: staffUserId, outAt: outAt),
  );

  Future<void> addAdvance({
    required int amountPaise,
    required DateTime advanceDate,
    String? note,
  }) => _mutate(
    (repository) => repository.addAdvance(
      staffUserId: staffUserId,
      amountPaise: amountPaise,
      advanceDate: advanceDate,
      note: note,
    ),
  );

  Future<void> setMonthlySalary(int? salaryPaise) => _mutate(
    (repository) => repository.setMonthlySalary(
      staffUserId,
      ref.read(payrollMonthProvider(staffUserId)),
      salaryPaise,
    ),
  );

  /// Sets (or with a null argument clears) the daily salary amount for one
  /// business day ([attendanceDate], UTC-midnight day cookie).
  Future<void> setDailySalary(DateTime attendanceDate, int? salaryPaise) =>
      _mutate(
        (repository) =>
            repository.setDailySalary(staffUserId, attendanceDate, salaryPaise),
      );

  /// Owner-only removal of the monthly salary. Clearing a month is a real
  /// delete: the repository drops the cloud row FIRST (so other owner devices
  /// never re-pull it) and then clears the local mirror. Kept separate from
  /// [setMonthlySalary] so the owner-only boundary is explicit — the same
  /// repository call, never a parallel delete path.
  Future<void> clearMonthlySalary() {
    requireOwner(ref);
    return _mutate(
      (repository) => repository.setMonthlySalary(
        staffUserId,
        ref.read(payrollMonthProvider(staffUserId)),
        null,
      ),
    );
  }

  /// Owner-only removal of one day's salary. Cloud delete first, local mirror
  /// second — see [clearMonthlySalary].
  Future<void> clearDailySalary(DateTime attendanceDate) {
    requireOwner(ref);
    return _mutate(
      (repository) =>
          repository.setDailySalary(staffUserId, attendanceDate, null),
    );
  }

  /// Owner-only removal of one attendance shift (real delete, never a
  /// deactivate). Cloud first, local mirror second — see [clearMonthlySalary].
  /// [requireOwner] is the boundary guard, so hiding the action in the UI is
  /// never the only protection. [_mutate] reloads the month afterwards, so
  /// working days, hours, salary and final payable recompute immediately.
  ///
  /// `async` so a non-owner session surfaces as a rejected future (like every
  /// other payroll failure) rather than a synchronous throw.
  Future<void> deleteAttendance(String shiftId) async {
    requireOwner(ref);
    return _mutate(
      (repository) => repository.deleteAttendance(staffUserId, shiftId),
    );
  }

  /// Owner-only marking of one business day as Leave (day-level state, never
  /// a worked shift). [requireOwner] is the boundary guard, so hiding the
  /// action in the UI is never the only protection. [_mutate] reloads the
  /// month afterwards, so working days, leave days, hours and final payable
  /// recompute immediately.
  ///
  /// `async` so a non-owner session surfaces as a rejected future (like every
  /// other payroll failure) rather than a synchronous throw.
  Future<void> markLeave({
    required DateTime attendanceDate,
    String? reason,
  }) async {
    requireOwner(ref);
    return _mutate(
      (repository) => repository.markLeave(
        staffUserId: staffUserId,
        attendanceDate: attendanceDate,
        reason: reason,
      ),
    );
  }

  /// Owner-only clearing of a Leave day. Same boundary and reload contract
  /// as [markLeave]; a day without Leave is a safe no-op in the repository.
  Future<void> clearLeave({required DateTime attendanceDate}) async {
    requireOwner(ref);
    return _mutate(
      (repository) => repository.clearLeave(
        staffUserId: staffUserId,
        attendanceDate: attendanceDate,
      ),
    );
  }

  Future<void> _mutate(
    Future<void> Function(StaffPayrollRepository repository) action,
  ) async {
    // The loading state only ever spans the LOCAL write (fast): the rebuild
    // paints from the mirror immediately, so taps release without waiting
    // for cloud reconciliation, which follows in the background.
    state = const AsyncLoading();
    try {
      final repository = ref.read(staffPayrollRepositoryProvider);
      await action(repository);
      _reconcileArmed = true;
      ref.invalidateSelf();
    } on Object catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    }
  }
}

final payrollSummaryProvider =
    AsyncNotifierProvider.family<
      PayrollSummaryController,
      MonthlyPayrollSummary,
      String
    >(PayrollSummaryController.new);
