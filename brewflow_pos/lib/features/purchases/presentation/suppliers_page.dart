import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../features/staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Suppliers Landing Page
///
/// Local-first supplier profiles: search by name/phone/email, filter by
/// status, and a responsive list (data table on wide screens, cards on narrow
/// ones). Status is soft — deactivating a supplier never touches their
/// purchase history (the receiving transaction re-validates activity).
/// Purchase/receiving UI arrives in a later phase; this page manages profile
/// data only.
/// ---------------------------------------------------------------------------

final class SuppliersPage extends ConsumerWidget {
  const SuppliersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliers = ref.watch(suppliersProvider);
    final filter = ref.watch(suppliersFilterProvider);
    final hasFilters =
        filter.query.isNotEmpty || filter.status != SupplierStatusFilter.all;
    final phone = MediaQuery.sizeOf(context).width < 600;

    return Padding(
      padding: AppInsets.screen,
      child: phone
          ? _buildPhoneLayout(context, ref, suppliers, filter, hasFilters)
          : _buildDesktopLayout(context, ref, suppliers, filter, hasFilters),
    );
  }

  /// Phone (<600dp) layout: concise vertical hierarchy inside a
  /// [SingleChildScrollView] so it can never overflow vertically — header,
  /// prominent Add Supplier action, search + status chips, then the list /
  /// empty state.
  Widget _buildPhoneLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Supplier>> suppliers,
    SuppliersFilter filter,
    bool hasFilters,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Suppliers',
            subtitle: 'Manage the suppliers you purchase stock from.',
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Add Supplier',
            icon: Icons.add,
            expanded: true,
            onPressed: () => context.push(AppRoutes.supplierNew),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _FilterBar(),
          const SizedBox(height: AppSpacing.lg),
          ...suppliers.when(
            skipLoadingOnRefresh: true,
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: LoadingState(message: 'Loading suppliers…'),
                ),
              ),
            ],
            error: (error, stackTrace) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: ErrorState(
                    message: suppliersErrorMessage(error),
                    onRetry: () => ref.invalidate(suppliersProvider),
                  ),
                ),
              ),
            ],
            data: (items) => items.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
                      child: EmptyState(
                        icon: Icons.local_shipping_outlined,
                        title: hasFilters
                            ? 'No suppliers match your filters'
                            : 'No suppliers yet',
                        message: hasFilters
                            ? 'Try a different search or clear the filters.'
                            : 'Add your first supplier to start building profiles.',
                        action: hasFilters
                            ? SecondaryButton(
                                label: 'Clear Filters',
                                icon: Icons.filter_alt_off_outlined,
                                onPressed: () => ref
                                    .read(suppliersFilterProvider.notifier)
                                    .clear(),
                              )
                            : PrimaryButton(
                                label: 'Add Supplier',
                                icon: Icons.add,
                                onPressed: () =>
                                    context.push(AppRoutes.supplierNew),
                              ),
                      ),
                    ),
                  ]
                : [_PhoneSupplierList(suppliers: items)],
          ),
        ],
      ),
    );
  }

  /// Tablet / desktop (>=600dp) layout — unchanged from the original.
  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<Supplier>> suppliers,
    SuppliersFilter filter,
    bool hasFilters,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final header = const PageHeader(
              title: 'Suppliers',
              subtitle: 'Manage the suppliers you purchase stock from.',
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
          child: suppliers.when(
            skipLoadingOnRefresh: true,
            loading: () => const LoadingState(message: 'Loading suppliers…'),
            error: (error, stackTrace) => ErrorState(
              message: suppliersErrorMessage(error),
              onRetry: () => ref.invalidate(suppliersProvider),
            ),
            data: (items) => items.isEmpty
                ? EmptyState(
                    icon: Icons.local_shipping_outlined,
                    title: hasFilters
                        ? 'No suppliers match your filters'
                        : 'No suppliers yet',
                    message: hasFilters
                        ? 'Try a different search or clear the filters.'
                        : 'Add your first supplier to start building profiles.',
                    action: hasFilters
                        ? SecondaryButton(
                            label: 'Clear Filters',
                            icon: Icons.filter_alt_off_outlined,
                            onPressed: () => ref
                                .read(suppliersFilterProvider.notifier)
                                .clear(),
                          )
                        : PrimaryButton(
                            label: 'Add Supplier',
                            icon: Icons.add,
                            onPressed: () =>
                                context.push(AppRoutes.supplierNew),
                          ),
                  )
                : _SupplierList(suppliers: items, filtered: hasFilters),
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
          label: 'Add Supplier',
          icon: Icons.add,
          onPressed: () => context.push(AppRoutes.supplierNew),
        ),
      ],
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
    text: ref.read(suppliersFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(suppliersFilterProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;
        final search = SizedBox(
          width: compact ? double.infinity : 320,
          child: SearchField(
            controller: _search,
            hintText: 'Search by name, phone or email',
            onChanged: (value) =>
                ref.read(suppliersFilterProvider.notifier).setQuery(value),
          ),
        );
        final chips = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppFilterChip(
              label: 'All',
              selected: filter.status == SupplierStatusFilter.all,
              onSelected: (selected) {
                if (selected) {
                  ref
                      .read(suppliersFilterProvider.notifier)
                      .setStatus(SupplierStatusFilter.all);
                }
              },
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Active',
              selected: filter.status == SupplierStatusFilter.active,
              onSelected: (selected) => ref
                  .read(suppliersFilterProvider.notifier)
                  .setStatus(
                    selected
                        ? SupplierStatusFilter.active
                        : SupplierStatusFilter.all,
                  ),
            ),
            const SizedBox(width: AppSpacing.sm),
            AppFilterChip(
              label: 'Inactive',
              selected: filter.status == SupplierStatusFilter.inactive,
              onSelected: (selected) => ref
                  .read(suppliersFilterProvider.notifier)
                  .setStatus(
                    selected
                        ? SupplierStatusFilter.inactive
                        : SupplierStatusFilter.all,
                  ),
            ),
          ],
        );
        if (compact) {
          final notifier = ref.read(suppliersFilterProvider.notifier);
          final activeCount = filter.status != SupplierStatusFilter.all ? 1 : 0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),
              FilterSheetButton(
                activeCount: activeCount,
                onPressed: () => showFilterSheet(
                  context,
                  title: 'Filter Suppliers',
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

final class _SupplierList extends ConsumerWidget {
  const _SupplierList({required this.suppliers, required this.filtered});

  final List<Supplier> suppliers;

  /// True when the current filter hides the full list.
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    if (wide) {
      return SingleChildScrollView(child: _SupplierTable(suppliers: suppliers));
    }
    return ListView.builder(
      itemCount: suppliers.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _SupplierCard(supplier: suppliers[index]),
      ),
    );
  }
}

