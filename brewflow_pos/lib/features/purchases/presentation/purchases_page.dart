import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchases Landing Page
///
/// Purchase (receiving) history: search by purchase number or supplier, and a
/// responsive list (data table on wide screens, cards on narrow ones). Tapping
/// a purchase opens its snapshot detail. Receiving happens through the New
/// Purchase form.
/// ---------------------------------------------------------------------------

final class PurchasesPage extends ConsumerWidget {
  const PurchasesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchases = ref.watch(purchasesProvider);
    final filter = ref.watch(purchasesFilterProvider);
    final hasSearch = filter.query.trim().isNotEmpty;
    final phone = MediaQuery.sizeOf(context).width < 600;

    return Padding(
      padding: AppInsets.screen,
      child: phone
          ? _buildPhoneLayout(context, ref, purchases, filter, hasSearch)
          : _buildDesktopLayout(context, ref, purchases, filter, hasSearch),
    );
  }

  /// Phone (<600dp) layout: concise vertical hierarchy inside a
  /// [SingleChildScrollView] so it can never overflow vertically — header,
  /// prominent New Purchase action, search, then the list / empty state.
  Widget _buildPhoneLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PurchaseRow>> purchases,
    PurchasesFilter filter,
    bool hasSearch,
  ) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PageHeader(
            title: 'Purchases',
            subtitle: 'Receive and review stock purchases.',
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'New Purchase',
            icon: Icons.add,
            expanded: true,
            onPressed: () => context.push(AppRoutes.purchaseNew),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SearchBar(),
          const SizedBox(height: AppSpacing.lg),
          ...purchases.when(
            skipLoadingOnRefresh: true,
            loading: () => const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: LoadingState(message: 'Loading purchases…'),
                ),
              ),
            ],
            error: (error, stackTrace) => [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
                child: Center(
                  child: ErrorState(
                    message: purchasesErrorMessage(error),
                    onRetry: () => ref.invalidate(purchasesProvider),
                  ),
                ),
              ),
            ],
            data: (rows) => rows.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xxxl),
                      child: EmptyState(
                        icon: Icons.shopping_basket_outlined,
                        title: hasSearch
                            ? 'No purchases match your search'
                            : 'No purchases yet',
                        message: hasSearch
                            ? 'Try a different search or clear it.'
                            : 'Receive stock from your suppliers and it will appear here.',
                        action: hasSearch
                            ? SecondaryButton(
                                label: 'Clear Search',
                                icon: Icons.filter_alt_off_outlined,
                                onPressed: () => ref
                                    .read(purchasesFilterProvider.notifier)
                                    .clear(),
                              )
                            : PrimaryButton(
                                label: 'New Purchase',
                                icon: Icons.add,
                                onPressed: () =>
                                    context.push(AppRoutes.purchaseNew),
                              ),
                      ),
                    ),
                  ]
                : [_PhonePurchaseList(rows: rows)],
          ),
        ],
      ),
    );
  }

  /// Tablet / desktop (>=600dp) layout — unchanged from the original.
  Widget _buildDesktopLayout(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<PurchaseRow>> purchases,
    PurchasesFilter filter,
    bool hasSearch,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final header = const PageHeader(
              title: 'Purchases',
              subtitle: 'Receive and review stock purchases.',
            );
            final actions = PrimaryButton(
              label: 'New Purchase',
              icon: Icons.add,
              onPressed: () => context.push(AppRoutes.purchaseNew),
            );
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
        const _SearchBar(),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: purchases.when(
            skipLoadingOnRefresh: true,
            loading: () => const LoadingState(message: 'Loading purchases…'),
            error: (error, stackTrace) => ErrorState(
              message: purchasesErrorMessage(error),
              onRetry: () => ref.invalidate(purchasesProvider),
            ),
            data: (rows) => rows.isEmpty
                ? EmptyState(
                    icon: Icons.shopping_basket_outlined,
                    title: hasSearch
                        ? 'No purchases match your search'
                        : 'No purchases yet',
                    message: hasSearch
                        ? 'Try a different search or clear it.'
                        : 'Receive stock from your suppliers and it will appear here.',
                    action: hasSearch
                        ? SecondaryButton(
                            label: 'Clear Search',
                            icon: Icons.filter_alt_off_outlined,
                            onPressed: () => ref
                                .read(purchasesFilterProvider.notifier)
                                .clear(),
                          )
                        : PrimaryButton(
                            label: 'New Purchase',
                            icon: Icons.add,
                            onPressed: () =>
                                context.push(AppRoutes.purchaseNew),
                          ),
                  )
                : _PurchaseList(rows: rows),
          ),
        ),
      ],
    );
  }
}

