import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Orders Landing Page
///
/// Historical completed-sales list built from the persisted Billing records.
/// Search works on receipt numbers and product names; payment-method and
/// date-range filters narrow the list; wide screens get a table, narrow ones
/// cards — both driven by the same feed.
/// ---------------------------------------------------------------------------

final class OrdersPage extends ConsumerWidget {
  const OrdersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(ordersListProvider);
    final filter = ref.watch(ordersFilterProvider);

    return Padding(
      padding: AppInsets.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(
            title: 'Orders',
            subtitle: 'Review completed sales and receipts.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FilterBar(),
          SizedBox(height: AppSpacing.md),
          Expanded(
            child: feed.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(
                message: ordersErrorMessage(error),
                onRetry: () => ref.invalidate(ordersListProvider),
              ),
              data: (data) => data.items.isEmpty
                  ? _EmptyState(
                      filtered: filter.isActive,
                      onClearFilters: filter.isActive
                          ? () =>
                                ref.read(ordersFilterProvider.notifier).clear()
                          : null,
                    )
                  : _OrderList(
                      feed: data,
                      onLoadMore: () async {
                        try {
                          await ref
                              .read(ordersListProvider.notifier)
                              .loadMore();
                        } on OrdersFailure catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(
                                SnackBar(content: Text(error.message)),
                              );
                          }
                        }
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar();

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

final class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(ordersFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange() async {
    final current = ref.read(ordersFilterProvider);
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: current.fromUtc == null
          ? null
          : DateTimeRange(
              start: current.fromUtc!.toLocal(),
              end: current.toUtc!.toLocal(),
            ),
      helpText: 'Select the sale date range',
      saveText: 'Apply',
    );
    if (range == null || !mounted) return;
    ref
        .read(ordersFilterProvider.notifier)
        .setCustomRange(range.start, range.end);
  }

  void _onDateSelected(OrdersDatePreset? preset) {
    if (preset == null) return;
    if (preset == OrdersDatePreset.custom) {
      _pickCustomRange();
      return;
    }
    ref.read(ordersFilterProvider.notifier).setPreset(preset);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(ordersFilterProvider);
    // Keep the field in sync when the filter is reset elsewhere (e.g. the
    // "Clear Filters" actions), so it never shows a stale query.
    ref.listen(ordersFilterProvider, (previous, next) {
      if (_search.text != next.query) {
        _search.text = next.query;
      }
    });
    final compact = MediaQuery.sizeOf(context).width < 600;
    final search = SizedBox(
      width: compact ? double.infinity : 260,
      child: TextField(
        controller: _search,
        onChanged: (value) =>
            ref.read(ordersFilterProvider.notifier).setQuery(value),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search by receipt or product',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: AppBorderRadius.md,
            borderSide: BorderSide(color: context.appColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppBorderRadius.md,
            borderSide: BorderSide(color: context.appColors.divider),
          ),
        ),
      ),
    );
    final methodDropdown = DropdownButton<PaymentMethod?>(
      value: filter.paymentMethod,
      hint: const Text('All methods'),
      items: [
        const DropdownMenuItem<PaymentMethod?>(
          value: null,
          child: Text('All methods'),
        ),
        for (final method in PaymentMethod.values)
          DropdownMenuItem<PaymentMethod?>(
            value: method,
            child: Text(paymentMethodLabel(method)),
          ),
      ],
      onChanged: (method) =>
          ref.read(ordersFilterProvider.notifier).setPaymentMethod(method),
    );
    final dateDropdown = DropdownButton<OrdersDatePreset>(
      value: filter.datePreset,
      items: [
        const DropdownMenuItem(
          value: OrdersDatePreset.all,
          child: Text('All time'),
        ),
        const DropdownMenuItem(
          value: OrdersDatePreset.today,
          child: Text('Today'),
        ),
        const DropdownMenuItem(
          value: OrdersDatePreset.last7,
          child: Text('Last 7 days'),
        ),
        const DropdownMenuItem(
          value: OrdersDatePreset.last30,
          child: Text('Last 30 days'),
        ),
        DropdownMenuItem(
          value: OrdersDatePreset.last90,
          child: Text('Last 90 days'),
        ),
        if (filter.datePreset == OrdersDatePreset.custom)
          DropdownMenuItem(
            value: OrdersDatePreset.custom,
            child: Text('Custom range'),
          ),
      ],
      onChanged: _onDateSelected,
    );
    if (compact) {
      final notifier = ref.read(ordersFilterProvider.notifier);
      final activeCount =
          (filter.paymentMethod != null ? 1 : 0) +
          (filter.datePreset != OrdersDatePreset.all ? 1 : 0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          search,
          const SizedBox(height: AppSpacing.md),
          FilterSheetButton(
            activeCount: activeCount,
            onPressed: () => showFilterSheet(
              context,
              title: 'Filter Orders',
              onReset: notifier.clear,
              children: [
                _filterSectionLabel(context, 'Payment'),
                methodDropdown,
                const SizedBox(height: AppSpacing.md),
                _filterSectionLabel(context, 'Date'),
                dateDropdown,
              ],
            ),
          ),
        ],
      );
    }
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        search,
        methodDropdown,
        dateDropdown,
        if (filter.isActive)
          TextButton.icon(
            onPressed: () => ref.read(ordersFilterProvider.notifier).clear(),
            icon: const Icon(Icons.filter_alt_off_outlined),
            label: const Text('Clear Filters'),
          ),
      ],
    );
  }
}

