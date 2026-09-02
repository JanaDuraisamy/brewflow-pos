import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_breakpoints.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/product_thumbnail.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_history_page.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Inventory Landing Page
///
/// Local-first product management: search by name/SKU, filter by category and
/// active state, and a responsive list (data table on wide screens, cards on
/// narrow ones). All money figures come from exact paise values.
/// ---------------------------------------------------------------------------

final class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(productsProvider);
    final filter = ref.watch(inventoryFilterProvider);
    final categories = ref.watch(categoriesProvider);
    final hasFilters =
        filter.query.isNotEmpty ||
        filter.categoryId != null ||
        filter.status != ProductStatusFilter.all ||
        filter.lowStockOnly;

    final compact = AppBreakpoints.fromWidth(
      MediaQuery.sizeOf(context).width,
    ).isCompact;

    if (compact) {
      return _MobileInventoryView(
        products: products,
        categories: categories.value ?? const [],
        hasFilters: hasFilters,
      );
    }

    return Padding(
      padding: AppInsets.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 600;
              final header = const PageHeader(
                title: 'Inventory',
                subtitle: 'Manage products, categories and stock levels.',
              );
              final actions = const _HeaderActions();
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    SizedBox(height: AppSpacing.md),
                    actions,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: header),
                  SizedBox(width: AppSpacing.md),
                  actions,
                ],
              );
            },
          ),
          SizedBox(height: AppSpacing.md),
          _FilterBar(categories: categories.value ?? const []),
          SizedBox(height: AppSpacing.md),
          Expanded(
            child: products.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => _ErrorState(
                message: inventoryErrorMessage(error),
                onRetry: () => ref.invalidate(productsProvider),
              ),
              data: (items) => items.isEmpty
                  ? _EmptyState(
                      filtered: hasFilters,
                      onClearFilters: hasFilters
                          ? () => ref
                                .read(inventoryFilterProvider.notifier)
                                .clear()
                          : null,
                      onAddProduct: () => context.push(AppRoutes.productNew),
                    )
                  : _ProductList(
                      products: items,
                      categories: categories.value ?? const [],
                      filtered: hasFilters,
                    ),
            ),
          ),
        ],
      ),
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
        OutlinedButton.icon(
          onPressed: () => context.push(AppRoutes.inventoryCategories),
          icon: const Icon(Icons.category_outlined),
          label: const Text('Categories'),
        ),
        FilledButton.icon(
          onPressed: () => context.push(AppRoutes.productNew),
          icon: const Icon(Icons.add),
          label: const Text('Add Product'),
        ),
      ],
    );
  }
}

/// Phone (compact) inventory view. Owns the bulk multi-select mode: entering
/// selection shows checkboxes on product cards and a safe action bar for bulk
/// activate/deactivate (never deletion). The desktop layout is untouched.
final class _MobileInventoryView extends ConsumerStatefulWidget {
  const _MobileInventoryView({
    required this.products,
    required this.categories,
    required this.hasFilters,
  });

  final AsyncValue<List<Product>> products;
  final List<Category> categories;
  final bool hasFilters;

  @override
  ConsumerState<_MobileInventoryView> createState() =>
      _MobileInventoryViewState();
}

