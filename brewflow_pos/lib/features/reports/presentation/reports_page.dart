import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports Landing Page
///
/// One scrollable page over the reports controller: date-range selector
/// (today / 7 / 30 / 90 days / custom), sales KPIs, hand-drawn daily sales
/// chart, payment-method split, active-expense summary, profit & loss with
/// honest cost resolution, top products and category performance.
///
/// Every figure comes from the repositories; without data the page shows
/// honest empty states ('—', guidance and notes) — never invented figures.
/// ---------------------------------------------------------------------------

final class ReportsPage extends ConsumerWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportsControllerProvider);
    if (MediaQuery.sizeOf(context).width < AppBreakpoints.compact) {
      return const _PhoneReportsLayout();
    }
    return Padding(
      padding: AppInsets.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Reports',
            subtitle: 'Sales, expenses and profit for a date range.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _RangeSelector(),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: report.when(
              skipLoadingOnRefresh: true,
              loading: () =>
                  const LoadingState(message: 'Crunching your numbers…'),
              error: (error, stackTrace) => ErrorState(
                message: reportsErrorMessage(error),
                onRetry: () => ref.invalidate(reportsControllerProvider),
              ),
              data: (snapshot) => _ReportContent(snapshot: snapshot),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone (<600dp) layout: full-bleed cards with a two-column KPI grid,
/// compact date-range chips and a shorter sales chart. Tablet/desktop build
/// the standard padded layout above; every section below reuses the shared
/// card widgets and all user-visible strings.
final class _PhoneReportsLayout extends ConsumerWidget {
  const _PhoneReportsLayout();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportsControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.none,
          ),
          child: PageHeader(
            title: 'Reports',
            subtitle: 'Sales, expenses and profit for a date range.',
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.none,
          ),
          child: _RangeSelector(),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: report.when(
            skipLoadingOnRefresh: true,
            loading: () =>
                const LoadingState(message: 'Crunching your numbers…'),
            error: (error, stackTrace) => ErrorState(
              message: reportsErrorMessage(error),
              onRetry: () => ref.invalidate(reportsControllerProvider),
            ),
            data: (snapshot) => _PhoneReportContent(snapshot: snapshot),
          ),
        ),
      ],
    );
  }
}

final class _PhoneReportContent extends ConsumerWidget {
  const _PhoneReportContent({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        final syncFuture = ref.read(syncStatusProvider.notifier).syncNow();
        // ignore: unused_result
        await ref.refresh(reportsControllerProvider.future);
        await syncFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.massive,
        ),
        children: [
          _PhoneSummaryKpis(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _PhoneSalesOverviewCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _PaymentMethodsCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _ExpensesCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _ProfitLossCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _TopProductsCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.xl),
          _CategoryPerformanceCard(snapshot: snapshot),
        ],
      ),
    );
  }
}

final class _PhoneSummaryKpis extends StatelessWidget {
  const _PhoneSummaryKpis({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sales = snapshot.sales;
    final hasSales = sales.orderCount > 0;
    final average = sales.averageSalePaise;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 148,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      children: [
        KpiCard(
          label: 'Sales',
          value: hasSales ? Money.formatPaise(sales.totalPaise) : '—',
          icon: Icons.payments_outlined,
          caption: 'Counter receipts in the range',
        ),
        KpiCard(
          label: 'Orders',
          value: '${sales.orderCount}',
          icon: Icons.receipt_long_outlined,
          accent: AppColors.secondary,
          caption: 'Completed sales',
        ),
        KpiCard(
          label: 'Items',
          value: '${sales.itemCount}',
          icon: Icons.shopping_basket_outlined,
          accent: AppColors.info,
          caption: 'Pieces sold',
        ),
        KpiCard(
          label: 'Avg. Sale',
          value: average == null ? '—' : Money.formatPaise(average),
          icon: Icons.insights,
          accent: AppColors.gold,
          caption: 'Average order value',
        ),
      ],
    );
  }
}

