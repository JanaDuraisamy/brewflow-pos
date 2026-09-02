import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Dashboard Landing Page
///
/// Real-data landing page over the dashboard controller: greeting header
/// with date selection, today's KPIs, the seven-day sales chart, payment
/// split, stock alerts, recent bills, quick actions and a business summary.
/// Every figure comes from the repositories; without data the page shows
/// honest empty states ('—', zeroed counts and guidance) — never invented
/// figures.
/// ---------------------------------------------------------------------------

final class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardControllerProvider);
    return snapshot.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingState(message: "Crunching today's numbers…"),
      error: (error, stackTrace) => ErrorState(
        message: dashboardErrorMessage(error),
        onRetry: () => ref.invalidate(dashboardControllerProvider),
      ),
      data: (data) => _DashboardContent(snapshot: data),
    );
  }
}

final class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final email = auth.userEmail ?? 'Owner';
    final selected = ref.watch(dashboardDateProvider);
    final shopSettings = ref.watch(shopSettingsProvider).value;
    final shopName = shopSettings?.shopName ?? ShopSettings.defaults().shopName;
    final ownerName = shopSettings?.ownerName;
    return RefreshIndicator(
      onRefresh: () async {
        // Pull-to-refresh must run a real sync cycle, not just reload local
        // dashboard data — reuse the existing engine via syncNow (no second
        // timer, serialized, offline-safe).
        final syncFuture = ref.read(syncStatusProvider.notifier).syncNow();
        // ignore: unused_result
        await ref.refresh(dashboardControllerProvider.future);
        await syncFuture;
      },
      child: ResponsiveBuilder(
        builder: (context, breakpoint) {
          final horizontal = breakpoint.isCompact
              ? AppSpacing.lg
              : AppSpacing.screenPadding;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              horizontal,
              breakpoint.isCompact ? AppSpacing.lg : AppSpacing.xl,
              horizontal,
              AppSpacing.massive,
            ),
            children: [
              _DashboardHeader(
                selected: selected,
                alerts: snapshot.lowStockCount + snapshot.outOfStockCount,
                onPickDate: () => _pickDate(context, ref, selected),
                onNotifications: () => context.go(AppRoutes.inventory),
                onAvatarTap: () => showAccountMenu(context, email: email),
                avatarName: email,
                shopName: shopName,
                ownerName: ownerName,
              ),
              const SizedBox(height: AppSpacing.xl),
              _KpiGrid(snapshot: snapshot),
              const SizedBox(height: AppSpacing.sectionSpacing),
              _SalesOverview(
                weeklySalesPaise: snapshot.weeklySalesPaise,
                selected: selected,
              ),
              const SizedBox(height: AppSpacing.sectionSpacing),
              _PaymentSummary(snapshot: snapshot),
              if (snapshot.businessBreakdown.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sectionSpacing),
                _BusinessBreakdownCard(breakdown: snapshot.businessBreakdown),
              ],
              const SizedBox(height: AppSpacing.sectionSpacing),
              _AlertsSection(
                snapshot: snapshot,
                onOpenDueCustomers: () {
                  // Deep-link with the explicit due filter so the counter sees
                  // only customers that currently owe money.
                  ref.read(customersFilterProvider.notifier).setDueOnly(true);
                  context.go(AppRoutes.customers);
                },
              ),
              const SizedBox(height: AppSpacing.sectionSpacing),
              _RecentBillsSection(recentBills: snapshot.recentBills),
              const SizedBox(height: AppSpacing.sectionSpacing),
              const _SectionTitle('Quick actions'),
              const SizedBox(height: AppSpacing.md),
              const _ActionGrid(),
              const SizedBox(height: AppSpacing.sectionSpacing),
              _GlanceSection(snapshot: snapshot),
              SizedBox(height: AppSpacing.sectionSpacing),
              const _SyncStatusCard(),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pickDate(
    BuildContext context,
    WidgetRef ref,
    DateTime selected,
  ) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: selected.isAfter(today) ? today : selected,
      firstDate: DateTime(2020),
      lastDate: today,
    );
    if (picked != null) {
      ref.read(dashboardDateProvider.notifier).select(picked);
    }
  }
}

