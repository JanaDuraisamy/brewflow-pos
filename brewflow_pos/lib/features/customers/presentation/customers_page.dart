import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customers Landing Page
///
/// Local-first customer profiles: search by name/phone/email, filter by
/// status, and a responsive list (data table on wide screens, cards on narrow
/// ones). Purchase history and due tracking arrive in future phases; this
/// page manages profile data only.
/// ---------------------------------------------------------------------------

final class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customers = ref.watch(customersProvider);
    final filter = ref.watch(customersFilterProvider);
    final hasFilters =
        filter.query.isNotEmpty ||
        filter.status != CustomerStatusFilter.all ||
        filter.dueOnly;

    return RefreshIndicator(
      onRefresh: () async {
        final syncFuture = ref.read(syncStatusProvider.notifier).syncNow();
        // ignore: unused_result
        await ref.refresh(customersProvider.future);
        await syncFuture;
      },
      child: Padding(
        padding: AppInsets.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 600;
                final header = const PageHeader(
                  title: 'Customers',
                  subtitle: 'Maintain customer profiles for your shop.',
                );
                final actions = const _HeaderActions();
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header,
                      const SizedBox(height: AppSpacing.md),
                      actions,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: header),
                    const SizedBox(width: AppSpacing.md),
                    actions,
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.md),
            const _FilterBar(),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: customers.when(
                skipLoadingOnRefresh: true,
                loading: () =>
                    const LoadingState(message: 'Loading customers…'),
                error: (error, stackTrace) => ErrorState(
                  message: customersErrorMessage(error),
                  onRetry: () => ref.invalidate(customersProvider),
                ),
                data: (items) {
                  final countText = hasFilters
                      ? '${items.length} ${items.length == 1 ? 'result' : 'results'}'
                      : '${items.length} ${items.length == 1 ? 'customer' : 'customers'}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        countText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Expanded(
                        child: items.isEmpty
                            ? EmptyState(
                                icon: Icons.people_outline,
                                title: hasFilters
                                    ? 'No customers match your filters'
                                    : 'No customers yet',
                                message: hasFilters
                                    ? 'Try a different search or clear the filters.'
                                    : 'Add your first customer to start building profiles.',
                                action: hasFilters
                                    ? SecondaryButton(
                                        label: 'Clear Filters',
                                        icon: Icons.filter_alt_off_outlined,
                                        onPressed: () => ref
                                            .read(
                                              customersFilterProvider.notifier,
                                            )
                                            .clear(),
                                      )
                                    : PrimaryButton(
                                        label: 'Add Customer',
                                        icon: Icons.add,
                                        onPressed: () =>
                                            context.push(AppRoutes.customerNew),
                                      ),
                              )
                            : _CustomerList(
                                customers: items,
                                filtered: hasFilters,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _HeaderActions extends StatelessWidget {
  const _HeaderActions();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 600;
        final button = PrimaryButton(
          label: 'Add Customer',
          icon: Icons.add,
          expanded: narrow,
          onPressed: () => context.push(AppRoutes.customerNew),
        );
        if (narrow) {
          return SizedBox(width: double.infinity, child: button);
        }
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.end,
          children: [button],
        );
      },
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
    text: ref.read(customersFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(customersFilterProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final search = SizedBox(
          width: compact ? double.infinity : 320,
          child: SearchField(
            controller: _search,
            hintText: 'Search by name, phone or email',
            onChanged: (value) =>
                ref.read(customersFilterProvider.notifier).setQuery(value),
          ),
        );
        final chips = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFilterChip(
              label: 'All',
              selected: filter.status == CustomerStatusFilter.all,
              onSelected: (selected) {
                if (selected) {
                  ref
                      .read(customersFilterProvider.notifier)
                      .setStatus(CustomerStatusFilter.all);
                }
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Active',
              selected: filter.status == CustomerStatusFilter.active,
              onSelected: (selected) => ref
                  .read(customersFilterProvider.notifier)
                  .setStatus(
                    selected
                        ? CustomerStatusFilter.active
                        : CustomerStatusFilter.all,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Inactive',
              selected: filter.status == CustomerStatusFilter.inactive,
              onSelected: (selected) => ref
                  .read(customersFilterProvider.notifier)
                  .setStatus(
                    selected
                        ? CustomerStatusFilter.inactive
                        : CustomerStatusFilter.all,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'With Due',
              selected: filter.dueOnly,
              onSelected: (selected) => ref
                  .read(customersFilterProvider.notifier)
                  .setDueOnly(selected),
            ),
          ],
        );
        if (compact) {
          final notifier = ref.read(customersFilterProvider.notifier);
          final activeCount =
              (filter.status != CustomerStatusFilter.all ? 1 : 0) +
              (filter.dueOnly ? 1 : 0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),
              FilterSheetButton(
                activeCount: activeCount,
                onPressed: () => showFilterSheet(
                  context,
                  title: 'Filter Customers',
                  onReset: notifier.clear,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [for (final chip in chips.children) chip],
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            search,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: chips,
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _CustomerList extends ConsumerWidget {
  const _CustomerList({required this.customers, required this.filtered});

  final List<Customer> customers;

  /// True when the current filter hides the full list.
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) {
      return ListView.builder(
        itemCount: customers.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _MobileCustomerCard(customer: customers[index]),
        ),
      );
    }
    if (width >= 800) {
      return SingleChildScrollView(child: _CustomerTable(customers: customers));
    }
    return ListView.builder(
      itemCount: customers.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _CustomerCard(customer: customers[index]),
      ),
    );
  }
}

final class _CustomerTable extends StatelessWidget {
  const _CustomerTable({required this.customers});

  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DataTable(
      columns: const [
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Phone')),
        DataColumn(label: Text('Email')),
        DataColumn(label: Text('Status')),
      ],
      rows: [
        for (final customer in customers)
          DataRow(
            onSelectChanged: (_) =>
                context.push(AppRoutes.customerDetail, extra: customer),
            cells: [
              DataCell(
                Text(
                  customer.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  customer.phone ?? '—',
                  style: textTheme.bodyMedium?.copyWith(
                    color: customer.phone == null
                        ? context.appColors.textDisabled
                        : context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  customer.email ?? '—',
                  style: textTheme.bodyMedium?.copyWith(
                    color: customer.email == null
                        ? context.appColors.textDisabled
                        : context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(_StatusBadge(isActive: customer.isActive)),
            ],
          ),
      ],
    );
  }
}

final class _MobileCustomerCard extends ConsumerWidget {
  const _MobileCustomerCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    // Outstanding comes from the authoritative ledger aggregation; the card
    // only renders it, matching the detail page's source of truth.
    final ledger = ref.watch(customerLedgerProvider(customer.id));
    final outstanding = ledger.value?.summary.outstandingPaise;
    final hasDue = (outstanding ?? 0) > 0;
    final dueText = outstanding == null
        ? '—'
        : outstanding > 0
        ? 'Due ${Money.formatPaise(outstanding)}'
        : 'No dues';
    return AppCard(
      padding: AppInsets.card,
      onTap: () => context.push(AppRoutes.customerDetail, extra: customer),
      onLongPress: () => _showCustomerActions(context, ref, customer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AppAvatar(name: customer.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      customer.phone ?? 'No phone',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodyMedium?.copyWith(
                        color: customer.phone == null
                            ? context.appColors.textDisabled
                            : context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _StatusBadge(isActive: customer.isActive),
              const SizedBox(width: AppSpacing.xs),
              IconButton(
                tooltip: 'Edit customer',
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: context.appColors.textSecondary,
                padding: AppInsets.zero,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                onPressed: () =>
                    context.push(AppRoutes.customerEdit, extra: customer),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                hasDue
                    ? Icons.account_balance_wallet_outlined
                    : Icons.check_circle_outline,
                size: 16,
                color: hasDue
                    ? AppColors.error
                    : context.appColors.textDisabled,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                dueText,
                style: textTheme.bodySmall?.copyWith(
                  color: hasDue
                      ? AppColors.error
                      : context.appColors.textSecondary,
                  fontWeight: hasDue ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

final class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      padding: AppInsets.card,
      onTap: () => context.push(AppRoutes.customerDetail, extra: customer),
      onLongPress: () => _showCustomerActions(context, ref, customer),
      child: Row(
        children: [
          AppAvatar(name: customer.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    customer.phone ?? 'No phone',
                    customer.email ?? 'No email',
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(isActive: customer.isActive),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Edit customer',
            icon: const Icon(Icons.edit_outlined),
            color: context.appColors.textSecondary,
            onPressed: () =>
                context.push(AppRoutes.customerEdit, extra: customer),
          ),
        ],
      ),
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : context.appColors.textDisabled;
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
            isActive ? 'Active' : 'Inactive',
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

/// Long-press context menu for a customer card.
void _showCustomerActions(
  BuildContext context,
  WidgetRef ref,
  Customer customer,
) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: customer.name,
    items: [
      ContextMenuItem(
        icon: Icons.visibility_outlined,
        label: 'View',
        onTap: () => context.push(AppRoutes.customerDetail, extra: customer),
      ),
      ContextMenuItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () => context.push(AppRoutes.customerEdit, extra: customer),
      ),
      ContextMenuItem(
        icon: customer.isActive
            ? Icons.block_outlined
            : Icons.check_circle_outline,
        label: customer.isActive ? 'Deactivate' : 'Activate',
        destructive: customer.isActive,
        onTap: () => _toggleCustomerActive(context, ref, customer),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _deleteCustomer(context, ref, customer),
        ),
    ],
  );
}

Future<void> _toggleCustomerActive(
  BuildContext context,
  WidgetRef ref,
  Customer customer,
) async {
  final deactivating = customer.isActive;
  if (deactivating) {
    final confirmed = await confirmDestructive(
      context,
      title: 'Deactivate customer',
      subject: customer.name,
      consequence:
          'Deactivated customers are hidden from new selections until '
          'reactivated. Their ledger history is kept.',
      confirmLabel: 'Deactivate',
    );
    if (!confirmed) return;
  }
  await ref
      .read(customersProvider.notifier)
      .setActive(customer.id, !customer.isActive);
}

Future<void> _deleteCustomer(
  BuildContext context,
  WidgetRef ref,
  Customer customer,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Delete customer',
    subject: customer.name,
    consequence:
        'If this customer has sales or payment history they will be '
        'deactivated instead. Otherwise they will be permanently deleted — '
        'on this device and others. This cannot be undone.',
  );
  if (!confirmed) return;
  try {
    final result = await ref
        .read(customersProvider.notifier)
        .delete(customer.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == CustomerDeleteResult.deactivated
              ? 'Customer has ledger history — deactivated instead.'
              : 'Customer deleted.',
        ),
      ),
    );
  } on CustomersFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