final class _PhoneSalesOverviewCard extends StatelessWidget {
  const _PhoneSalesOverviewCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sales = snapshot.sales;
    final startDay = snapshot.range.fromUtc == null
        ? null
        : DateTime(
            snapshot.range.fromUtc!.toLocal().year,
            snapshot.range.fromUtc!.toLocal().month,
            snapshot.range.fromUtc!.toLocal().day,
          );
    return SectionCard(
      title: 'Sales Overview',
      subtitle: _rangeLabel(snapshot.range),
      child: SizedBox(
        height: 132,
        child: _DailySalesChart(
          daily: sales.dailySalesPaise,
          startDay: startDay,
          barMaxHeight: 100,
        ),
      ),
    );
  }
}

final class _RangeSelector extends ConsumerStatefulWidget {
  const _RangeSelector();

  @override
  ConsumerState<_RangeSelector> createState() => _RangeSelectorState();
}

final class _RangeSelectorState extends ConsumerState<_RangeSelector> {
  static const List<OrdersDatePreset> _presets = [
    OrdersDatePreset.today,
    OrdersDatePreset.last7,
    OrdersDatePreset.last30,
    OrdersDatePreset.last90,
  ];

  String _presetLabel(OrdersDatePreset preset) => switch (preset) {
    OrdersDatePreset.today => 'Today',
    OrdersDatePreset.last7 => 'Last 7 days',
    OrdersDatePreset.last30 => 'Last 30 days',
    OrdersDatePreset.last90 => 'Last 90 days',
    OrdersDatePreset.custom => 'Custom',
    OrdersDatePreset.all => 'All time',
  };

  Future<void> _pickCustomRange() async {
    final current = ref.read(reportsRangeProvider);
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: current.fromUtc == null || current.toUtc == null
          ? null
          : DateTimeRange(
              start: current.fromUtc!.toLocal(),
              end: current.toUtc!.toLocal(),
            ),
      helpText: 'Select the report date range',
      saveText: 'Apply',
    );
    if (picked == null || !mounted) return;
    ref
        .read(reportsRangeProvider.notifier)
        .setCustomRange(picked.start, picked.end);
  }

  void _select(OrdersDatePreset preset) {
    if (preset == OrdersDatePreset.custom) {
      _pickCustomRange();
      return;
    }
    ref.read(reportsRangeProvider.notifier).setPreset(preset);
  }

  @override
  Widget build(BuildContext context) {
    final range = ref.watch(reportsRangeProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final preset in _presets) ...[
            AppFilterChip(
              label: _presetLabel(preset),
              selected: range.datePreset == preset,
              onSelected: (_) => _select(preset),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          AppFilterChip(
            label: 'Custom',
            selected: range.isCustom,
            onSelected: (_) => _select(OrdersDatePreset.custom),
          ),
        ],
      ),
    );
  }
}

final class _ReportContent extends ConsumerWidget {
  const _ReportContent({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        final syncFuture = ref.read(syncStatusProvider.notifier).syncNow();
        // ignore: unused_result
        await ref.refresh(reportsControllerProvider.future);
        await syncFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.massive),
        children: [
          _SummaryKpis(snapshot: snapshot),
          const SizedBox(height: AppSpacing.sectionSpacing),
          _SalesOverviewCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.sectionSpacing),
          _PaymentMethodsCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.sectionSpacing),
          _ExpensesCard(snapshot: snapshot),
          const SizedBox(height: AppSpacing.sectionSpacing),
          _ProfitLossCard(snapshot: snapshot),
          SizedBox(height: AppSpacing.sectionSpacing),
          _TopProductsCard(snapshot: snapshot),
          SizedBox(height: AppSpacing.sectionSpacing),
          _CategoryPerformanceCard(snapshot: snapshot),
        ],
      ),
    );
  }
}

