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
import 'package:brewflow_pos/features/expenses/data/quick_expense_store.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_repository.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expenses Landing Page
///
/// Local-first expense records: search by name/note, filter by status,
/// category, payment method and date range, and a responsive list (data
/// table on wide screens, cards on narrow ones). Rows open the edit form;
/// deactivating an expense is the only removal path (no hard delete). A
/// Shop Payable summary above the filters shows the outstanding total of
/// NOT_PAID expenses; every expense also carries a Paid/Not paid badge.
/// ---------------------------------------------------------------------------

final class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider);
    final filter = ref.watch(expensesFilterProvider);
    final phone = MediaQuery.sizeOf(context).width < 600;

    return Padding(
      padding: AppInsets.screen,
      child: phone
          ? _buildPhoneLayout(context, ref, expenses, filter)
          : _buildDesktopLayout(context, ref, expenses, filter),
    );
  }

  /// Phone (<600dp) layout: a clean, spacious, Apple-inspired vertical
  /// hierarchy inside a [SingleChildScrollView] so nothing can ever overflow
  /// vertically — header, prominent Add Expense action, payable summary,
  /// search + filters, result count, quick expenses, then the list / empty
  /// state.
  Widget _buildPhoneLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Expense>> expenses,
    ExpensesFilter filter,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Expenses',
            subtitle: 'Record and review business expenses.',
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Add Expense',
            icon: Icons.add,
            expanded: true,
            onPressed: () => context.push(AppRoutes.expenseNew),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _PayableSummary(),
          const SizedBox(height: AppSpacing.lg),
          const _FilterBar(),
          const SizedBox(height: AppSpacing.lg),
          ...expenses.when(
            skipLoadingOnRefresh: true,
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: LoadingState(message: 'Loading expenses…'),
                ),
              ),
            ],
            error: (error, stackTrace) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: ErrorState(
                  message: expensesErrorMessage(error),
                  onRetry: () => ref.invalidate(expensesProvider),
                ),
              ),
            ],
            data: (items) {
              final countText = filter.isActive
                  ? '${items.length} ${items.length == 1 ? 'result' : 'results'}'
                  : '${items.length} ${items.length == 1 ? 'expense' : 'expenses'}';
              return [
                Text(
                  countText,
                  style: textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const _QuickExpensesSection(),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xxxl),
                    child: EmptyState(
                      icon: Icons.payments_outlined,
                      title: filter.isActive
                          ? 'No expenses match your filters'
                          : 'No expenses yet',
                      message: filter.isActive
                          ? 'Try a different search or clear the filters.'
                          : 'Add your first expense to start tracking '
                                'spending.',
                      action: filter.isActive
                          ? SecondaryButton(
                              label: 'Clear Filters',
                              icon: Icons.filter_alt_off_outlined,
                              onPressed: () => ref
                                  .read(expensesFilterProvider.notifier)
                                  .clear(),
                            )
                          : PrimaryButton(
                              label: 'Add Expense',
                              icon: Icons.add,
                              onPressed: () =>
                                  context.push(AppRoutes.expenseNew),
                            ),
                    ),
                  )
                else
                  _ExpenseList(expenses: items, phone: true),
              ];
            },
          ),
        ],
      ),
    );
  }

  /// Tablet / desktop (>=600dp) layout — unchanged from the original.
  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Expense>> expenses,
    ExpensesFilter filter,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final header = const PageHeader(
              title: 'Expenses',
              subtitle: 'Record and review business expenses.',
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
        const _PayableSummary(),
        const SizedBox(height: AppSpacing.md),
        const _FilterBar(),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: expenses.when(
            skipLoadingOnRefresh: true,
            loading: () => const LoadingState(message: 'Loading expenses…'),
            error: (error, stackTrace) => ErrorState(
              message: expensesErrorMessage(error),
              onRetry: () => ref.invalidate(expensesProvider),
            ),
            data: (items) {
              final countText = filter.isActive
                  ? '${items.length} ${items.length == 1 ? 'result' : 'results'}'
                  : '${items.length} ${items.length == 1 ? 'expense' : 'expenses'}';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _QuickExpensesSection(),
                  const SizedBox(height: AppSpacing.md),
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
                            icon: Icons.payments_outlined,
                            title: filter.isActive
                                ? 'No expenses match your filters'
                                : 'No expenses yet',
                            message: filter.isActive
                                ? 'Try a different search or clear the filters.'
                                : 'Add your first expense to start tracking '
                                      'spending.',
                            action: filter.isActive
                                ? SecondaryButton(
                                    label: 'Clear Filters',
                                    icon: Icons.filter_alt_off_outlined,
                                    onPressed: () => ref
                                        .read(expensesFilterProvider.notifier)
                                        .clear(),
                                  )
                                : PrimaryButton(
                                    label: 'Add Expense',
                                    icon: Icons.add,
                                    onPressed: () =>
                                        context.push(AppRoutes.expenseNew),
                                  ),
                          )
                        : _ExpenseList(expenses: items),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

final class _HeaderActions extends StatelessWidget {
  const _HeaderActions();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      alignment: WrapAlignment.end,
      children: [
        PrimaryButton(
          label: 'Add Expense',
          icon: Icons.add,
          onPressed: () => context.push(AppRoutes.expenseNew),
        ),
      ],
    );
  }
}