final class _OrderList extends ConsumerWidget {
  const _OrderList({required this.feed, required this.onLoadMore});

  final OrdersFeed feed;
  final Future<void> Function() onLoadMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ResponsiveBuilder(
      builder: (context, breakpoint) {
        // Phones (<600dp) get clean order cards; tablets/desktops keep the
        // wide history table. Both render from the same feed.
        if (!breakpoint.isCompact) {
          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _OrderTable(orders: feed.items),
                ),
              ),
              if (feed.hasMore) ...[
                SizedBox(height: AppSpacing.md),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load More'),
                  ),
                ),
              ],
            ],
          );
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: feed.items.length + (feed.hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == feed.items.length) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Center(
                  child: OutlinedButton.icon(
                    onPressed: onLoadMore,
                    icon: const Icon(Icons.expand_more),
                    label: const Text('Load More'),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: _OrderCard(order: feed.items[index]),
            );
          },
        );
      },
    );
  }
}

final class _OrderTable extends StatelessWidget {
  const _OrderTable({required this.orders});

  final List<OrderSummary> orders;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DataTable(
      columns: const [
        DataColumn(label: Text('Receipt')),
        DataColumn(label: Text('Date & Time')),
        DataColumn(label: Text('Customer')),
        DataColumn(label: Text('Items')),
        DataColumn(label: Text('Total')),
        DataColumn(label: Text('Payment')),
      ],
      rows: [
        for (final order in orders)
          DataRow(
            onSelectChanged: (_) =>
                context.push(AppRoutes.orderDetail, extra: order),
            cells: [
              DataCell(
                Text(
                  order.receiptNumber,
                  style: textTheme.bodyMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                Text(
                  formatDateTime(order.createdAt),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  orderCustomerLabel(order.customerName),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  itemsLabel(order.itemCount),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  Money.formatPaise(order.totalPaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              DataCell(
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (order.isVoided) const _VoidedBadge(),
                    _PaymentBadge(
                      status: order.paymentStatus,
                      method: order.paymentMethod,
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});

  final OrderSummary order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return AppCard(
      onTap: () => context.push(AppRoutes.orderDetail, extra: order),
      onLongPress: () => _showOrderActions(context, ref, order),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.receiptNumber,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: AppSpacing.sm),
              if (order.isVoided) ...[
                const _VoidedBadge(),
                SizedBox(width: AppSpacing.xs),
              ],
              _PaymentBadge(
                status: order.paymentStatus,
                method: order.paymentMethod,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _MetaRow(
            icon: Icons.schedule,
            child: Text(
              formatDateTime(order.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: appColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetaRow(
            icon: Icons.person_outline,
            child: Text(
              orderCustomerLabel(order.customerName),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: appColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _MetaRow(
            icon: Icons.shopping_bag_outlined,
            child: Text(
              itemsLabel(order.itemCount),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                color: appColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Divider(
            height: AppSpacing.xxl + AppSpacing.sm,
            color: appColors.divider,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Total',
                style: textTheme.bodyMedium?.copyWith(
                  color: appColors.textSecondary,
                ),
              ),
              Text(
                Money.formatPaise(order.totalPaise),
                style: textTheme.titleMedium?.copyWith(
                  color: appColors.textPrimary,
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

/// One labelled meta line inside a phone order card (icon + inline text).
final class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.child});

  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.appColors.textSecondary),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: child),
      ],
    );
  }
}

final class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status, this.method});

  final PaymentStatus status;
  final PaymentMethod? method;

  @override
  Widget build(BuildContext context) {
    final notPaid = status == PaymentStatus.notPaid;
    final label = notPaid ? 'Not paid' : paymentMethodLabel(method!);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: (notPaid ? AppColors.warning : AppColors.primary).withValues(
          alpha: 0.12,
        ),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: notPaid ? AppColors.warning : AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

final class _VoidedBadge extends StatelessWidget {
  const _VoidedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block, size: AppSpacing.sm, color: AppColors.error),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Voided',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

final class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: AppSpacing.ultra,
                color: AppColors.error,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                'Could not load orders',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, this.onClearFilters});

  final bool filtered;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.receipt_long_outlined,
                size: AppSpacing.ultra,
                color: AppColors.primary,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                filtered ? 'No orders match your filters' : 'No orders yet',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                filtered
                    ? 'Try a different search or clear the filters.'
                    : 'Completed sales from the counter will appear here.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (filtered)
                OutlinedButton.icon(
                  onPressed: onClearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: const Text('Clear Filters'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Long-press context menu for an order card.
void _showOrderActions(
  BuildContext context,
  WidgetRef ref,
  OrderSummary order,
) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: order.receiptNumber,
    items: [
      ContextMenuItem(
        icon: Icons.receipt_long_outlined,
        label: 'View Details',
        onTap: () => context.push(AppRoutes.orderDetail, extra: order),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.undo_outlined,
          label: 'Void Sale',
          destructive: true,
          onTap: () => _voidSale(context, ref, order),
        ),
    ],
  );
}

Future<void> _voidSale(
  BuildContext context,
  WidgetRef ref,
  OrderSummary order,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Void sale',
    subject: order.receiptNumber,
    consequence:
        'Stock will be restored and any payments will be reversed. '
        'This cannot be undone.',
    confirmLabel: 'Void',
  );
  if (!confirmed) return;
  try {
    await ref.read(ordersListProvider.notifier).voidOrder(order.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sale voided.')));
  } on BillingFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}

Widget _filterSectionLabel(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: context.appColors.textSecondary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