final class _SummaryKpis extends StatelessWidget {
  const _SummaryKpis({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sales = snapshot.sales;
    final hasSales = sales.orderCount > 0;
    final average = sales.averageSalePaise;
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240,
        mainAxisExtent: 148,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      children: [
        KpiCard(
          label: 'Sales',
          value: hasSales ? Money.formatPaise(sales.totalPaise) : '—',
          icon: Icons.payments_outlined,
          caption: 'Counter receipts in the range',
        ),
        KpiCard(
          label: 'Orders',
          value: '${sales.orderCount}',
          icon: Icons.receipt_long_outlined,
          accent: AppColors.secondary,
          caption: 'Completed sales',
        ),
        KpiCard(
          label: 'Items',
          value: '${sales.itemCount}',
          icon: Icons.shopping_basket_outlined,
          accent: AppColors.info,
          caption: 'Pieces sold',
        ),
        KpiCard(
          label: 'Avg. Sale',
          value: average == null ? '—' : Money.formatPaise(average),
          icon: Icons.insights,
          accent: AppColors.gold,
          caption: 'Average order value',
        ),
      ],
    );
  }
}

String _rangeLabel(ReportRange range) => switch (range.datePreset) {
  OrdersDatePreset.today => 'Today',
  OrdersDatePreset.last7 => 'Last 7 days',
  OrdersDatePreset.last30 => 'Last 30 days',
  OrdersDatePreset.last90 => 'Last 90 days',
  OrdersDatePreset.custom =>
    range.fromUtc == null
        ? 'Custom range'
        : '${DateFormat('d MMM').format(range.fromUtc!.toLocal())} – '
              '${DateFormat('d MMM yyyy').format(range.toUtc!.toLocal())}',
  OrdersDatePreset.all => 'All time',
};

final class _SalesOverviewCard extends StatelessWidget {
  const _SalesOverviewCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final sales = snapshot.sales;
    final startDay = snapshot.range.fromUtc == null
        ? null
        : DateTime(
            snapshot.range.fromUtc!.toLocal().year,
            snapshot.range.fromUtc!.toLocal().month,
            snapshot.range.fromUtc!.toLocal().day,
          );
    return SectionCard(
      title: 'Sales Overview',
      subtitle: _rangeLabel(snapshot.range),
      child: SizedBox(
        height: 190,
        child: _DailySalesChart(
          daily: sales.dailySalesPaise,
          startDay: startDay,
        ),
      ),
    );
  }
}

final class _DailySalesChart extends StatefulWidget {
  const _DailySalesChart({
    required this.daily,
    required this.startDay,
    this.barMaxHeight = 128,
  });

  final List<int> daily;

  /// Local midnight of the first day of the range (label anchors).
  final DateTime? startDay;

  /// Height of the tallest bar; compact layouts pass a smaller value.
  final double barMaxHeight;

  @override
  State<_DailySalesChart> createState() => _DailySalesChartState();
}

class _DailySalesChartState extends State<_DailySalesChart> {
  int? _selected;

