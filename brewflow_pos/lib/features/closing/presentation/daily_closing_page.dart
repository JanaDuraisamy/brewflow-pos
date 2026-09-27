import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing Page
///
/// Owner-only end-of-day cash/sales recording and review. Amounts are entered
/// in rupees and stored as integer paise; every field is optional-but-zeroed
/// so a partial close never blocks saving. Records are immutable — correcting
/// a day means saving a new closing for the same business date.
///
/// Selecting a date auto-loads that day's cash/UPI totals from completed
/// sales and expenses from the expense data; Total Sales auto-calculates as
/// Cash + UPI but stays manually overridable. Opening a date that already
/// has a saved closing loads the latest saved values instead. Records sync
/// to the cloud and load on any owner device.
/// ---------------------------------------------------------------------------

final class DailyClosingPage extends ConsumerStatefulWidget {
  const DailyClosingPage({super.key});

  @override
  ConsumerState<DailyClosingPage> createState() => _DailyClosingPageState();
}

final class _DailyClosingPageState extends ConsumerState<DailyClosingPage> {
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

  final _cash = TextEditingController();
  final _upi = TextEditingController();
  final _sales = TextEditingController();
  final _expenses = TextEditingController();
  final _cashInBox = TextEditingController();
  final _cashTakenOut = TextEditingController();
  final _takenOutBy = TextEditingController();
  final _talliedBy = TextEditingController();
  final _note = TextEditingController();

  late DateTime _businessDate;
  String? _amountError;

  /// The date the form was last prefilled for; null until the first fill.
  /// Guards the post-frame autofill so it runs once per date/totals load.
  DateTime? _prefilledFor;