final class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.selected,
    required this.alerts,
    required this.onPickDate,
    required this.onNotifications,
    required this.onAvatarTap,
    required this.avatarName,
    required this.shopName,
    this.ownerName,
  });

  final DateTime selected;
  final int alerts;
  final VoidCallback onPickDate;
  final VoidCallback onNotifications;
  final VoidCallback onAvatarTap;
  final String avatarName;

  /// Saved business identity shown as the brand line of the dashboard. The
  /// BrewFlow product wordmark elsewhere in the shell is product branding
  /// and stays untouched.
  final String shopName;
  final String? ownerName;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday = selected == today;
    final hour = now.hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    final displayName = ownerName ?? avatarName.split('@').first;
    final isCompact = MediaQuery.sizeOf(context).width < 600;

    final dateChip = InkWell(
      onTap: onPickDate,
      borderRadius: AppBorderRadius.pill,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? AppSpacing.lg : AppSpacing.md,
          vertical: isCompact ? AppSpacing.md : AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: context.appColors.lightGray,
          borderRadius: AppBorderRadius.pill,
          border: Border.all(color: context.appColors.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.calendar_today,
              size: 14,
              color: AppColors.primary,
            ),
            SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                isToday
                    ? 'Today · ${DateFormat('d MMM').format(selected)}'
                    : DateFormat('d MMM yyyy').format(selected),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelMedium?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: context.appColors.textSecondary,
            ),
          ],
        ),
      ),
    );

    if (isCompact) {
      // Phone: spacious, vertically stacked, Apple-inspired — generous
      // spacing, large touch targets, no horizontal squeeze.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: textTheme.labelMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
          SizedBox(height: AppSpacing.md),
          Text(
            '$greeting, $displayName!',
            style: textTheme.headlineSmall?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            shopName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            isToday
                ? "Here's what's happening at the counter."
                : 'Showing sales for ${DateFormat('d MMM yyyy').format(selected)}.',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
              height: 1.4,
            ),
          ),
          SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: '$displayName · $avatarName',
                  child: dateChip,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              NotificationBell(count: alerts, onPressed: onNotifications),
              const SizedBox(width: AppSpacing.sm),
              AppAvatar(
                name: displayName,
                backgroundColor: AppColors.primaryDark,
                onTap: onAvatarTap,
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: textTheme.labelMedium?.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$greeting, $displayName!',
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.headlineSmall?.copyWith(
                      color: context.appColors.charcoal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    shopName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    isToday
                        ? "Here's what's happening at the counter."
                        : 'Showing sales for ${DateFormat('d MMM yyyy').format(selected)}.',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Tooltip(
                message: '$displayName · $avatarName',
                child: dateChip,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            NotificationBell(count: alerts, onPressed: onNotifications),
            AppAvatar(
              name: displayName,
              backgroundColor: AppColors.primaryDark,
              onTap: onAvatarTap,
            ),
          ],
        ),
      ],
    );
  }
}

final class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasDaySales = snapshot.dayOrderCount > 0;
    final sales = hasDaySales ? Money.formatPaise(snapshot.daySalesPaise) : '—';
    final profit = snapshot.dayProfitPaise == null
        ? '—'
        : Money.formatPaise(snapshot.dayProfitPaise!);
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
          value: sales,
          icon: Icons.payments_outlined,
          caption: 'Counter receipts for the selected day',
        ),
        KpiCard(
          label: 'Profit',
          value: profit,
          icon: Icons.trending_up,
          accent: AppColors.gold,
          caption: snapshot.dayProfitPaise == null
              ? 'Add cost prices to see profit'
              : 'Total minus cost today',
        ),
        KpiCard(
          label: 'Bills',
          value: '${snapshot.dayOrderCount}',
          icon: Icons.receipt_long_outlined,
          accent: AppColors.secondary,
          caption: 'Completed sales',
        ),
        KpiCard(
          label: 'Items',
          value: '${snapshot.dayItemCount}',
          icon: Icons.shopping_basket_outlined,
          accent: AppColors.info,
          caption: 'Pieces sold',
        ),
      ],
    );
  }
}