  void _showDay(BuildContext context, int index) {
    final amount = widget.daily[index];
    final date = widget.startDay?.add(Duration(days: index));
    final label = date != null
        ? DateFormat('EEE, d MMM yyyy').format(date)
        : 'Day ${index + 1}';
    final amountText = Money.formatPaise(amount);
    setState(() => _selected = index);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        margin: EdgeInsets.all(AppSpacing.md),
        padding: EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Theme.of(sheetContext).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(
                    Icons.calendar_today_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(sheetContext).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
            SizedBox(height: AppSpacing.sm),
            Divider(height: 1, color: Theme.of(sheetContext).dividerColor),
            SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sales',
                        style: Theme.of(sheetContext).textTheme.labelSmall
                            ?.copyWith(
                              color: Theme.of(
                                sheetContext,
                              ).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        amount > 0 ? amountText : 'No sales — 0',
                        style: Theme.of(sheetContext).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: amount > 0 ? null : AppColors.error,
                            ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: amount > 0
                        ? AppColors.success.withValues(alpha: 0.12)
                        : AppColors.textDisabled.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    amount > 0 ? 'Revenue' : 'Zero',
                    style: Theme.of(sheetContext).textTheme.labelSmall
                        ?.copyWith(
                          color: amount > 0
                              ? AppColors.success
                              : Theme.of(
                                  sheetContext,
                                ).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _selected = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxValue = widget.daily.fold<int>(
      0,
      (max, value) => value > max ? value : max,
    );
    if (maxValue <= 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_chart_outlined,
              size: 32,
              color: context.appColors.textDisabled,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'No sales recorded in this window',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    if (widget.daily.length > 366) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.date_range_outlined,
              size: 32,
              color: context.appColors.textDisabled,
            ),
            SizedBox(height: AppSpacing.sm),
            Text(
              'Daily chart is hidden for ranges over one year.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }
    final showLabels = widget.daily.length <= 14;
    final gap = showLabels ? AppSpacing.xs : 0.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.daily.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: gap),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _showDay(context, i),
                        child: Container(
                          width: double.infinity,
                          height:
                              4 +
                              (widget.daily[i] / maxValue) *
                                  widget.barMaxHeight,
                          decoration: BoxDecoration(
                            color: _selected == i
                                ? AppColors.gold
                                : i == widget.daily.length - 1
                                ? AppColors.gold.withValues(alpha: 0.85)
                                : AppColors.primary,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadius.sm),
                            ),
                            border: _selected == i
                                ? Border.all(
                                    color: AppColors.charcoal,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (showLabels) ...[
                    SizedBox(height: AppSpacing.xs),
                    if (widget.startDay != null)
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          DateFormat(
                            'd MMM',
                          ).format(widget.startDay!.add(Duration(days: i))),
                          style: textTheme.labelSmall?.copyWith(
                            color: i == widget.daily.length - 1
                                ? context.appColors.charcoal
                                : context.appColors.textSecondary,
                            fontWeight: i == widget.daily.length - 1
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final class _PaymentMethodsCard extends StatelessWidget {
  const _PaymentMethodsCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final payments = snapshot.payments;
    final hasSales = snapshot.sales.orderCount > 0;
    return SectionCard(
      title: 'Payment Methods',
      subtitle: 'How the selected range was paid',
      child: Column(
        children: [
          _PaymentRow(
            label: 'Cash',
            color: AppColors.cash,
            amount: hasSales
                ? Money.formatPaise(payments.paiseOf(PaymentMethod.cash))
                : '—',
            share: payments.shareOf(PaymentMethod.cash),
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PaymentRow(
            label: 'UPI',
            color: AppColors.upi,
            amount: hasSales
                ? Money.formatPaise(payments.paiseOf(PaymentMethod.upi))
                : '—',
            share: payments.shareOf(PaymentMethod.upi),
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PaymentRow(
            label: 'Bank',
            color: AppColors.card,
            amount: hasSales
                ? Money.formatPaise(payments.paiseOf(PaymentMethod.bank))
                : '—',
            share: payments.shareOf(PaymentMethod.bank),
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                hasSales ? Money.formatPaise(payments.totalPaise) : '—',
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.label,
    required this.color,
    required this.amount,
    required this.share,
  });

  final String label;
  final Color color;
  final String amount;
  final int? share;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.charcoal,
              ),
            ),
          ),
          Text(
            share == null ? '—' : '$share%',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Text(
            amount,
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ExpensesCard extends StatelessWidget {
  const _ExpensesCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final summary = snapshot.expenses;
    if (summary.count == 0) {
      return SectionCard(
        title: 'Expenses Summary',
        subtitle: 'Active expenses in the range',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'No expenses recorded in this range',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
      );
    }
    return SectionCard(
      title: 'Expenses Summary',
      subtitle: 'Active expenses in the range',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total Expenses',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                Money.formatPaise(summary.totalPaise),
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${summary.count} expense${summary.count == 1 ? '' : 's'}',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ),
          Divider(height: 20, thickness: 1, color: context.appColors.divider),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'By category',
              style: textTheme.labelMedium?.copyWith(
                color: context.appColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in summary.byCategoryPaise.entries) ...[
            SizedBox(height: AppSpacing.xs),
            _LabelAmountRow(label: entry.key.label, amount: entry.value),
          ],
          Divider(height: 20, thickness: 1, color: context.appColors.divider),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'By payment method',
              style: textTheme.labelMedium?.copyWith(
                color: context.appColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final entry in summary.byPaymentPaise.entries) ...[
            SizedBox(height: AppSpacing.xs),
            _LabelAmountRow(
              label: paymentMethodLabel(entry.key),
              amount: entry.value,
            ),
          ],
        ],
      ),
    );
  }
}

final class _LabelAmountRow extends StatelessWidget {
  const _LabelAmountRow({required this.label, required this.amount});

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.charcoal,
              ),
            ),
          ),
          Text(
            Money.formatPaise(amount),
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ProfitLossCard extends StatelessWidget {
  const _ProfitLossCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  static String _signed(int paise) =>
      paise < 0 ? '-${Money.formatPaise(-paise)}' : Money.formatPaise(paise);

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final pnl = snapshot.profitLoss;
    final cogs = pnl.cogsPaise;
    final net = pnl.netProfitPaise;
    final unknownProfit = cogs == null && pnl.hasSales;
    final showNet = net != null && (pnl.hasSales || pnl.hasExpenses);
    return SectionCard(
      title: 'Profit & Loss',
      subtitle: 'Sales − cost of goods − expenses',
      child: Column(
        children: [
          _PnLRow(
            label: 'Sales',
            value: pnl.hasSales ? Money.formatPaise(pnl.salesPaise) : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PnLRow(
            label: 'Cost of Goods',
            value: pnl.hasSales && cogs != null ? Money.formatPaise(cogs) : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PnLRow(
            label: 'Expenses',
            value: pnl.hasExpenses ? Money.formatPaise(pnl.expensesPaise) : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PnLRow(
            label: 'Net Profit',
            value: showNet ? _signed(net) : '—',
            emphasize: true,
          ),
          if (unknownProfit) ...[
            SizedBox(height: AppSpacing.md),
            Text(
              'Add cost prices to see profit',
              style: textTheme.bodySmall?.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (pnl.partialCosts) ...[
            SizedBox(height: AppSpacing.md),
            Text(
              'Profit uses only lines with current cost prices',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
          SizedBox(height: AppSpacing.md),
          Text(
            'Profit uses current product cost prices; historical sale-time '
            'cost is not stored.',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textDisabled,
            ),
          ),
        ],
      ),
    );
  }
}

final class _PnLRow extends StatelessWidget {
  const _PnLRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final emphasized = emphasize
        ? textTheme.titleSmall?.copyWith(
            color: context.appColors.charcoal,
            fontWeight: FontWeight.w700,
          )
        : textTheme.bodyMedium?.copyWith(color: context.appColors.charcoal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: emphasized)),
          Text(value, style: emphasized),
        ],
      ),
    );
  }
}

final class _TopProductsCard extends StatelessWidget {
  const _TopProductsCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = snapshot.topProducts;
    return SectionCard(
      title: 'Top Products',
      subtitle: 'By sales revenue · top 5',
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No products sold in this range',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 12,
                      thickness: 1,
                      color: context.appColors.divider,
                    ),
                  _ProductRow(row: rows[i]),
                ],
              ],
            ),
    );
  }
}

final class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.row});

  final ProductPerformanceRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.variantName == null
                      ? row.productName
                      : '${row.productName} — ${row.variantName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '${row.unitsSold} pcs',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Text(
            Money.formatPaise(row.revenuePaise),
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

final class _CategoryPerformanceCard extends StatelessWidget {
  const _CategoryPerformanceCard({required this.snapshot});

  final ReportsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final rows = snapshot.categoryPerformance;
    return SectionCard(
      title: 'Category Performance',
      subtitle: "Category performance uses the product's current category.",
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                'No sales recorded in this range',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            )
          : Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 12,
                      thickness: 1,
                      color: context.appColors.divider,
                    ),
                  _LabelAmountRow(
                    label: rows[i].categoryName,
                    amount: rows[i].revenuePaise,
                  ),
                ],
              ],
            ),
    );
  }
}