  /// True once the owner types into Total Sales: the auto-calculation
  /// (Cash + UPI) must never clobber a manual override afterwards.
  bool _salesTouched = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _businessDate = DateTime.utc(now.year, now.month, now.day);
    _sales.addListener(() {
      if (_sales.text.trim().isNotEmpty) _salesTouched = true;
    });
  }

  @override
  void dispose() {
    _cash.dispose();
    _upi.dispose();
    _sales.dispose();
    _expenses.dispose();
    _cashInBox.dispose();
    _cashTakenOut.dispose();
    _takenOutBy.dispose();
    _talliedBy.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Back to the dashboard. Entries arrive via go() (push() does not
  /// resolve across navigators in this router setup), so history is empty:
  /// pop when something is actually below, otherwise go to the dashboard.
  void _goBack() {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closings = ref.watch(dailyClosingsProvider);
    final totals = ref.watch(closingDayTotalsProvider(_businessDate));
    final phone = MediaQuery.sizeOf(context).width < 600;

    ref.listen(dailyClosingsProvider, (previous, next) {
      if (next.hasError && next.error is DailyClosingFailure) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text((next.error! as DailyClosingFailure).message),
            ),
          );
      }
    });

    _maybeAutofill(totals: totals.value, saved: closings.value);

    // PopScope owns the Android system back/gesture (entries arrive via
    // go(), so no history exists to pop): it returns to the dashboard
    // instead of exiting the app. Same destination as the Back button.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _goBack();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _goBack),
          title: const Text('Daily Closing'),
          centerTitle: false,
        ),
        body: Padding(
          padding: AppInsets.screen,
          child: phone
              ? _buildPhone(context, closings)
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1020),
                    child: _buildPhone(context, closings),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildPhone(
    BuildContext context,
    AsyncValue<List<DailyClosingRecord>> closings,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Daily Closing',
            subtitle: 'Record and review end-of-day sales & cash tallies.',
          ),
          const SizedBox(height: AppSpacing.lg),
          _DaySummaryCard(businessDate: _businessDate),
          const SizedBox(height: AppSpacing.lg),
          _recordForm(context),
          const SizedBox(height: AppSpacing.xxxl),
          Text(
            'Saved closings',
            style: textTheme.titleMedium?.copyWith(
              color: appColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...closings.when(
            skipLoadingOnRefresh: true,
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: LoadingState(message: 'Loading closings…'),
                ),
              ),
            ],
            error: (error, stackTrace) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: ErrorState(
                  message: _closingsErrorMessage(error),
                  onRetry: () => ref.invalidate(dailyClosingsProvider),
                ),
              ),
            ],
            data: (records) => records.isEmpty
                ? [
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                      child: EmptyState(
                        icon: Icons.nights_stay_outlined,
                        title: 'No closings saved yet',
                        message:
                            'Record your first end-of-day closing above and it will appear here.',
                      ),
                    ),
                  ]
                : records.map((record) {
                    final date = record.businessDate.toLocal();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _ClosingCard(
                        record: record,
                        dayLabel:
                            '${date.day} ${_monthNames[date.month - 1]} ${date.year}',
                      ),
                    );
                  }).toList(),
          ),
        ],
      ),
    );
  }

  /// Prefills the form once per selected date: the latest saved closing
  /// for that date when one exists, otherwise the auto-populated day
  /// totals. Only empty fields are filled and a manually overridden Total
  /// Sales is never clobbered.
  void _maybeAutofill({
    required ClosingDayTotals? totals,
    required List<DailyClosingRecord>? saved,
  }) {
    if (_prefilledFor == _businessDate) return;
    DailyClosingRecord? latest;
    if (saved != null) {
      for (final record in saved) {
        if (record.businessDate == _businessDate) {
          latest = record;
          break;
        }
      }
    }
    if (latest == null && totals == null) return;
    _prefilledFor = _businessDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (latest != null) {
          _cash.text = Money.paiseToRupeesInput(latest.totalCashPaise);
          _upi.text = Money.paiseToRupeesInput(latest.totalUpiPaise);
          _sales.text = Money.paiseToRupeesInput(latest.totalSalesPaise);
          _salesTouched = true;
          _expenses.text = Money.paiseToRupeesInput(latest.totalExpensePaise);
          _cashInBox.text = Money.paiseToRupeesInput(latest.cashLeftInBoxPaise);
          _cashTakenOut.text = Money.paiseToRupeesInput(
            latest.cashTakenOutPaise,
          );
          return;
        }
        final auto = totals!;
        if (_cash.text.trim().isEmpty) {
          _cash.text = Money.paiseToRupeesInput(auto.totalCashPaise);
        }
        if (_upi.text.trim().isEmpty) {
          _upi.text = Money.paiseToRupeesInput(auto.totalUpiPaise);
        }
        if (_expenses.text.trim().isEmpty) {
          _expenses.text = Money.paiseToRupeesInput(auto.totalExpensePaise);
        }
        if (!_salesTouched && _sales.text.trim().isEmpty) {
          _sales.text = Money.paiseToRupeesInput(auto.totalSalesPaise);
        }
      });
    });
  }

  Widget _recordForm(BuildContext context) {
    final appColors = context.appColors;
    final busy = ref.watch(dailyClosingsProvider).isLoading;
    final date = _businessDate.toLocal();
    final savedForDate =
        ref
            .watch(dailyClosingsProvider)
            .value
            ?.any((record) => record.businessDate == _businessDate) ??
        false;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: 'Pick business date',
                onPressed: _pickBusinessDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '${date.day} ${_monthNames[date.month - 1]} ${date.year}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: appColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (savedForDate) ...[
            Text(
              'Already saved for this date — saving again stores a new revision.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          const SizedBox(height: AppSpacing.md),
          _amountField(_cash, 'Total Cash', Icons.payments_outlined),
          const SizedBox(height: AppSpacing.md),
          _amountField(_upi, 'Total UPI', Icons.phone_iphone),
          const SizedBox(height: AppSpacing.md),
          _amountField(_sales, 'Total Sales', Icons.receipt_long_outlined),
          const SizedBox(height: AppSpacing.md),
          _amountField(
            _expenses,
            'Total Expenses',
            Icons.shopping_bag_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          _amountField(
            _cashInBox,
            'Cash left in box',
            Icons.inventory_2_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          _amountField(
            _cashTakenOut,
            'Cash taken out',
            Icons.file_upload_outlined,
          ),
          const SizedBox(height: AppSpacing.md),
          _textField(_takenOutBy, 'Taken out by (optional)'),
          const SizedBox(height: AppSpacing.md),
          _textField(_talliedBy, 'Tallied by (optional)'),
          const SizedBox(height: AppSpacing.md),
          _textField(_note, 'Note (optional)'),
          if (_amountError != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _amountError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Save Closing',
            icon: Icons.check,
            expanded: true,
            loading: busy,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  Widget _amountField(
    TextEditingController controller,
    String label,
    IconData icon,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: '₹ 0',
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Future<void> _pickBusinessDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 400)),
      lastDate: today,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _businessDate = DateTime.utc(picked.year, picked.month, picked.day);
      _prefilledFor = null;
      _salesTouched = false;
    });
  }

  Future<void> _save() async {
    setState(() {
      _amountError = null;
    });

    final parsed =
        {
          'Total Cash': _cash.text,
          'Total UPI': _upi.text,
          'Total Sales': _sales.text,
          'Total Expenses': _expenses.text,
          'Cash left in box': _cashInBox.text,
          'Cash taken out': _cashTakenOut.text,
        }.map((label, text) {
          final paise = Money.parseRupeesToPaise(text);
          return MapEntry(label, paise ?? (text.trim().isEmpty ? 0 : -1));
        });

    final invalid = parsed.entries.where((entry) => entry.value < 0);
    if (invalid.isNotEmpty) {
      setState(() {
        _amountError =
            '“${invalid.first.key}” must be a valid amount (e.g. 2500.50).';
      });
      return;
    }

    await ref
        .read(dailyClosingsProvider.notifier)
        .record(
          businessDate: _businessDate,
          totalCashPaise: parsed['Total Cash'] ?? 0,
          totalUpiPaise: parsed['Total UPI'] ?? 0,
          totalSalesPaise: parsed['Total Sales'] ?? 0,
          totalExpensePaise: parsed['Total Expenses'] ?? 0,
          cashLeftInBoxPaise: parsed['Cash left in box'] ?? 0,
          cashTakenOutPaise: parsed['Cash taken out'] ?? 0,
          takenOutBy: _takenOutBy.text.trim().isEmpty
              ? null
              : _takenOutBy.text.trim(),
          talliedBy: _talliedBy.text.trim().isEmpty
              ? null
              : _talliedBy.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        );

    if (!mounted) return;
    // The provider surfaces failures (e.g. All-businesses scope) through
    // the state listener above — only clear on a real save.
    if (ref.read(dailyClosingsProvider).hasError) return;
    _clearForm();
    _prefilledFor = null;
    _salesTouched = false;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(const SnackBar(content: Text('Closing saved.')));
  }

  void _clearForm() {
    _cash.clear();
    _upi.clear();
    _sales.clear();
    _expenses.clear();
    _cashInBox.clear();
    _cashTakenOut.clear();
    _takenOutBy.clear();
    _talliedBy.clear();
    _note.clear();
  }

  static String _closingsErrorMessage(Object error) {
    if (error is DailyClosingFailure) return error.message;
    return 'Could not load closings. Check the device storage and retry.';
  }
}