/// Outstanding shop payable: the sum of active NOT_PAID expenses. Loading
/// shows a placeholder and failures degrade to '—' (details stay logged);
/// the list itself still renders normally.
final class _PayableSummary extends ConsumerWidget {
  const _PayableSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payable = ref.watch(shopPayableProvider);
    final amount = payable.value;
    final textTheme = Theme.of(context).textTheme;
    final highlighted = (amount ?? 0) > 0;
    return AppCard(
      padding: AppInsets.card,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              size: 20,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Shop Payable',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Expenses recorded but not paid yet.',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            amount == null
                ? (payable.hasError ? '—' : '…')
                : Money.formatPaise(amount),
            style: textTheme.titleMedium?.copyWith(
              color: highlighted
                  ? AppColors.warning
                  : context.appColors.textPrimary,
              fontWeight: FontWeight.w700,
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
    text: ref.read(expensesFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange(OrdersDatePreset preset) async {
    final controller = ref.read(expensesFilterProvider.notifier);
    final filter = ref.read(expensesFilterProvider);
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: filter.fromUtc != null && filter.toUtc != null
          ? DateTimeRange(
              start: filter.fromUtc!.toLocal(),
              end: filter.toUtc!.toLocal(),
            )
          : DateTimeRange(start: now, end: now),
    );
    if (range == null) return;
    controller.setCustomRange(range.start, range.end);
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(expensesFilterProvider);
    final search = SizedBox(
      width: MediaQuery.sizeOf(context).width < 600 ? double.infinity : 320,
      child: SearchField(
        controller: _search,
        hintText: 'Search by name or note',
        onChanged: (value) =>
            ref.read(expensesFilterProvider.notifier).setQuery(value),
      ),
    );
    final statusChips = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppFilterChip(
          label: 'All',
          selected: filter.status == ExpenseStatusFilter.all,
          onSelected: (selected) {
            if (selected) {
              ref
                  .read(expensesFilterProvider.notifier)
                  .setStatus(ExpenseStatusFilter.all);
            }
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        AppFilterChip(
          label: 'Active',
          selected: filter.status == ExpenseStatusFilter.active,
          onSelected: (selected) => ref
              .read(expensesFilterProvider.notifier)
              .setStatus(
                selected ? ExpenseStatusFilter.active : ExpenseStatusFilter.all,
              ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppFilterChip(
          label: 'Inactive',
          selected: filter.status == ExpenseStatusFilter.inactive,
          onSelected: (selected) => ref
              .read(expensesFilterProvider.notifier)
              .setStatus(
                selected
                    ? ExpenseStatusFilter.inactive
                    : ExpenseStatusFilter.all,
              ),
        ),
      ],
    );
    final compact = MediaQuery.sizeOf(context).width < 600;
    final dropdownRow = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _CategoryDropdown(selected: filter.category),
          const SizedBox(width: AppSpacing.md),
          _PaymentDropdown(selected: filter.paymentMethod),
          const SizedBox(width: AppSpacing.md),
          _DateDropdown(
            preset: filter.datePreset,
            onChanged: (preset) {
              if (preset == OrdersDatePreset.custom) {
                _pickCustomRange(preset);
                return;
              }
              ref.read(expensesFilterProvider.notifier).setPreset(preset);
            },
          ),
        ],
      ),
    );
    if (compact) {
      final notifier = ref.read(expensesFilterProvider.notifier);
      final activeCount =
          (filter.status != ExpenseStatusFilter.all ? 1 : 0) +
          (filter.category != null ? 1 : 0) +
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
              title: 'Filter Expenses',
              onReset: notifier.clear,
              children: [
                _filterSectionLabel(context, 'Status'),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [for (final chip in statusChips.children) chip],
                ),
                const SizedBox(height: AppSpacing.md),
                _filterSectionLabel(context, 'Category'),
                _CategoryDropdown(selected: filter.category),
                const SizedBox(height: AppSpacing.md),
                _filterSectionLabel(context, 'Payment'),
                _PaymentDropdown(selected: filter.paymentMethod),
                const SizedBox(height: AppSpacing.md),
                _filterSectionLabel(context, 'Date'),
                _DateDropdown(
                  preset: filter.datePreset,
                  onChanged: (preset) {
                    if (preset == OrdersDatePreset.custom) {
                      _pickCustomRange(preset);
                      return;
                    }
                    ref.read(expensesFilterProvider.notifier).setPreset(preset);
                  },
                ),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            search,
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: statusChips,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        dropdownRow,
      ],
    );
  }
}

