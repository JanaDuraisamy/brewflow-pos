import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/domain/staff_payroll_models.dart';
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Payroll Page (Standalone Staff Attendance)
///
/// A standalone, owner-only page: it loads the roster itself and lets the
/// owner pick which staff member's attendance they are viewing, so the route
/// works without any entry context. Per selected member it shows today's
/// daily summary (date, clock-in/out, working hours, status, daily salary),
/// clock in/out controls, the monthly summary (total working days, total
/// hours, calculated salary from the daily entries vs the owner-set monthly
/// salary, advances, final payable = effective salary − advances) and the raw
/// attendance + advance history with per-day salary editing. Salary is never
/// derived from an hourly rate; hours are display-only. Attendance, salary
/// and advances sync to the cloud and load on any owner device.
/// ---------------------------------------------------------------------------

final class StaffPayrollPage extends ConsumerStatefulWidget {
  const StaffPayrollPage({super.key, this.staff});

  /// Optional staff preselected from the staff list (go() extra). When null,
  /// the page falls back to the first roster member so /staff/payroll works
  /// as a true standalone screen.
  final UserProfile? staff;

  @override
  ConsumerState<StaffPayrollPage> createState() => _StaffPayrollPageState();
}

final class _StaffPayrollPageState extends ConsumerState<StaffPayrollPage> {
  String? _selectedStaffId;
  String? _listenedMemberId;
  ProviderSubscription<AsyncValue<MonthlyPayrollSummary>>? _summaryListener;

  @override
  void initState() {
    super.initState();
    _selectedStaffId = widget.staff?.id;
  }

  @override
  void dispose() {
    _summaryListener?.close();
    super.dispose();
  }

  /// The member the page currently shows: the explicit selector choice wins,
  /// then the staff passed on entry, then the first roster member. This keeps
  /// the pushed page usable before the roster resolves and never leaves a
  /// selection dangling when a chosen member disappears.
  UserProfile? _resolveSelected(List<UserProfile>? roster) {
    final members = roster ?? const <UserProfile>[];
    if (members.isEmpty) return widget.staff;
    for (final member in members) {
      if (member.id == _selectedStaffId) return member;
    }
    return members.first;
  }