final class _SearchBar extends ConsumerStatefulWidget {
  const _SearchBar();

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

final class _SearchBarState extends ConsumerState<_SearchBar> {
  late final TextEditingController _search = TextEditingController(
    text: ref.read(purchasesFilterProvider).query,
  );

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SearchField(
      controller: _search,
      hintText: 'Search by purchase number or supplier',
      onChanged: (value) =>
          ref.read(purchasesFilterProvider.notifier).setQuery(value),
    );
  }
}

final class _PurchaseList extends ConsumerWidget {
  const _PurchaseList({required this.rows});

  final List<PurchaseRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 800;
        return wide ? _PurchaseTable(rows: rows) : _PurchaseCards(rows: rows);
      },
    );
  }
}

final class _PurchaseTable extends StatelessWidget {
  const _PurchaseTable({required this.rows});

  final List<PurchaseRow> rows;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      child: DataTable(
        columnSpacing: 32,
        horizontalMargin: 12,
        columns: const [
          DataColumn(label: Text('Purchase No.')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Supplier')),
          DataColumn(label: Text('Total')),
        ],
        rows: [
          for (final row in rows)
            DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => context.push(
                      AppRoutes.purchaseDetail,
                      extra: row.purchase,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        row.purchase.purchaseNumber,
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => context.push(
                      AppRoutes.purchaseDetail,
                      extra: row.purchase,
                    ),
                    child: Text(formatDateTime(row.purchase.createdAt)),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => context.push(
                      AppRoutes.purchaseDetail,
                      extra: row.purchase,
                    ),
                    child: Text(row.supplierName ?? 'Walk-in'),
                  ),
                ),
                DataCell(
                  InkWell(
                    onTap: () => context.push(
                      AppRoutes.purchaseDetail,
                      extra: row.purchase,
                    ),
                    child: Text(Money.formatPaise(row.purchase.totalPaise)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

final class _PurchaseCards extends ConsumerWidget {
  const _PurchaseCards({required this.rows});

  final List<PurchaseRow> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final row = rows[index];
        return AppCard(
          onTap: () =>
              context.push(AppRoutes.purchaseDetail, extra: row.purchase),
          onLongPress: () => _showPurchaseActions(context, ref, row.purchase),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.purchase.purchaseNumber,
                      style: textTheme.titleSmall?.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    Money.formatPaise(row.purchase.totalPaise),
                    style: textTheme.titleSmall?.copyWith(
                      color: context.appColors.charcoal,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                row.supplierName ?? 'Walk-in',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                formatDateTime(row.purchase.createdAt),
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

final class _PhonePurchaseList extends StatelessWidget {
  const _PhonePurchaseList({required this.rows});

  final List<PurchaseRow> rows;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _PhonePurchaseCard(row: rows[index]),
      ),
    );
  }
}

/// Phone-only purchase card: compact vertical hierarchy (number + total,
/// supplier, date) that never overflows on narrow widths.
final class _PhonePurchaseCard extends ConsumerWidget {
  const _PhonePurchaseCard({required this.row});

  final PurchaseRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => context.push(AppRoutes.purchaseDetail, extra: row.purchase),
      onLongPress: () => _showPurchaseActions(context, ref, row.purchase),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.purchase.purchaseNumber,
                  style: textTheme.titleSmall?.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                Money.formatPaise(row.purchase.totalPaise),
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.charcoal,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            row.supplierName ?? 'Walk-in',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatDateTime(row.purchase.createdAt),
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Long-press context menu for a purchase card.
void _showPurchaseActions(
  BuildContext context,
  WidgetRef ref,
  Purchase purchase,
) {
  final isOwner = ref.read(userProfileProvider).value?.isOwner ?? true;
  showContextActionSheet(
    context,
    title: purchase.purchaseNumber,
    items: [
      ContextMenuItem(
        icon: Icons.receipt_long_outlined,
        label: 'View Details',
        onTap: () => context.push(AppRoutes.purchaseDetail, extra: purchase),
      ),
      if (isOwner)
        ContextMenuItem(
          icon: Icons.undo_outlined,
          label: 'Void Purchase',
          destructive: true,
          onTap: () => _voidPurchase(context, ref, purchase),
        ),
    ],
  );
}

Future<void> _voidPurchase(
  BuildContext context,
  WidgetRef ref,
  Purchase purchase,
) async {
  final confirmed = await confirmDestructive(
    context,
    title: 'Void purchase',
    subject: purchase.purchaseNumber,
    consequence:
        'The stock added by this purchase will be reversed and the receipt '
        'will be removed. This cannot be undone.',
    confirmLabel: 'Void',
  );
  if (!confirmed) return;
  try {
    await ref.read(purchasesProvider.notifier).voidPurchase(purchase.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Purchase voided.')));
  } on PurchasesFailure catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(error.message)));
  }
}