final class _MobileInventoryViewState
    extends ConsumerState<_MobileInventoryView> {
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  void _toggle(String id) {
    setState(() {
      if (!_selectedIds.add(id)) {
        _selectedIds.remove(id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
    });
  }

  Future<void> _applyBatch(bool activate) async {
    final ids = List<String>.of(_selectedIds);
    if (ids.isEmpty) return;
    final deactivating = !activate;
    if (deactivating) {
      final confirmed = await confirmDestructive(
        context,
        title: 'Deactivate products',
        subject: ids.length == 1 ? '1 product' : '${ids.length} products',
        consequence:
            'Deactivated products are hidden from new sales until '
            'reactivated. Their stock and history are kept.',
        confirmLabel: 'Deactivate',
      );
      if (!confirmed) return;
    }
    final controller = ref.read(productsProvider.notifier);
    for (final id in ids) {
      await controller.setActive(id, activate);
    }
    if (mounted) _cancelSelection();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: AppInsets.screen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_selecting)
            _SelectionBar(count: _selectedIds.length, onClose: _cancelSelection)
          else ...[
            _MobileHeader(onSelect: () => setState(() => _selecting = true)),
            const SizedBox(height: AppSpacing.md),
            const _MobileSearch(),
            const SizedBox(height: AppSpacing.md),
            _MobileFilterBar(categories: widget.categories),
          ],
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: widget.products.when(
              skipLoadingOnRefresh: true,
              loading: () => const LoadingState(),
              error: (error, stackTrace) => ErrorState(
                message: inventoryErrorMessage(error),
                onRetry: () => ref.invalidate(productsProvider),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return EmptyState(
                    icon: widget.hasFilters
                        ? Icons.search_off
                        : Icons.inventory_2_outlined,
                    title: widget.hasFilters
                        ? 'No products match your filters'
                        : 'No products yet',
                    message: widget.hasFilters
                        ? 'Try a different search or clear the filters.'
                        : 'Add your first product to start managing stock.',
                    action: widget.hasFilters
                        ? SecondaryButton(
                            label: 'Clear Filters',
                            icon: Icons.filter_alt_off_outlined,
                            onPressed: () => ref
                                .read(inventoryFilterProvider.notifier)
                                .clear(),
                          )
                        : PrimaryButton(
                            label: 'Add Product',
                            icon: Icons.add,
                            onPressed: () => context.push(AppRoutes.productNew),
                          ),
                  );
                }
                return _MobileProductList(
                  products: items,
                  selecting: _selecting,
                  selectedIds: _selectedIds,
                  onToggle: _toggle,
                );
              },
            ),
          ),
          if (_selecting) ...[
            const SizedBox(height: AppSpacing.md),
            _BatchActionBar(
              enabled: _selectedIds.isNotEmpty,
              onActivate: () => _applyBatch(true),
              onDeactivate: () => _applyBatch(false),
            ),
          ],
        ],
      ),
    );
  }
}

/// Compact selection header: closes selection and reports how many product
/// cards are currently selected.
final class _SelectionBar extends StatelessWidget {
  const _SelectionBar({required this.count, required this.onClose});

  final int count;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancel selection',
          icon: const Icon(Icons.close),
          color: context.appColors.textSecondary,
          onPressed: onClose,
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          '$count selected',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Safe (non-destructive) bulk actions available in selection mode.
final class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.enabled,
    required this.onActivate,
    required this.onDeactivate,
  });

  final bool enabled;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: enabled ? onActivate : null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Activate'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: enabled ? onDeactivate : null,
            icon: const Icon(Icons.block_outlined),
            label: const Text('Deactivate'),
          ),
        ),
      ],
    );
  }
}

/// Phone header: title first with a compact "Select" entry for bulk mode,
/// then a prominent full-width add action paired with the category management
/// action as the secondary control.
final class _MobileHeader extends StatelessWidget {
  const _MobileHeader({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: PageHeader(
                title: 'Inventory',
                subtitle: 'Manage products, categories and stock levels.',
              ),
            ),
            TextButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.checklist, size: 18),
              label: const Text('Select'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: 'Add Product',
                icon: Icons.add,
                expanded: true,
                onPressed: () => context.push(AppRoutes.productNew),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SecondaryButton(
              label: 'Categories',
              icon: Icons.category_outlined,
              onPressed: () => context.push(AppRoutes.inventoryCategories),
            ),
          ],
        ),
      ],
    );
  }
}

/// Phone search field, always synced with the stored filter query so a
/// "Clear Filters" action empties the visible search text too.
final class _MobileSearch extends ConsumerStatefulWidget {
  const _MobileSearch();