  /// Back to the staff list. Entries arrive via go() (push() does not
  /// resolve across navigators in this router setup), so history is empty:
  /// pop when something is actually below, otherwise go to the list.
  void _goBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.staff);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roster = ref.watch(staffRosterProvider);
    final member = _resolveSelected(roster.value);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => _goBack(context)),
          title: const Text('Staff Attendance'),
          centerTitle: false,
        ),
        body: Padding(
          padding: AppInsets.screen,
          child: member == null
              ? _buildRosterUnavailable(context, roster)
              : _buildPage(context, roster, member),
        ),
      ),
    );
  }

  /// Rendered before any member is known (empty roster, still loading or
  /// failed) — only reachable on direct, entry-free navigation.
  Widget _buildRosterUnavailable(
    BuildContext context,
    AsyncValue<List<UserProfile>> roster,
  ) {
    return roster.when(
      data: (members) => members.isEmpty
          ? const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'No staff yet',
              message:
                  'Add staff on the Staff page to record attendance '
                  'against them.',
            )
          : const EmptyState(
              icon: Icons.person_off_outlined,
              title: 'No staff member selected',
              message: 'Choose a staff member to view their attendance.',
            ),
      loading: () =>
          const Center(child: LoadingState(message: 'Loading staff…')),
      error: (error, _) => ErrorState(
        message: _rosterErrorMessage(error),
        onRetry: () => ref.invalidate(staffRosterProvider),
      ),
    );
  }

  static String _rosterErrorMessage(Object error) {
    if (error is StaffFailure) return error.message;
    return 'Could not load the staff roster. Pull to retry.';
  }

  Widget _buildPage(
    BuildContext context,
    AsyncValue<List<UserProfile>> roster,
    UserProfile member,
  ) {
    final memberId = member.id;
    // One listener at a time: switching members replaces the subscription.
    if (_listenedMemberId != memberId) {
      _summaryListener?.close();
      _listenedMemberId = memberId;
      _summaryListener = ref.listenManual(payrollSummaryProvider(memberId), (
        previous,
        next,
      ) {
        if (!mounted) return;
        if (next.hasError && next.error is StaffPayrollFailure) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(
              SnackBar(
                content: Text((next.error! as StaffPayrollFailure).message),
              ),
            );
        }
      });
    }

    final summary = ref.watch(payrollSummaryProvider(memberId));
    final month = ref.watch(payrollMonthProvider(memberId));
    final phone = MediaQuery.sizeOf(context).width < 600;

    final subtitle = [
      member.displayName,
      member.email,
    ].whereType<String>().join(' · ');

    return phone
        ? _buildPhone(context, roster, member, subtitle, month, summary)
        : _buildDesktop(context, roster, member, subtitle, month, summary);
  }

  Widget _buildPhone(
    BuildContext context,
    AsyncValue<List<UserProfile>> roster,
    UserProfile member,
    String subtitle,
    DateTime month,
    AsyncValue<MonthlyPayrollSummary> summary,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: 'Staff Attendance', subtitle: subtitle),
          const SizedBox(height: AppSpacing.lg),
          _StaffSelector(
            members: roster.value,
            selected: member,
            onChanged: (next) => setState(() => _selectedStaffId = next?.id),
          ),
          const SizedBox(height: AppSpacing.md),
          _MonthSelector(memberId: member.id, month: month),
          const SizedBox(height: AppSpacing.lg),
          ...summary.when(
            skipLoadingOnRefresh: true,
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(child: LoadingState(message: 'Loading payroll…')),
              ),
            ],
            error: (error, stackTrace) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: ErrorState(
                  message: _payrollErrorMessage(error),
                  onRetry: () =>
                      ref.invalidate(payrollSummaryProvider(member.id)),
                ),
              ),
            ],
            data: (data) => [
              _DailySummaryCard(memberId: member.id, data: data),
              const SizedBox(height: AppSpacing.lg),
              _PayrollSummaryCard(memberId: member.id, data: data),
              const SizedBox(height: AppSpacing.lg),
              _AdvancesCard(memberId: member.id, data: data),
              const SizedBox(height: AppSpacing.lg),
              _AttendanceCard(memberId: member.id, data: data),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Attendance, salary and advances sync to the cloud.',
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktop(
    BuildContext context,
    AsyncValue<List<UserProfile>> roster,
    UserProfile member,
    String subtitle,
    DateTime month,
    AsyncValue<MonthlyPayrollSummary> summary,
  ) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: _buildPhone(context, roster, member, subtitle, month, summary),
      ),
    );
  }

  static String _payrollErrorMessage(Object error) {
    if (error is StaffPayrollFailure) return error.message;
    return 'Could not load payroll. Pull to retry or check the device storage.';
  }
}

/// ---------------------------------------------------------------------------
/// Staff selector — the owner picks whose attendance is on screen. Hidden
/// while the roster is empty (entry-provided staff still renders beneath).
/// ---------------------------------------------------------------------------

final class _StaffSelector extends StatelessWidget {
  const _StaffSelector({
    required this.members,
    required this.selected,
    required this.onChanged,
  });

  final List<UserProfile>? members;
  final UserProfile selected;
  final ValueChanged<UserProfile?> onChanged;