final class _SupplierTable extends StatelessWidget {
  const _SupplierTable({required this.suppliers});

  final List<Supplier> suppliers;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DataTable(
      columns: const [
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Phone')),
        DataColumn(label: Text('Email')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('')),
      ],
      rows: [
        for (final supplier in suppliers)
          DataRow(
            cells: [
              DataCell(
                Text(
                  supplier.name,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              DataCell(
                Text(
                  supplier.phone ?? '—',
                  style: textTheme.bodyMedium?.copyWith(
                    color: supplier.phone == null
                        ? context.appColors.textDisabled
                        : context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  supplier.email ?? '—',
                  style: textTheme.bodyMedium?.copyWith(
                    color: supplier.email == null
                        ? context.appColors.textDisabled
                        : context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(_StatusBadge(isActive: supplier.isActive)),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit supplier',
                      icon: const Icon(Icons.edit_outlined),
                      color: context.appColors.textSecondary,
                      onPressed: () =>
                          context.push(AppRoutes.supplierEdit, extra: supplier),
                    ),
                    _ToggleActiveButton(supplier: supplier),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final class _SupplierCard extends ConsumerWidget {
  const _SupplierCard({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      padding: AppInsets.card,
      onLongPress: () => _showSupplierActions(context, ref, supplier),
      child: Row(
        children: [
          AppAvatar(name: supplier.name),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  supplier.name,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [
                    supplier.phone ?? 'No phone',
                    supplier.email ?? 'No email',
                  ].join(' · '),
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(isActive: supplier.isActive),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            tooltip: 'Edit supplier',
            icon: const Icon(Icons.edit_outlined),
            color: context.appColors.textSecondary,
            onPressed: () =>
                context.push(AppRoutes.supplierEdit, extra: supplier),
          ),
          _ToggleActiveButton(supplier: supplier),
        ],
      ),
    );
  }
}

/// Phone-only supplier list: non-virtualized so the parent
/// [SingleChildScrollView] owns scrolling (no nested-ListView bounds).
final class _PhoneSupplierList extends StatelessWidget {
  const _PhoneSupplierList({required this.suppliers});

  final List<Supplier> suppliers;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: suppliers.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _PhoneSupplierCard(supplier: suppliers[index]),
      ),
    );
  }
}

/// Phone-only supplier card: prioritizes name and contact on a roomy top row
/// (avatar + edit action), then the status badge and activate/deactivate
/// toggle on a second row. Never the dense desktop-style presentation.
final class _PhoneSupplierCard extends ConsumerWidget {
  const _PhoneSupplierCard({required this.supplier});

  final Supplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      padding: AppInsets.card,
      onLongPress: () => _showSupplierActions(context, ref, supplier),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppAvatar(name: supplier.name),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: textTheme.titleSmall?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      [
                        supplier.phone ?? 'No phone',
                        supplier.email ?? 'No email',
                      ].join(' · '),
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                tooltip: 'Edit supplier',
                icon: const Icon(Icons.edit_outlined),
                color: context.appColors.textSecondary,
                onPressed: () =>
                    context.push(AppRoutes.supplierEdit, extra: supplier),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _StatusBadge(isActive: supplier.isActive),
              const Spacer(),
              _ToggleActiveButton(supplier: supplier),
            ],
          ),
        ],
      ),
    );
  }
}