final class _CategoryDropdown extends ConsumerWidget {
  const _CategoryDropdown({required this.selected});

  final ExpenseCategory? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButton<ExpenseCategory>(
      value: selected,
      hint: const Text('All categories'),
      items: [
        for (final category in ExpenseCategory.values)
          DropdownMenuItem(value: category, child: Text(category.label)),
      ],
      onChanged: (value) =>
          ref.read(expensesFilterProvider.notifier).setCategory(value),
    );
  }
}

final class _PaymentDropdown extends ConsumerWidget {
  const _PaymentDropdown({required this.selected});

  final PaymentMethod? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButton<PaymentMethod>(
      value: selected,
      hint: const Text('All payments'),
      items: [
        for (final method in PaymentMethod.values)
          DropdownMenuItem(
            value: method,
            child: Text(paymentMethodLabel(method)),
          ),
      ],
      onChanged: (value) =>
          ref.read(expensesFilterProvider.notifier).setPaymentMethod(value),
    );
  }
}

final class _DateDropdown extends StatelessWidget {
  const _DateDropdown({required this.preset, required this.onChanged});

  final OrdersDatePreset preset;
  final ValueChanged<OrdersDatePreset> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<OrdersDatePreset>(
      value: preset,
      items: [
        for (final preset in OrdersDatePreset.values)
          DropdownMenuItem(
            value: preset,
            child: Text(switch (preset) {
              OrdersDatePreset.all => 'All dates',
              OrdersDatePreset.today => 'Today',
              OrdersDatePreset.last7 => 'Last 7 days',
              OrdersDatePreset.last30 => 'Last 30 days',
              OrdersDatePreset.last90 => 'Last 90 days',
              OrdersDatePreset.custom => 'Custom range',
            }),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

final class _ExpenseList extends ConsumerWidget {
  const _ExpenseList({required this.expenses, this.phone = false});

  final List<Expense> expenses;

  /// Renders the phone-only, non-virtualized card list so the parent
  /// [SingleChildScrollView] owns scrolling (no nested-ListView bounds).
  final bool phone;

  Future<void> _confirmDeactivate(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate expense?'),
        content: Text(
          '${expense.name} will be hidden from active lists. '
          'You can reactivate it later from its edit form.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(expensesProvider.notifier).setActive(expense.id, false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Expense deactivated.')),
      );
    } on ExpensesFailure {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not deactivate the expense.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (phone) {
      return ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: expenses.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _PhoneExpenseCard(
            expense: expenses[index],
            onDeactivate: (expense) =>
                _confirmDeactivate(context, ref, expense),
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: _ExpenseTable(
            expenses: expenses,
            onDeactivate: (expense) =>
                _confirmDeactivate(context, ref, expense),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: expenses.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _ExpenseCard(
          expense: expenses[index],
          onDeactivate: (expense) => _confirmDeactivate(context, ref, expense),
        ),
      ),
    );
  }
}

final class _ExpenseTable extends StatelessWidget {
  const _ExpenseTable({required this.expenses, required this.onDeactivate});

  final List<Expense> expenses;
  final ValueChanged<Expense> onDeactivate;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DataTable(
      columns: const [
        DataColumn(label: Text('Expense')),
        DataColumn(label: Text('Amount')),
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('Payment')),
        DataColumn(label: Text('Date')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final expense in expenses)
          DataRow(
            onSelectChanged: (_) =>
                context.push(AppRoutes.expenseEdit, extra: expense),
            cells: [
              DataCell(
                Text(
                  expense.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  Money.formatPaise(expense.amountPaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  expense.category.label,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  paymentMethodLabel(expense.paymentMethod),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  formatDate(expense.expenseDate),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
              DataCell(
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(isActive: expense.isActive),
                    _PaymentBadge(status: expense.paymentStatus),
                  ],
                ),
              ),
              DataCell(
                IconButton(
                  tooltip: 'Deactivate expense',
                  icon: const Icon(Icons.delete_outline),
                  color: context.appColors.textSecondary,
                  onPressed: () => onDeactivate(expense),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final class _ExpenseCard extends ConsumerWidget {
  const _ExpenseCard({required this.expense, required this.onDeactivate});

  final Expense expense;
  final ValueChanged<Expense> onDeactivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      padding: AppInsets.card,
      onTap: () => context.push(AppRoutes.expenseEdit, extra: expense),
      onLongPress: () => _showExpenseActions(context, ref, expense),
      child: Row(
        children: [
          AppAvatar(name: expense.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.name,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  Money.formatPaise(expense.amountPaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${expense.category.label} · '
                  '${paymentMethodLabel(expense.paymentMethod)} · '
                  '${formatDate(expense.expenseDate)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusBadge(isActive: expense.isActive),
              _PaymentBadge(status: expense.paymentStatus),
            ],
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            tooltip: 'Deactivate expense',
            icon: const Icon(Icons.delete_outline),
            color: context.appColors.textSecondary,
            onPressed: () => onDeactivate(expense),
          ),
        ],
      ),
    );
  }
}

/// Phone-only expense card: vertical hierarchy that never overflows on narrow
/// widths — avatar + name/amount + deactivate on one row, then the combined
/// details line and the status badges stacked below (wrapping as needed).
final class _PhoneExpenseCard extends ConsumerWidget {
  const _PhoneExpenseCard({required this.expense, required this.onDeactivate});

  final Expense expense;
  final ValueChanged<Expense> onDeactivate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return AppCard(
      padding: AppInsets.card,
      onTap: () => context.push(AppRoutes.expenseEdit, extra: expense),
      onLongPress: () => _showExpenseActions(context, ref, expense),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: expense.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      Money.formatPaise(expense.amountPaise),
                      style: textTheme.titleSmall?.copyWith(
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Deactivate expense',
                icon: const Icon(Icons.delete_outline),
                color: appColors.textSecondary,
                onPressed: () => onDeactivate(expense),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '${expense.category.label} · '
            '${paymentMethodLabel(expense.paymentMethod)} · '
            '${formatDate(expense.expenseDate)}',
            style: textTheme.bodySmall?.copyWith(
              color: appColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatusBadge(isActive: expense.isActive),
              _PaymentBadge(status: expense.paymentStatus),
            ],
          ),
        ],
      ),
    );
  }
}

final class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.status});

  final ExpensePaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final paid = status == ExpensePaymentStatus.paid;
    final color = paid ? AppColors.success : AppColors.warning;
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
            paid ? 'Paid' : 'Not paid',
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

/// ---------------------------------------------------------------------------
/// Quick Expenses section (P0 FIX 8)
///
/// Pinned daily-purchase templates as tappable chips. Tap = pre-filled sheet
/// (amount editable, PAID/NOT PAID, CASH/UPI) that records a NORMAL expense
/// for today through the existing controller/repository. Long-press unpins.
/// ---------------------------------------------------------------------------
final class _QuickExpensesSection extends ConsumerWidget {
  const _QuickExpensesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(quickExpensesProvider);
    final textTheme = Theme.of(context).textTheme;
    final items = templates.value ?? const <QuickExpenseTemplate>[];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.bolt, size: 18, color: AppColors.primary),
        SizedBox(width: AppSpacing.xs),
        Text(
          'Quick Expenses',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: items.isEmpty
              ? Text(
                  'Pin daily purchases for one-tap entry',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final template in items)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: InkWell(
                            borderRadius: AppBorderRadius.pill,
                            onTap: () => _openQuickEntry(context, template),
                            onLongPress: () {
                              ref
                                  .read(quickExpensesProvider.notifier)
                                  .unpin(template);
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(
                                  SnackBar(
                                    content: Text('Unpinned ${template.name}'),
                                  ),
                                );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                                vertical: AppSpacing.xs,
                              ),
                              decoration: BoxDecoration(
                                color: context.appColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.pill,
                                ),
                                border: Border.all(
                                  color: context.appColors.divider,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    template.name,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: context.appColors.textPrimary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (template.defaultAmountPaise != null) ...[
                                    SizedBox(width: AppSpacing.xs),
                                    Text(
                                      Money.formatPaise(
                                        template.defaultAmountPaise!,
                                      ),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: context.appColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        SizedBox(width: AppSpacing.sm),
        InkWell(
          borderRadius: AppBorderRadius.pill,
          onTap: () => _pinNew(context),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Icon(
              Icons.push_pin_outlined,
              size: 16,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openQuickEntry(
    BuildContext context,
    QuickExpenseTemplate template,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _QuickExpenseSheet(template: template),
    );
  }

  Future<void> _pinNew(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _QuickPinSheet(),
    );
  }
}

/// One-tap daily entry for a pinned template. Records a real expense via the
/// shared [ExpensesController.create] path — same validation, same ledger.
final class _QuickExpenseSheet extends ConsumerStatefulWidget {
  const _QuickExpenseSheet({required this.template});

  final QuickExpenseTemplate template;

  @override
  ConsumerState<_QuickExpenseSheet> createState() => _QuickExpenseSheetState();
}

final class _QuickExpenseSheetState extends ConsumerState<_QuickExpenseSheet> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.template.defaultAmountPaise == null
        ? ''
        : (widget.template.defaultAmountPaise! / 100).toStringAsFixed(0),
  );
  ExpensePaymentStatus _status = ExpensePaymentStatus.paid;
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? _parsedPaise() {
    final text = _amount.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    if (value == null || value < 0) return null;
    return Money.parseRupeesToPaise(text);
  }

  Future<void> _save() async {
    final paise = _parsedPaise();
    if (paise == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(expensesProvider.notifier)
          .create(
            name: widget.template.name,
            amountPaise: paise,
            category: widget.template.category,
            paymentMethod: _method,
            expenseDate: DateTime.now().toUtc(),
            paymentStatus: _status,
          );
      // Remember the last amount for tomorrow's one-tap entry.
      await ref
          .read(quickExpensesProvider.notifier)
          .pin(
            QuickExpenseTemplate(
              name: widget.template.name,
              category: widget.template.category,
              defaultAmountPaise: paise,
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              '${widget.template.name} saved · ${Money.formatPaise(paise)}'
              '${_status == ExpensePaymentStatus.notPaid ? ' · Not paid' : ''}',
            ),
          ),
        );
    } on ExpensesFailure catch (error) {
      if (mounted) setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } on Exception {
      if (mounted) setState(() => _saving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Something went wrong. Please try again.'),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppInsets.screen.left,
          AppSpacing.md,
          AppInsets.screen.right,
          AppInsets.screen.bottom + AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.template.name,
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppSpacing.xs),
            Text(
              widget.template.category.label,
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
              ),
            ),
            SizedBox(height: AppSpacing.md),
            SegmentedButton<ExpensePaymentStatus>(
              segments: const [
                ButtonSegment(
                  value: ExpensePaymentStatus.paid,
                  label: Text('PAID'),
                ),
                ButtonSegment(
                  value: ExpensePaymentStatus.notPaid,
                  label: Text('NOT PAID'),
                ),
              ],
              selected: {_status},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _status = selection.first),
            ),
            if (_status == ExpensePaymentStatus.paid) ...[
              SizedBox(height: AppSpacing.sm),
              SegmentedButton<PaymentMethod>(
                segments: const [
                  ButtonSegment(value: PaymentMethod.cash, label: Text('CASH')),
                  ButtonSegment(value: PaymentMethod.upi, label: Text('UPI')),
                ],
                selected: {_method},
                showSelectedIcon: false,
                onSelectionChanged: (selection) =>
                    setState(() => _method = selection.first),
              ),
            ],
            SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.primary,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pin-a-new-template sheet: name + category (+ optional default amount).
final class _QuickPinSheet extends ConsumerStatefulWidget {
  const _QuickPinSheet();

  @override
  ConsumerState<_QuickPinSheet> createState() => _QuickPinSheetState();
}

final class _QuickPinSheetState extends ConsumerState<_QuickPinSheet> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  ExpenseCategory _category = ExpenseCategory.supplies;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _pin() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    final amountText = _amount.text.trim();
    final paise = amountText.isEmpty
        ? null
        : Money.parseRupeesToPaise(amountText);
    ref
        .read(quickExpensesProvider.notifier)
        .pin(
          QuickExpenseTemplate(
            name: name,
            category: _category,
            defaultAmountPaise: paise,
          ),
        );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppInsets.screen.left,
          AppSpacing.md,
          AppInsets.screen.right,
          AppInsets.screen.bottom + AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pin quick expense',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Name (e.g. Milk)'),
            ),
            SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final category in ExpenseCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(category.label),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            SizedBox(height: AppSpacing.md),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Default amount (optional)',
                prefixText: '₹ ',
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _pin,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Pin'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Long-press context menu for an expense card.
void _showExpenseActions(BuildContext context, WidgetRef ref, Expense expense) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: expense.name,
    items: [
      ContextMenuItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () => context.push(AppRoutes.expenseEdit, extra: expense),
      ),
      ContextMenuItem(
        icon: expense.isActive
            ? Icons.block_outlined
            : Icons.check_circle_outline,
        label: expense.isActive ? 'Deactivate' : 'Activate',
        destructive: expense.isActive,
        onTap: () => _toggleExpenseActive(context, ref, expense),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _deleteExpense(context, ref, expense),
        ),
    ],
  );
}

Future<void> _toggleExpenseActive(
  BuildContext context,
  WidgetRef ref,
  Expense expense,
) async {
  final deactivating = expense.isActive;
  if (deactivating) {
    final confirmed = await confirmDestructive(
      context,
      title: 'Deactivate expense',
      subject: expense.name,
      consequence:
          'Deactivated expenses are hidden from reports until reactivated. '
          'The record itself is kept.',
      confirmLabel: 'Deactivate',
    );
    if (!confirmed) return;
  }
  await ref
      .read(expensesProvider.notifier)
      .setActive(expense.id, !expense.isActive);
}

Future<void> _deleteExpense(
  BuildContext context,
  WidgetRef ref,
  Expense expense,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Delete expense',
    subject: expense.name,
    consequence:
        'This permanently removes the expense record and its sync tombstone. '
        'Other devices will stop showing it too. This cannot be undone.',
  );
  if (!confirmed) return;
  try {
    await ref.read(expensesProvider.notifier).delete(expense.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Expense deleted.')));
  } on ExpensesFailure catch (error) {
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