  @override
  Widget build(BuildContext context) {
    final roster = members;
    if (roster == null || roster.isEmpty) return const SizedBox.shrink();
    final appColors = context.appColors;
    return AppCard(
      child: Row(
        children: [
          Icon(Icons.badge_outlined, color: appColors.textSecondary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'Staff member',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<UserProfile>(
                value: selected,
                isExpanded: true,
                borderRadius: AppBorderRadius.lg,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: appColors.textPrimary),
                items: [
                  for (final member in roster)
                    DropdownMenuItem<UserProfile>(
                      value: member,
                      child: Text(
                        member.displayName ?? member.email,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Month stepping — previous/next with a readable label.
/// ---------------------------------------------------------------------------

final class _MonthSelector extends ConsumerWidget {
  const _MonthSelector({required this.memberId, required this.month});

  final String memberId;
  final DateTime month;

  static const List<String> _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton.filledTonal(
          tooltip: 'Previous month',
          onPressed: () =>
              ref.read(payrollMonthProvider(memberId).notifier).shift(-1),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Text(
            '${_monthNames[month.month - 1]} ${month.year}',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: appColors.textPrimary),
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Next month',
          onPressed: () =>
              ref.read(payrollMonthProvider(memberId).notifier).shift(1),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Daily summary — today's business day: date, clock-in/out, working hours and
/// status (In progress / Present / Absent), plus the clock in/out controls.
/// Defaults (09:00 in, 20:00 out) keep a single tap chain recording a day.
/// ---------------------------------------------------------------------------

final class _DailySummaryCard extends ConsumerWidget {
  const _DailySummaryCard({required this.memberId, required this.data});

  final String memberId;
  final MonthlyPayrollSummary data;

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final open = data.openShift;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayUtc = DateTime.utc(now.year, now.month, now.day);

    StaffAttendanceRecord? closedToday;
    for (final shift in data.shifts) {
      if (shift.attendanceDate == todayUtc) {
        closedToday = shift;
        break;
      }
    }
    final record = open ?? closedToday;
    final salaryDayUtc = record?.attendanceDate ?? todayUtc;
    StaffDailySalary? salaryForDay;
    for (final entry in data.dailySalaries) {
      if (entry.attendanceDate == salaryDayUtc) {
        salaryForDay = entry;
        break;
      }
    }

    final String dateLabel;
    final String inLabel;
    final String outLabel;
    final String hoursLabel;
    if (record == null) {
      dateLabel = _formatDate(today);
      inLabel = '—';
      outLabel = '—';
      hoursLabel = '—';
    } else {
      final businessDay = DateTime(
        record.attendanceDate.year,
        record.attendanceDate.month,
        record.attendanceDate.day,
      );
      dateLabel = _formatDate(businessDay);
      inLabel = TimeOfDay.fromDateTime(record.inAt.toLocal()).format(context);
      if (record.isOpen) {
        outLabel = 'In progress';
        hoursLabel = 'In progress';
      } else if (record.outAt != null) {
        outLabel = TimeOfDay.fromDateTime(
          record.outAt!.toLocal(),
        ).format(context);
        hoursLabel = formatHoursMinutes(record.workedMinutes);
      } else {
        outLabel = '—';
        hoursLabel = '—';
      }
    }

    final String statusLabel;
    final Color statusColor;
    if (open != null) {
      statusLabel = 'In progress';
      statusColor = AppColors.warning;
    } else if (closedToday != null) {
      statusLabel = 'Present';
      statusColor = AppColors.success;
    } else {
      statusLabel = 'Absent';
      statusColor = appColors.textDisabled;
    }

    final busy = ref.watch(payrollSummaryProvider(memberId)).isLoading;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                record == null ? Icons.schedule : Icons.today,
                color: record == null
                    ? appColors.textDisabled
                    : AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Daily summary',
                style: textTheme.titleMedium?.copyWith(
                  color: appColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _dailyRow(context, label: 'Date', value: Text(dateLabel)),
          _dailyRow(context, label: 'Clock In', value: Text(inLabel)),
          _dailyRow(context, label: 'Clock Out', value: Text(outLabel)),
          _dailyRow(context, label: 'Working Hours', value: Text(hoursLabel)),
          _dailyRow(
            context,
            label: 'Daily Salary',
            value: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  salaryForDay == null
                      ? 'Not set'
                      : Money.formatPaise(salaryForDay.salaryPaise),
                ),
                IconButton(
                  tooltip: 'Set daily salary',
                  onPressed: () => _editDailySalary(
                    context,
                    ref,
                    memberId: memberId,
                    attendanceDate: salaryDayUtc,
                    current: salaryForDay?.salaryPaise,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
              ],
            ),
          ),
          _dailyRow(
            context,
            label: 'Status',
            value: _StatusChip(label: statusLabel, color: statusColor),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (open == null)
            PrimaryButton(
              label: 'Clock In',
              icon: Icons.play_arrow,
              expanded: true,
              loading: busy,
              onPressed: () => _pickClockTimes(
                context,
                ref,
                closed: true,
                defaultIn: DateTime(today.year, today.month, today.day, 9),
              ),
            )
          else
            SecondaryButton(
              label: 'Clock Out',
              icon: Icons.stop,
              expanded: true,
              onPressed: busy
                  ? null
                  : () => _pickClockTimes(
                      context,
                      ref,
                      closed: false,
                      defaultIn: DateTime(
                        today.year,
                        today.month,
                        today.day,
                        20,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day} ${_monthNames[date.month - 1]} ${date.year}';

  Widget _dailyRow(
    BuildContext context, {
    required String label,
    required Widget value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          value,
        ],
      ),
    );
  }

  Future<void> _pickClockTimes(
    BuildContext context,
    WidgetRef ref, {
    required bool closed,
    required DateTime defaultIn,
  }) async {
    final now = DateTime.now();
    final today = now;
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 400)),
      lastDate: today,
    );
    if (pickedDate == null || !context.mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(defaultIn),
    );
    if (pickedTime == null || !context.mounted) return;
    final picked = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    final controller = ref.read(payrollSummaryProvider(memberId).notifier);
    await (closed
        ? controller.clockIn(inAt: picked)
        : controller.clockOut(outAt: picked));
  }

  Future<void> _editDailySalary(
    BuildContext context,
    WidgetRef ref, {
    required String memberId,
    required DateTime attendanceDate,
    required int? current,
  }) async {
    final controller = TextEditingController(
      text: current == null ? '' : Money.paiseToRupeesInput(current),
    );
    final saved = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily salary'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Salary for this day (rupees)',
            hintText: 'e.g. 300',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          // Owner-only removal: deletes the day in the cloud first, then
          // locally. [PayrollSummaryController.clearDailySalary] enforces the
          // same boundary, so hiding this action is never the only guard.
          if (current != null &&
              (ref.read(userProfileProvider).value?.isOwner ?? false))
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == 'delete') {
      if (!context.mounted) return;
      final confirmed = await confirmDestructive(
        context,
        title: 'Delete daily salary',
        subject: '${attendanceDate.day}/${attendanceDate.month}',
        consequence:
            'The saved salary for this day is removed on this device and '
            'every other device for the shop. This cannot be undone.',
        confirmLabel: 'Delete',
      );
      if (!confirmed || !context.mounted) return;
      await ref
          .read(payrollSummaryProvider(memberId).notifier)
          .clearDailySalary(attendanceDate);
      return;
    }
    if (saved != true || !context.mounted) return;
    final text = controller.text.trim();
    if (text.isEmpty) {
      // An emptied field is a removal too, so it takes the same owner-only
      // path as the explicit Delete action.
      final isOwner = ref.read(userProfileProvider).value?.isOwner ?? false;
      if (!isOwner) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only the owner can clear a daily salary.'),
          ),
        );
        return;
      }
      await ref
          .read(payrollSummaryProvider(memberId).notifier)
          .clearDailySalary(attendanceDate);
      return;
    }
    final paise = Money.parseRupeesToPaise(text);
    if (paise == null) return;
    await ref
        .read(payrollSummaryProvider(memberId).notifier)
        .setDailySalary(attendanceDate, paise);
  }
}

/// ---------------------------------------------------------------------------
/// Status pill: In progress / Present / Absent.
/// ---------------------------------------------------------------------------

final class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Monthly summary card: total working days and total hours (display-only),
/// the calculated salary (sum of the daily entries) vs the effective monthly
/// salary (owner override wins when set), advances and final payable
/// (effective salary − advances). The calculated/owner-set origin is shown
/// clearly so nobody mistakes the derived number for a manual value.
/// ---------------------------------------------------------------------------

final class _PayrollSummaryCard extends ConsumerWidget {
  const _PayrollSummaryCard({required this.memberId, required this.data});

  final String memberId;
  final MonthlyPayrollSummary data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final effective = data.effectiveSalaryPaise;
    final override = data.manualSalaryPaise;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Monthly summary',
            style: textTheme.titleMedium?.copyWith(
              color: appColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _summaryRow(
            context,
            label: 'Total Working Days',
            value: '${data.totalWorkingDays}',
          ),
          _summaryRow(
            context,
            label: 'Total Working Hours',
            value: formatHoursMinutes(data.totalMinutes),
          ),
          _summaryRow(
            context,
            label: 'Calculated Salary',
            value: data.dailySalaries.isEmpty
                ? '—'
                : Money.formatPaise(data.calculatedSalaryPaise),
          ),
          _summaryRow(
            context,
            label: 'Monthly Salary',
            value: effective == null ? 'Not set' : Money.formatPaise(effective),
            trailing: IconButton(
              tooltip: 'Set salary',
              onPressed: () => _editSalary(context, ref),
              icon: const Icon(Icons.edit_outlined, size: 18),
            ),
          ),
          if (override != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Owner-set monthly salary',
                  style: textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else if (data.dailySalaries.isNotEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  'Auto-calculated from daily entries',
                  style: textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const Divider(height: AppSpacing.xl),
          _summaryRow(
            context,
            label: 'Advances',
            value: Money.formatPaise(data.advancePaise),
            emphasized: false,
          ),
          const SizedBox(height: AppSpacing.xs),
          _summaryRow(
            context,
            label: 'Final Payable',
            value: effective == null
                ? '—'
                : Money.formatPaise(data.payablePaise!),
            emphasized: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required String label,
    required String value,
    Widget? trailing,
    bool emphasized = false,
  }) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final style = emphasized
        ? textTheme.titleMedium?.copyWith(
            color: appColors.textPrimary,
            fontWeight: FontWeight.w700,
          )
        : textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          ?trailing,
          Text(value, style: style),
        ],
      ),
    );
  }

  Future<void> _editSalary(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(
      text: data.manualSalaryPaise == null
          ? ''
          : Money.paiseToRupeesInput(data.manualSalaryPaise!),
    );
    final saved = await showDialog<Object?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Monthly salary'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Salary for the month (rupees)',
            hintText: 'e.g. 12000',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          // Owner-only removal: clears the month in the cloud first, then
          // locally. [PayrollSummaryController.clearMonthlySalary] enforces
          // the same boundary, so hiding this action is never the only guard.
          if (data.manualSalaryPaise != null &&
              (ref.read(userProfileProvider).value?.isOwner ?? false))
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('delete'),
              child: const Text('Delete'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == 'delete') {
      if (!context.mounted) return;
      final confirmed = await confirmDestructive(
        context,
        title: 'Delete monthly salary',
        subject: 'Monthly salary',
        consequence:
            'The saved salary for this month is removed on this device and '
            'every other device for the shop. This cannot be undone.',
        confirmLabel: 'Delete',
      );
      if (!confirmed || !context.mounted) return;
      await ref
          .read(payrollSummaryProvider(memberId).notifier)
          .clearMonthlySalary();
      return;
    }
    if (saved != true || !context.mounted) return;
    final paise = Money.parseRupeesToPaise(controller.text);
    if (paise == null) return;
    await ref
        .read(payrollSummaryProvider(memberId).notifier)
        .setMonthlySalary(paise);
  }
}

/// ---------------------------------------------------------------------------
/// Advances — list + add dialog.
/// ---------------------------------------------------------------------------

final class _AdvancesCard extends ConsumerWidget {
  const _AdvancesCard({required this.memberId, required this.data});

  final String memberId;
  final MonthlyPayrollSummary data;

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final advances = data.advances;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Advances',
                  style: textTheme.titleMedium?.copyWith(
                    color: appColors.textPrimary,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => _addAdvance(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (advances.isEmpty)
            Text(
              'No advances this month.',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...advances.map(
              (advance) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${advance.advanceDate.day} ${_monthNames[advance.advanceDate.month - 1]}'
                        '${advance.note == null ? '' : ' · ${advance.note}'}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: appColors.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      Money.formatPaise(advance.amountPaise),
                      style: textTheme.bodyMedium?.copyWith(
                        fontFeatures: [const FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _addAdvance(BuildContext context, WidgetRef ref) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final amount = TextEditingController();
    final note = TextEditingController();
    final date = ValueNotifier<DateTime>(
      DateTime.utc(today.year, today.month, today.day),
    );

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<DateTime>(
        valueListenable: date,
        builder: (dialogContext, selected, _) => AlertDialog(
          title: const Text('Add advance'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount (rupees)',
                    hintText: 'e.g. 500',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    hintText: 'e.g. Salary top-up',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Date'),
                  subtitle: Text(
                    '${selected.day} ${_monthNames[selected.month - 1]} ${selected.year}',
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: dialogContext,
                      initialDate: selected,
                      firstDate: DateTime(selected.year - 5),
                      lastDate: today,
                    );
                    if (picked != null) {
                      date.value = DateTime.utc(
                        picked.year,
                        picked.month,
                        picked.day,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !context.mounted) return;
    final paise = Money.parseRupeesToPaise(amount.text);
    if (paise == null) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Enter a valid amount.')));
      return;
    }
    await ref
        .read(payrollSummaryProvider(memberId).notifier)
        .addAdvance(
          amountPaise: paise,
          advanceDate: date.value,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
  }
}

/// ---------------------------------------------------------------------------
/// Raw attendance history for the month.
/// ---------------------------------------------------------------------------

final class _AttendanceCard extends ConsumerWidget {
  const _AttendanceCard({required this.memberId, required this.data});

  final String memberId;
  final MonthlyPayrollSummary data;

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    final shifts = data.shifts;
    final salaryByDay = {
      for (final entry in data.dailySalaries)
        entry.attendanceDate: entry.salaryPaise,
    };
    // Hiding the action is convenience only; [PayrollSummaryController
    // .deleteAttendance] re-checks the owner boundary on every call.
    final isOwner = ref.watch(userProfileProvider).value?.isOwner ?? false;
    final busy = ref.watch(payrollSummaryProvider(memberId)).isLoading;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attendance',
            style: textTheme.titleMedium?.copyWith(
              color: appColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (shifts.isEmpty)
            Text(
              'No attendance recorded this month.',
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...shifts.map(
              (shift) => Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${shift.attendanceDate.day} ${_monthNames[shift.attendanceDate.month - 1]}'
                            '${shift.attendanceDate.year == DateTime.now().year ? '' : ' ${shift.attendanceDate.year}'}',
                            style: textTheme.bodyMedium?.copyWith(
                              color: appColors.textPrimary,
                            ),
                          ),
                          Text(
                            '${TimeOfDay.fromDateTime(shift.inAt.toLocal()).format(context)}'
                            '${shift.isOpen ? ' – open' : ' – ${TimeOfDay.fromDateTime(shift.outAt!.toLocal()).format(context)}'}',
                            style: textTheme.labelSmall?.copyWith(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                salaryByDay[shift.attendanceDate] == null
                                    ? 'Daily salary: not set'
                                    : 'Daily salary ${Money.formatPaise(salaryByDay[shift.attendanceDate]!)}',
                                style: textTheme.labelSmall?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              IconButton(
                                tooltip: 'Set daily salary',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _editDailySalaryFromHistory(
                                  context,
                                  ref,
                                  attendanceDate: shift.attendanceDate,
                                  current: salaryByDay[shift.attendanceDate],
                                ),
                                icon: const Icon(Icons.edit_outlined, size: 16),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Text(
                      shift.isOpen
                          ? 'In progress'
                          : formatHoursMinutes(shift.workedMinutes),
                      style: textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isOwner)
                      IconButton(
                        tooltip: 'Delete attendance',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.error,
                        ),
                        onPressed: busy
                            ? null
                            : () =>
                                  _deleteAttendance(context, ref, shift: shift),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editDailySalaryFromHistory(
    BuildContext context,
    WidgetRef ref, {
    required DateTime attendanceDate,
    required int? current,
  }) async {
    final controller = TextEditingController(
      text: current == null ? '' : Money.paiseToRupeesInput(current),
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Daily salary'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Salary for this day (rupees)',
            hintText: 'e.g. 300',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final text = controller.text.trim();
    if (text.isEmpty) {
      await ref
          .read(payrollSummaryProvider(memberId).notifier)
          .setDailySalary(attendanceDate, null);
      return;
    }
    final paise = Money.parseRupeesToPaise(text);
    if (paise == null) return;
    await ref
        .read(payrollSummaryProvider(memberId).notifier)
        .setDailySalary(attendanceDate, paise);
  }

  /// Owner-only, confirmed removal of one attendance shift. The record is
  /// deleted in the cloud first and then in the local mirror, so it disappears
  /// from every device for the shop; the month reloads and working days, hours,
  /// salary and final payable are recomputed from the remaining records.
  Future<void> _deleteAttendance(
    BuildContext context,
    WidgetRef ref, {
    required StaffAttendanceRecord shift,
  }) async {
    final day = DateTime(
      shift.attendanceDate.year,
      shift.attendanceDate.month,
      shift.attendanceDate.day,
    );
    final hours = shift.isOpen
        ? 'open shift'
        : '${TimeOfDay.fromDateTime(shift.inAt.toLocal()).format(context)}'
              ' – '
              '${TimeOfDay.fromDateTime(shift.outAt!.toLocal()).format(context)}'
              ' (${formatHoursMinutes(shift.workedMinutes)})';
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete attendance',
      subject: '${day.day} ${_monthNames[day.month - 1]} ${day.year} · $hours',
      consequence:
          "This shift is removed for good and stops counting toward the "
          "month's working days, hours and final payable. Every other device "
          'for the shop loses it too. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    await ref
        .read(payrollSummaryProvider(memberId).notifier)
        .deleteAttendance(shift.id);
  }
}