  @override
  ConsumerState<_MobileSearch> createState() => _MobileSearchState();
}

final class _MobileSearchState extends ConsumerState<_MobileSearch> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(inventoryFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(inventoryFilterProvider).query;
    if (query != _search.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _search.text != query) {
          _search.text = query;
        }
      });
    }
    return SearchField(
      controller: _search,
      hintText: 'Search by name or SKU',
      onChanged: (value) =>
          ref.read(inventoryFilterProvider.notifier).setQuery(value),
    );
  }
}

final class _FilterBar extends ConsumerStatefulWidget {
  const _FilterBar({required this.categories});

  final List<Category> categories;

  @override
  ConsumerState<_FilterBar> createState() => _FilterBarState();
}

final class _FilterBarState extends ConsumerState<_FilterBar> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(inventoryFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(inventoryFilterProvider);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _search,
            onChanged: (value) =>
                ref.read(inventoryFilterProvider.notifier).setQuery(value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by name or SKU',
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
        ),
        SegmentedButton<ProductStatusFilter>(
          segments: const [
            ButtonSegment(value: ProductStatusFilter.all, label: Text('All')),
            ButtonSegment(
              value: ProductStatusFilter.active,
              label: Text('Active'),
            ),
            ButtonSegment(
              value: ProductStatusFilter.inactive,
              label: Text('Inactive'),
            ),
          ],
          selected: {filter.status},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => ref
              .read(inventoryFilterProvider.notifier)
              .setStatus(selection.first),
        ),
        DropdownButton<String?>(
          value: filter.categoryId,
          hint: const Text('All categories'),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text('All categories'),
            ),
            for (final category in widget.categories)
              DropdownMenuItem<String?>(
                value: category.id,
                child: Text(category.name),
              ),
          ],
          onChanged: (id) =>
              ref.read(inventoryFilterProvider.notifier).setCategory(id),
        ),
        AppFilterChip(
          label: 'Low Stock',
          selected: filter.lowStockOnly,
          onSelected: (selected) => ref
              .read(inventoryFilterProvider.notifier)
              .setLowStockOnly(selected),
        ),
      ],
    );
  }
}

/// Phone filter bar: a single "Filters" trigger that opens a filter sheet, so
/// narrow screens never show crowded horizontal chip rows. Categories stay a
/// secondary control inside that sheet, never dominant.
final class _MobileFilterBar extends ConsumerStatefulWidget {
  const _MobileFilterBar({required this.categories});

  final List<Category> categories;

  @override
  ConsumerState<_MobileFilterBar> createState() => _MobileFilterBarState();
}

final class _MobileFilterBarState extends ConsumerState<_MobileFilterBar> {
  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(inventoryFilterProvider);
    final notifier = ref.read(inventoryFilterProvider.notifier);

    final statusChips = [
      _chip(
        label: 'All',
        selected: filter.status == ProductStatusFilter.all,
        onTap: () => notifier.setStatus(ProductStatusFilter.all),
      ),
      _chip(
        label: 'Active',
        selected: filter.status == ProductStatusFilter.active,
        onTap: () => notifier.setStatus(ProductStatusFilter.active),
      ),
      _chip(
        label: 'Inactive',
        selected: filter.status == ProductStatusFilter.inactive,
        onTap: () => notifier.setStatus(ProductStatusFilter.inactive),
      ),
      _chip(
        label: 'Low Stock',
        selected: filter.lowStockOnly,
        onTap: () => notifier.setLowStockOnly(!filter.lowStockOnly),
      ),
    ];

    final categoryChips = [
      _chip(
        label: 'All Categories',
        selected: filter.categoryId == null,
        onTap: () => notifier.setCategory(null),
      ),
      for (final category in widget.categories)
        _chip(
          label: category.name,
          selected: filter.categoryId == category.id,
          onTap: () => notifier.setCategory(category.id),
        ),
    ];