final class _SalesOverview extends StatelessWidget {
  const _SalesOverview({
    required this.weeklySalesPaise,
    required this.selected,
  });

  final List<int> weeklySalesPaise;
  final DateTime selected;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Sales Overview',
      subtitle: 'Last 7 days ending ${DateFormat('d MMM').format(selected)}',
      child: SizedBox(
        height: 190,
        child: _WeeklySalesChart(
          days: weeklySalesPaise,
          windowStart: selected.subtract(const Duration(days: 6)),
        ),
      ),
    );
  }
}

final class _WeeklySalesChart extends StatefulWidget {
  const _WeeklySalesChart({required this.days, required this.windowStart});

  final List<int> days;
  final DateTime windowStart;

  @override
  State<_WeeklySalesChart> createState() => _WeeklySalesChartState();
}

class _WeeklySalesChartState extends State<_WeeklySalesChart> {
  int? _selected;

  void _showDay(BuildContext context, int index) {
    final amount = widget.days[index];
    final date = widget.windowStart.add(Duration(days: index));
    final label = DateFormat('EEE, d MMM yyyy').format(date);
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
            Text(
              amount > 0 ? amountText : 'No sales — 0',
              style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: amount > 0 ? null : AppColors.error,
              ),
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
    final maxValue = widget.days.fold<int>(
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < widget.days.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
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
                          height: 4 + (widget.days[i] / maxValue) * 128,
                          decoration: BoxDecoration(
                            color: _selected == i
                                ? AppColors.gold
                                : i == widget.days.length - 1
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
                  SizedBox(height: AppSpacing.xs),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      DateFormat(
                        'd MMM',
                      ).format(widget.windowStart.add(Duration(days: i))),
                      style: textTheme.labelSmall?.copyWith(
                        color: i == widget.days.length - 1
                            ? context.appColors.charcoal
                            : context.appColors.textSecondary,
                        fontWeight: i == widget.days.length - 1
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

final class _PaymentSummary extends StatelessWidget {
  const _PaymentSummary({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasSales = snapshot.dayOrderCount > 0;
    final split = snapshot.paymentSplitPaise;
    return SectionCard(
      title: 'Payment Summary',
      subtitle: "How the selected day's payments arrived",
      child: Column(
        children: [
          _PaymentRow(
            label: 'Cash',
            color: AppColors.cash,
            amount: hasSales
                ? Money.formatPaise(split[PaymentMethod.cash] ?? 0)
                : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PaymentRow(
            label: 'UPI',
            color: AppColors.upi,
            amount: hasSales
                ? Money.formatPaise(split[PaymentMethod.upi] ?? 0)
                : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          _PaymentRow(
            label: 'Bank',
            color: AppColors.card,
            amount: hasSales
                ? Money.formatPaise(split[PaymentMethod.bank] ?? 0)
                : '—',
          ),
          Divider(height: 12, thickness: 1, color: context.appColors.divider),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Total',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                hasSales ? Money.formatPaise(snapshot.daySalesPaise) : '—',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
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
  });

  final String label;
  final Color color;
  final String amount;

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

final class _AlertsSection extends ConsumerWidget {
  const _AlertsSection({
    required this.snapshot,
    required this.onOpenDueCustomers,
  });

  final DashboardSnapshot snapshot;
  final VoidCallback onOpenDueCustomers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = snapshot.dueCustomers;
    return SectionCard(
      title: 'Alerts',
      subtitle: 'Stock needs your attention',
      child: Column(
        children: [
          AlertCard(
            icon: Icons.inventory_2_outlined,
            title: 'Low Stock',
            message: snapshot.lowStockCount > 0
                ? '${snapshot.lowStockCount} active items at or below '
                      '${snapshot.lowStockThreshold} units'
                : 'No items running low right now',
            accent: AppColors.warning,
            count: snapshot.lowStockCount,
            onTap: () {
              // Open Inventory with the Low Stock filter pre-applied so only
              // currently low-stock entities are listed.
              ref.read(inventoryFilterProvider.notifier).setLowStockOnly(true);
              context.go(AppRoutes.inventory);
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          AlertCard(
            icon: Icons.remove_shopping_cart_outlined,
            title: 'Out of Stock',
            message: snapshot.outOfStockCount > 0
                ? '${snapshot.outOfStockCount} active items sold out'
                : 'Everything you sell is in stock',
            accent: AppColors.error,
            count: snapshot.outOfStockCount,
            onTap: () => context.go(AppRoutes.inventory),
          ),
          const SizedBox(height: AppSpacing.sm),
          AlertCard(
            icon: Icons.event_note_outlined,
            title: 'Due Reminders',
            message: due.dueCustomerCount > 0
                ? '${Money.formatPaise(due.totalOutstandingPaise)} '
                      'outstanding across ${due.dueCustomerCount} '
                      '${due.dueCustomerCount == 1 ? 'customer' : 'customers'}'
                : 'No dues right now — everyone is settled',
            accent: AppColors.error,
            count: due.dueCustomerCount,
            onTap: onOpenDueCustomers,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

final class _RecentBillsSection extends StatelessWidget {
  const _RecentBillsSection({required this.recentBills});

  final List<OrderSummary> recentBills;

  @override
  Widget build(BuildContext context) {
    if (recentBills.isEmpty) {
      return SectionCard(
        title: 'Recent Bills',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Text(
                'No bills recorded yet — your first sale will appear here.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SecondaryButton(
                label: 'Start a Sale',
                icon: Icons.point_of_sale_outlined,
                onPressed: () => context.go(AppRoutes.billing),
              ),
            ],
          ),
        ),
      );
    }
    return SectionCard(
      title: 'Recent Bills',
      subtitle: 'Your latest completed sales',
      child: Column(
        children: [
          for (var i = 0; i < recentBills.length; i++) ...[
            if (i > 0)
              Divider(
                height: 12,
                thickness: 1,
                color: context.appColors.divider,
              ),
            _BillRow(bill: recentBills[i]),
          ],
        ],
      ),
    );
  }
}

final class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill});

  final OrderSummary bill;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => context.go(AppRoutes.orders),
      borderRadius: AppBorderRadius.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bill.receiptNumber,
                    style: textTheme.titleSmall?.copyWith(
                      color: context.appColors.charcoal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '${bill.paymentStatus == PaymentStatus.notPaid ? 'Not paid' : paymentMethodLabel(bill.paymentMethod!)} · '
                    '${itemsLabel(bill.itemCount)} · '
                    '${formatDateTime(bill.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Text(
              Money.formatPaise(bill.totalPaise),
              style: textTheme.titleSmall?.copyWith(
                color: context.appColors.charcoal,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleLarge?.copyWith(color: context.appColors.textPrimary),
    );
  }
}

final class _ActionGrid extends StatelessWidget {
  const _ActionGrid();

  static const List<(IconData, String, String, String)> _actions = [
    (
      Icons.point_of_sale_outlined,
      'New Sale',
      'Start a sale at the counter',
      AppRoutes.billing,
    ),
    (
      Icons.inventory_2_outlined,
      'Manage Inventory',
      'Add and track products',
      AppRoutes.inventory,
    ),
    (
      Icons.receipt_long_outlined,
      'Review Orders',
      'See recent orders',
      AppRoutes.orders,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 320,
        mainAxisExtent: 84,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
      ),
      children: [
        for (final (icon, title, subtitle, route) in _actions)
          _QuickActionCard(
            icon: icon,
            title: title,
            subtitle: subtitle,
            route: route,
          ),
      ],
    );
  }
}

final class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => context.go(route),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Icon(icon, size: AppSpacing.xxxl, color: AppColors.primary),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 20,
            color: context.appColors.textDisabled,
          ),
        ],
      ),
    );
  }
}

final class _BusinessBreakdownCard extends StatelessWidget {
  const _BusinessBreakdownCard({required this.breakdown});

  final List<BusinessSalesSummary> breakdown;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Business Breakdown',
      subtitle: 'Per-business sales for the selected day · read-only',
      child: Column(
        children: [
          for (var i = 0; i < breakdown.length; i++) ...[
            if (i > 0)
              Divider(
                height: 12,
                thickness: 1,
                color: context.appColors.divider,
              ),
            _BusinessRow(entry: breakdown[i]),
          ],
        ],
      ),
    );
  }
}

final class _BusinessRow extends StatelessWidget {
  const _BusinessRow({required this.entry});

  final BusinessSalesSummary entry;

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
                  entry.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.orderCount} ${entry.orderCount == 1 ? 'order' : 'orders'} · ${entry.itemCount} ${entry.itemCount == 1 ? 'item' : 'items'}',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Text(
            Money.formatPaise(entry.salesPaise),
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

final class _GlanceSection extends StatelessWidget {
  const _GlanceSection({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final hasSales = snapshot.dayOrderCount > 0;
    final average = hasSales
        ? Money.formatPaise(snapshot.daySalesPaise ~/ snapshot.dayOrderCount)
        : '—';
    final items = [
      ('Products', '${snapshot.productCount}'),
      ('Categories', '${snapshot.categoryCount}'),
      ('Total Bills', '${snapshot.totalBills}'),
      ('Avg. Sale Today', average),
    ];
    return SectionCard(
      title: 'Business at a Glance',
      subtitle: 'Store-wide numbers pulled from your records',
      child: GridView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 220,
          mainAxisExtent: 56,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
        ),
        children: [
          for (final (label, value) in items)
            _GlanceTile(label: label, value: value),
        ],
      ),
    );
  }
}

final class _GlanceTile extends StatelessWidget {
  const _GlanceTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

final class _SyncStatusCard extends ConsumerWidget {
  const _SyncStatusCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final textTheme = Theme.of(context).textTheme;

    // Syncing takes visual precedence over the underlying level.
    final effectiveLevel = status.isSyncing
        ? SyncStatusLevel.syncing
        : status.level;

    final (icon, color, title, detail) = switch (effectiveLevel) {
      SyncStatusLevel.syncing => (
        Icons.sync_outlined,
        AppColors.info,
        'Syncing…',
        'Pushing local changes and pulling cloud updates',
      ),
      SyncStatusLevel.error => (
        Icons.cloud_off_outlined,
        AppColors.error,
        'Sync failed',
        status.lastError ?? 'Tap to retry sync',
      ),
      SyncStatusLevel.synced => (
        Icons.cloud_done_outlined,
        AppColors.success,
        status.lastSyncAt != null ? 'Synced just now' : 'All synced',
        status.lastSyncAt != null
            ? 'All data is backed up to the cloud'
            : 'All data is backed up to the cloud',
      ),
      SyncStatusLevel.pending => (
        Icons.cloud_upload_outlined,
        AppColors.warning,
        '${status.pendingCount} pending',
        status.lastError != null
            ? 'Sync failed · Tap to retry'
            : 'Waiting to sync ${status.pendingCount} change(s) — pull to refresh or tap to sync now',
      ),
      SyncStatusLevel.offline => (
        Icons.cloud_off_outlined,
        AppColors.warning,
        'Offline',
        'Offline · Changes saved locally — will sync when back online',
      ),
      SyncStatusLevel.unconfirmed => (
        Icons.cloud_sync_outlined,
        AppColors.info,
        'Connecting…',
        'Establishing cloud connection',
      ),
      SyncStatusLevel.idle => (
        Icons.cloud_queue_outlined,
        AppColors.textSecondary,
        'Not signed in',
        'Sign in to enable cloud sync',
      ),
    };

    final canSync = status.level != SyncStatusLevel.idle && !status.isSyncing;

    return AppCard(
      onTap: canSync
          ? () => ref.read(syncStatusProvider.notifier).syncNow()
          : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          if (status.isSyncing)
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            )
          else
            Icon(icon, size: 22, color: color),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          if (status.isSyncing)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (!status.isSyncing && canSync)
            Icon(Icons.refresh_outlined, size: 20, color: color),
          if (!status.isSyncing && status.failedCount > 0) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${status.failedCount} failed',
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