/// ---------------------------------------------------------------------------
/// Day summary — a read-only preview of the selected business date: the saved
/// closing values when the date is already closed, otherwise the auto totals
/// derived from that day's paid sales and expenses. Text-only: it never adds
/// fields to the form below.
/// ---------------------------------------------------------------------------

final class _DaySummaryCard extends ConsumerWidget {
  const _DaySummaryCard({required this.businessDate});

  final DateTime businessDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    DailyClosingRecord? saved;
    for (final record
        in ref.watch(dailyClosingsProvider).value ??
            const <DailyClosingRecord>[]) {
      if (record.businessDate == businessDate) {
        saved = record;
        break;
      }
    }
    final totals = ref.watch(closingDayTotalsProvider(businessDate)).value;

    final savedValues = saved != null;
    final cash = savedValues ? saved.totalCashPaise : totals?.totalCashPaise;
    final upi = savedValues ? saved.totalUpiPaise : totals?.totalUpiPaise;
    final sales = savedValues ? saved.totalSalesPaise : totals?.totalSalesPaise;
    final expenses = savedValues
        ? saved.totalExpensePaise
        : totals?.totalExpensePaise;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.summarize_outlined,
                size: 20,
                color: appColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Day summary',
                  style: textTheme.titleMedium?.copyWith(
                    color: appColors.textPrimary,
                  ),
                ),
              ),
              _DaySummaryChip(
                label: savedValues ? 'Saved' : 'Auto-calculated',
                color: savedValues ? AppColors.success : AppColors.info,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _summaryRow(context, label: 'Cash', paise: cash),
          _summaryRow(context, label: 'UPI', paise: upi),
          _summaryRow(context, label: 'Sales', paise: sales),
          _summaryRow(context, label: 'Expenses', paise: expenses),
          if (savedValues) ...[
            const Divider(height: AppSpacing.xl),
            _summaryRow(
              context,
              label: 'Cash in box',
              paise: saved.cashLeftInBoxPaise,
            ),
            _summaryRow(
              context,
              label: 'Cash taken out',
              paise: saved.cashTakenOutPaise,
            ),
          ],
          if (!savedValues)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'Preview from this day’s sales and expenses — saving a '
                'closing stores them.',
                style: textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required String label,
    required int? paise,
  }) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            paise == null ? '—' : Money.formatPaise(paise),
            style: textTheme.bodyMedium?.copyWith(
              color: appColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Day summary source pill: Saved / Auto-calculated.
/// ---------------------------------------------------------------------------

final class _DaySummaryChip extends StatelessWidget {
  const _DaySummaryChip({required this.label, required this.color});

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
/// One saved closing record.
/// ---------------------------------------------------------------------------

final class _ClosingCard extends ConsumerWidget {
  const _ClosingCard({required this.record, required this.dayLabel});

  final DailyClosingRecord record;
  final String dayLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.nights_stay_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  dayLabel,
                  style: textTheme.titleSmall?.copyWith(
                    color: appColors.textPrimary,
                  ),
                ),
              ),
              // Owner-only: the delete action is rendered for the owner alone
              // and DailyClosingsController.remove enforces the same boundary.
              if (ref.watch(userProfileProvider).value?.isOwner ?? false)
                Tooltip(
                  message: 'Delete closing',
                  child: IconButton(
                    onPressed: () => _confirmDelete(context, ref),
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _amountRow(context, 'Cash', record.totalCashPaise),
          _amountRow(context, 'UPI', record.totalUpiPaise),
          _amountRow(context, 'Sales', record.totalSalesPaise),
          _amountRow(context, 'Expenses', record.totalExpensePaise),
          const Divider(height: AppSpacing.xl),
          _amountRow(context, 'Cash in box', record.cashLeftInBoxPaise),
          _amountRow(context, 'Cash taken out', record.cashTakenOutPaise),
          if (record.takenOutBy != null)
            _noteRow(context, 'Taken out by', record.takenOutBy!),
          if (record.talliedBy != null)
            _noteRow(context, 'Tallied by', record.talliedBy!),
          if (record.note != null) _noteRow(context, 'Note', record.note!),
        ],
      ),
    );
  }

  Widget _amountRow(BuildContext context, String label, int paise) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            Money.formatPaise(paise),
            style: textTheme.bodyMedium?.copyWith(
              color: appColors.textPrimary,
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$label · $value',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete closing?'),
        content: Text(
          'Delete the closing for $dayLabel? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(dailyClosingsProvider.notifier).remove(record.id);
  }
}