    final activeCount =
        (filter.status != ProductStatusFilter.all ? 1 : 0) +
        (filter.lowStockOnly ? 1 : 0) +
        (filter.categoryId != null ? 1 : 0);

    return FilterSheetButton(
      activeCount: activeCount,
      onPressed: () => showFilterSheet(
        context,
        title: 'Filter Products',
        onReset: notifier.clear,
        children: [
          _sectionLabel('Status'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: statusChips,
          ),
          if (widget.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            _sectionLabel('Category'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: categoryChips,
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
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

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppFilterChip(
      label: label,
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

final class _ProductList extends ConsumerWidget {
  const _ProductList({
    required this.products,
    required this.categories,
    required this.filtered,
  });

  final List<Product> products;
  final List<Category> categories;

  /// True when the current filter hides the full catalogue.
  final bool filtered;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < AppBreakpoints.compact) {
      return _MobileProductList(products: products);
    }
    if (width >= 800) {
      // The table can be taller and wider than the available viewport. The
      // outer (vertical) scroll view lets rows that fall below the fold be
      // reached, while the inner (horizontal) scroll view keeps the wide
      // columns scrollable.
      return Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: _ProductTable(products: products, categories: categories),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: products.length,
      itemBuilder: (context, index) => _ProductCard(
        product: products[index],
        categoryName: _categoryName(categories, products[index].categoryId),
      ),
    );
  }
}

final class _ProductTable extends StatelessWidget {
  const _ProductTable({required this.products, required this.categories});

  final List<Product> products;
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DataTable(
      columns: const [
        DataColumn(label: Text('Product')),
        DataColumn(label: Text('Category')),
        DataColumn(label: Text('Selling Price')),
        DataColumn(label: Text('Cost Price')),
        DataColumn(label: Text('Stock')),
        DataColumn(label: Text('Status')),
        DataColumn(label: Text('Actions')),
      ],
      rows: [
        for (final product in products)
          DataRow(
            onSelectChanged: (_) =>
                context.push(AppRoutes.productEdit, extra: product),
            cells: [
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProductThumbnail(imagePath: product.imagePath, size: 36),
                    SizedBox(width: AppSpacing.sm + 2),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          style: textTheme.bodyMedium?.copyWith(
                            color: context.appColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (product.sku != null)
                          Text(
                            'SKU ${product.sku}',
                            style: textTheme.bodySmall?.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              DataCell(
                Text(
                  _categoryName(categories, product.categoryId),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  Money.formatPaise(product.sellingPricePaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  product.costPricePaise == null
                      ? '—'
                      : Money.formatPaise(product.costPricePaise!),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
              DataCell(
                Text(
                  _stockCellText(product),
                  style: textTheme.bodyMedium?.copyWith(
                    color: product.stockQuantity == 0
                        ? AppColors.outOfStock
                        : context.appColors.textPrimary,
                  ),
                ),
              ),
              DataCell(_StatusBadge(isActive: product.isActive)),
              DataCell(
                IconButton(
                  tooltip: 'Adjust stock',
                  icon: const Icon(Icons.swap_vert),
                  color: context.appColors.textSecondary,
                  onPressed: () => _showAdjustStockDialog(context, product),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final class _ProductCard extends ConsumerWidget {
  const _ProductCard({required this.product, required this.categoryName});

  final Product product;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final globalThreshold =
        ref.watch(shopSettingsProvider).value?.lowStockThreshold ??
        ShopSettings.defaultLowStockThreshold;
    final threshold = effectiveLowStockThreshold(product, globalThreshold);
    final stockColor = product.stockQuantity <= 0
        ? AppColors.outOfStock
        : isLowStock(stock: product.stockQuantity, threshold: threshold)
        ? AppColors.lowStock
        : context.appColors.textPrimary;
    final unit = _stockUnitSuffix(product.stockUnit);
    final alert = threshold != null && product.stockQuantity <= 0
        ? const _StockAlertChip(
            label: 'Out of stock',
            color: AppColors.outOfStock,
          )
        : threshold != null &&
              isLowStock(stock: product.stockQuantity, threshold: threshold)
        ? const _StockAlertChip(label: 'Low stock', color: AppColors.lowStock)
        : null;

    return Card(
      color: context.appColors.surface,
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.lg,
        side: BorderSide(color: context.appColors.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.card.left,
              AppInsets.card.top,
              AppInsets.card.right,
              AppSpacing.xs,
            ),
            child: Row(
              children: [
                ProductThumbnail(imagePath: product.imagePath),
                SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: textTheme.titleSmall?.copyWith(
                          color: context.appColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        [
                          categoryName,
                          if (product.sku != null) 'SKU ${product.sku}',
                        ].join(' · '),
                        style: textTheme.bodySmall?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: AppSpacing.sm),
                IconButton(
                  tooltip: 'Stock history',
                  icon: const Icon(Icons.history),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  color: context.appColors.textSecondary,
                  onPressed: () => context.push(
                    AppRoutes.productStockHistory,
                    extra: StockHistoryArgs(product: product),
                  ),
                ),
                IconButton(
                  tooltip: 'Adjust stock',
                  icon: const Icon(Icons.swap_vert),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  color: context.appColors.textSecondary,
                  onPressed: () => _showAdjustStockDialog(context, product),
                ),
                IconButton(
                  tooltip: 'Edit product',
                  icon: const Icon(Icons.edit_outlined),
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                  color: context.appColors.textSecondary,
                  onPressed: () =>
                      context.push(AppRoutes.productEdit, extra: product),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.card.left,
              AppSpacing.xs,
              AppInsets.card.right,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      Money.formatPaise(product.sellingPricePaise),
                      if (product.costPricePaise != null)
                        'Cost ${Money.formatPaise(product.costPricePaise!)}',
                      'Stock ${product.stockQuantity}${unit.isEmpty ? '' : ' $unit'}',
                    ].join('  ·  '),
                    style: textTheme.bodySmall?.copyWith(color: stockColor),
                  ),
                ),
                if (alert != null) ...[SizedBox(width: AppSpacing.sm), alert],
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppInsets.card.left,
              AppSpacing.sm,
              AppInsets.card.right,
              AppInsets.card.bottom,
            ),
            child: Row(children: [_StatusBadge(isActive: product.isActive)]),
          ),
          if (product.variants.isNotEmpty)
            _VariantsTile(product: product, globalThreshold: globalThreshold),
        ],
      ),
    );
  }
}

/// Phone product list: clean [AppCard]s with a readable
/// name / SKU / price / stock / status layout and a single stock action.
/// In selection mode each card toggles via [onToggle] so users can bulk
/// activate/deactivate products.
final class _MobileProductList extends ConsumerWidget {
  const _MobileProductList({
    required this.products,
    this.selecting = false,
    this.selectedIds = const {},
    this.onToggle,
  });

  final List<Product> products;
  final bool selecting;
  final Set<String> selectedIds;
  final ValueChanged<String>? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      itemCount: products.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.md),
      itemBuilder: (context, index) {
        final product = products[index];
        return _MobileProductCard(
          product: product,
          selecting: selecting,
          selected: selectedIds.contains(product.id),
          onToggle: () => onToggle?.call(product.id),
        );
      },
    );
  }
}

final class _MobileProductCard extends ConsumerWidget {
  const _MobileProductCard({
    required this.product,
    this.selecting = false,
    this.selected = false,
    this.onToggle,
  });

  final Product product;
  final bool selecting;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final globalThreshold =
        ref.watch(shopSettingsProvider).value?.lowStockThreshold ??
        ShopSettings.defaultLowStockThreshold;
    final threshold = effectiveLowStockThreshold(product, globalThreshold);
    final stockColor = product.stockQuantity <= 0
        ? AppColors.outOfStock
        : isLowStock(stock: product.stockQuantity, threshold: threshold)
        ? AppColors.lowStock
        : appColors.textPrimary;
    final unit = _stockUnitSuffix(product.stockUnit);
    final stockValue = unit.isEmpty
        ? '${product.stockQuantity}'
        : '${product.stockQuantity} $unit';

    return AppCard(
      onTap: selecting
          ? onToggle
          : () => context.push(AppRoutes.productEdit, extra: product),
      onLongPress: selecting
          ? onToggle
          : () => _showProductActions(context, ref, product),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selecting) ...[
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 22,
                  color: selected ? AppColors.primary : appColors.textDisabled,
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleSmall?.copyWith(
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (product.sku != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'SKU ${product.sku}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: appColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (!selecting)
                IconButton(
                  tooltip: 'Adjust stock',
                  icon: const Icon(Icons.swap_vert),
                  visualDensity: VisualDensity.compact,
                  color: appColors.textSecondary,
                  onPressed: () => _showAdjustStockDialog(context, product),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _MobileMetric(
                  label: 'Price',
                  value: Money.formatPaise(product.sellingPricePaise),
                  valueColor: appColors.textPrimary,
                ),
              ),
              Expanded(
                child: _MobileMetric(
                  label: 'Stock',
                  value: stockValue,
                  valueColor: stockColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _StatusBadge(isActive: product.isActive),
        ],
      ),
    );
  }
}

final class _MobileMetric extends StatelessWidget {
  const _MobileMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.bodySmall?.copyWith(
            color: context.appColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Expandable variant summary shown under a variant product card.
final class _VariantsTile extends StatelessWidget {
  const _VariantsTile({required this.product, required this.globalThreshold});

  final Product product;
  final int globalThreshold;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final unit = _stockUnitSuffix(product.stockUnit);
    final variants = product.variants;
    return ExpansionTile(
      tilePadding: AppInsets.card,
      childrenPadding: EdgeInsets.fromLTRB(
        AppInsets.card.left,
        0,
        AppInsets.card.right,
        AppSpacing.sm,
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      title: Text(
        '${variants.length} ${variants.length == 1 ? 'variant' : 'variants'}',
        style: textTheme.bodyMedium?.copyWith(
          color: context.appColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      children: [
        for (final variant in variants)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: InkWell(
              borderRadius: AppBorderRadius.md,
              onTap: () => context.push(
                AppRoutes.productStockHistory,
                extra: StockHistoryArgs(product: product, variant: variant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: variant.isActive
                            ? AppColors.success
                            : context.appColors.textDisabled,
                        shape: BoxShape.circle,
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            variant.name,
                            style: textTheme.bodyMedium?.copyWith(
                              color: context.appColors.textPrimary,
                            ),
                          ),
                          if (variant.sku != null)
                            Text(
                              'SKU ${variant.sku}',
                              style: textTheme.bodySmall?.copyWith(
                                color: context.appColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text(
                      [
                        Money.formatPaise(variant.sellingPricePaise),
                        'Stock ${variant.stockQuantity}${unit.isEmpty ? '' : ' $unit'}',
                      ].join(' · '),
                      style: textTheme.bodySmall?.copyWith(
                        color: _variantStockColor(
                          context,
                          variant,
                          product,
                          globalThreshold,
                        ),
                      ),
                    ),
                    SizedBox(width: AppSpacing.xs),
                    IconButton(
                      tooltip: 'Adjust variant stock',
                      icon: const Icon(Icons.swap_vert, size: 18),
                      visualDensity: VisualDensity.compact,
                      color: context.appColors.textSecondary,
                      onPressed: () => _showAdjustStockDialog(
                        context,
                        product,
                        variant: variant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _variantStockColor(
    BuildContext context,
    ProductVariant variant,
    Product product,
    int globalThreshold,
  ) {
    if (variant.stockQuantity <= 0) {
      return AppColors.outOfStock;
    }
    final threshold = effectiveVariantLowStockThreshold(
      variant,
      product,
      globalThreshold,
    );
    if (isLowStock(stock: variant.stockQuantity, threshold: threshold)) {
      return AppColors.lowStock;
    }
    return context.appColors.textSecondary;
  }
}

/// Small pill marking a stock-level problem (low or out).
final class _StockAlertChip extends StatelessWidget {
  const _StockAlertChip({required this.label, required this.color});

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

/// Short display suffix for measured stock units; empty for counted stock.
String _stockUnitSuffix(StockUnit unit) => switch (unit) {
  StockUnit.ml => 'ml',
  StockUnit.gram => 'g',
  StockUnit.kg => 'kg',
  StockUnit.count || StockUnit.none => '',
};

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

String _categoryName(List<Category> categories, String id) {
  for (final category in categories) {
    if (category.id == id) {
      return category.name;
    }
  }
  return '—';
}

String _stockCellText(Product product) {
  final unit = _stockUnitSuffix(product.stockUnit);
  return unit.isEmpty
      ? '${product.stockQuantity}'
      : '${product.stockQuantity} $unit';
}

void _showAdjustStockDialog(
  BuildContext context,
  Product product, {
  ProductVariant? variant,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => StockAdjustmentDialog(product: product, variant: variant),
  );
}

/// Long-press context menu for a product card: quick, safe access to editing,
/// stock adjustment and activate/deactivate without hunting through the page.
void _showProductActions(BuildContext context, WidgetRef ref, Product product) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: product.name,
    items: [
      ContextMenuItem(
        icon: Icons.edit_outlined,
        label: 'Edit',
        onTap: () => context.push(AppRoutes.productEdit, extra: product),
      ),
      ContextMenuItem(
        icon: Icons.swap_vert,
        label: 'Adjust Stock',
        onTap: () => _showAdjustStockDialog(context, product),
      ),
      ContextMenuItem(
        icon: product.isActive
            ? Icons.block_outlined
            : Icons.check_circle_outline,
        label: product.isActive ? 'Deactivate' : 'Activate',
        destructive: product.isActive,
        onTap: () => _toggleProductActive(context, ref, product),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: 'Delete',
          destructive: true,
          onTap: () => _deleteProduct(context, ref, product),
        ),
    ],
  );
}

Future<void> _toggleProductActive(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  final deactivating = product.isActive;
  if (deactivating) {
    final confirmed = await confirmDestructive(
      context,
      title: 'Deactivate product',
      subject: product.name,
      consequence:
          'Deactivated products are hidden from new sales until reactivated. '
          'Your stock and history are kept.',
      confirmLabel: 'Deactivate',
    );
    if (!confirmed) return;
  }
  await ref
      .read(productsProvider.notifier)
      .setActive(product.id, !product.isActive);
}

Future<void> _deleteProduct(
  BuildContext context,
  WidgetRef ref,
  Product product,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Delete product',
    subject: product.name,
    consequence:
        'If this product has variants, sales, purchases or stock history it '
        'will be deactivated instead. Otherwise it will be permanently '
        'deleted — on this device and others. This cannot be undone.',
  );
  if (!confirmed) return;
  try {
    final result = await ref.read(productsProvider.notifier).delete(product.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == ProductDeleteResult.deactivated
              ? 'Product has history — deactivated instead.'
              : 'Product deleted.',
        ),
      ),
    );
  } on InventoryFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
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
                'Could not load products',
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
  const _EmptyState({
    required this.filtered,
    this.onClearFilters,
    this.onAddProduct,
  });

  final bool filtered;
  final VoidCallback? onClearFilters;
  final VoidCallback? onAddProduct;

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
                Icons.inventory_2_outlined,
                size: AppSpacing.ultra,
                color: AppColors.primary,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                filtered ? 'No products match your filters' : 'No products yet',
                textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                filtered
                    ? 'Try a different search or clear the filters.'
                    : 'Add your first product to start managing stock.',
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
                )
              else
                FilledButton.icon(
                  onPressed: onAddProduct,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Product'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