/// Deactivate/activate toggle with a busy guard; failures surface as a
/// user-safe snackbar and never leave the list in a stale state (the
/// controller refreshes on success).
final class _ToggleActiveButton extends ConsumerStatefulWidget {
  const _ToggleActiveButton({required this.supplier});

  final Supplier supplier;

  @override
  ConsumerState<_ToggleActiveButton> createState() =>
      _ToggleActiveButtonState();
}

final class _ToggleActiveButtonState
    extends ConsumerState<_ToggleActiveButton> {
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(suppliersProvider.notifier)
          .setActive(widget.supplier.id, !widget.supplier.isActive);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(suppliersErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deactivating = widget.supplier.isActive;
    return _busy
        ? const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        : IconButton(
            tooltip: deactivating ? 'Deactivate supplier' : 'Activate supplier',
            icon: Icon(
              deactivating ? Icons.toggle_on : Icons.toggle_off,
              color: deactivating
                  ? AppColors.primary
                  : context.appColors.textDisabled,
            ),
            onPressed: _toggle,
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

/// Long-press context menu for a supplier card.
void _showSupplierActions(
  BuildContext context,
  WidgetRef ref,
  Supplier supplier,
) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: supplier.name,
    items: [
      ContextMenuItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () => context.push(AppRoutes.supplierEdit, extra: supplier),
      ),
      ContextMenuItem(
        icon: supplier.isActive
            ? Icons.block_outlined
            : Icons.check_circle_outline,
        label: supplier.isActive ? 'Deactivate' : 'Activate',
        destructive: supplier.isActive,
        onTap: () => _toggleSupplierActive(context, ref, supplier),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _deleteSupplier(context, ref, supplier),
        ),
    ],
  );
}

Future<void> _toggleSupplierActive(
  BuildContext context,
  WidgetRef ref,
  Supplier supplier,
) async {
  final deactivating = supplier.isActive;
  if (deactivating) {
    final confirmed = await confirmDestructive(
      context,
      title: 'Deactivate supplier',
      subject: supplier.name,
      consequence:
          'Deactivated suppliers are hidden from new purchases until '
          'reactivated. Their purchase history is kept.',
      confirmLabel: 'Deactivate',
    );
    if (!confirmed) return;
  }
  await ref
      .read(suppliersProvider.notifier)
      .setActive(supplier.id, !supplier.isActive);
}

Future<void> _deleteSupplier(
  BuildContext context,
  WidgetRef ref,
  Supplier supplier,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Delete supplier',
    subject: supplier.name,
    consequence:
        'If this supplier has purchase history they will be deactivated '
        'instead. Otherwise they will be permanently deleted — on this '
        'device and others. This cannot be undone.',
  );
  if (!confirmed) return;
  try {
    final result = await ref
        .read(suppliersProvider.notifier)
        .delete(supplier.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == SupplierDeleteResult.deactivated
              ? 'Supplier has purchase history — deactivated instead.'
              : 'Supplier deleted.',
        ),
      ),
    );
  } on SuppliersFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
