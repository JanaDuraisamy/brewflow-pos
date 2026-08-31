import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Purchase Detail Page
///
/// Shows one completed purchase from its persisted snapshot lines (product
/// name, SKU, unit cost and quantity at receiving time) plus the header
/// (number, date, supplier, notes) and totals. Historical values are never
/// re-read from current product data.
/// ---------------------------------------------------------------------------

final class PurchaseDetailPage extends ConsumerWidget {
  const PurchaseDetailPage({super.key, this.purchase});

  /// The purchase header; null when the route opened without one.
  final Purchase? purchase;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final purchase = this.purchase;
    if (purchase == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Purchase')),
        body: const Center(child: Text('Purchase not found.')),
      );
    }

    final items = ref.watch(purchaseItemsProvider(purchase.id));
    final supplierName = purchase.supplierId == null
        ? null
        : ref.watch(purchaseSupplierNameProvider(purchase.supplierId!)).value;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: Text(purchase.purchaseNumber)),
      body: SingleChildScrollView(
        padding: AppInsets.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    purchase.purchaseNumber,
                    style: textTheme.titleLarge?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    formatDateTime(purchase.createdAt),
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Datum(label: 'Supplier', value: supplierName ?? 'Walk-in'),
                  if (purchase.notes != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _Datum(label: 'Notes', value: purchase.notes!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Items',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            items.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: LoadingState(message: 'Loading items…'),
              ),
              error: (error, stackTrace) => ErrorState(
                message: purchasesErrorMessage(error),
                onRetry: () =>
                    ref.invalidate(purchaseItemsProvider(purchase.id)),
              ),
              data: (lines) => lines.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: Text('No items on this purchase.')),
                    )
                  : _ItemsList(items: lines),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                children: [
                  _TotalRow(label: 'Subtotal', paise: purchase.subtotalPaise),
                  const SizedBox(height: AppSpacing.xs),
                  _TotalRow(
                    label: 'Total',
                    paise: purchase.totalPaise,
                    emphasized: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _Datum extends StatelessWidget {
  const _Datum({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.charcoal,
            ),
          ),
        ),
      ],
    );
  }
}

final class _ItemsList extends StatelessWidget {
  const _ItemsList({required this.items});

  final List<PurchaseItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 640) {
          return _ItemsTable(items: items);
        }
        return _ItemsCards(items: items);
      },
    );
  }
}

final class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.items});

  final List<PurchaseItem> items;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: DataTable(
        columns: [
          const DataColumn(
            label: Text('Product'),
            columnWidth: IntrinsicColumnWidth(flex: 1),
          ),
          const DataColumn(label: Text('SKU')),
          const DataColumn(label: Text('Quantity')),
          const DataColumn(label: Text('Unit Cost')),
          const DataColumn(label: Text('Line Total')),
        ],
        rows: [
          for (final item in items)
            DataRow(
              cells: [
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Text(
                      item.variantName == null
                          ? item.productName
                          : '${item.productName} — ${item.variantName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(Text(item.sku ?? '—')),
                DataCell(Text('${item.quantity}')),
                DataCell(Text(Money.formatPaise(item.unitCostPaise))),
                DataCell(Text(Money.formatPaise(item.lineTotalPaise))),
              ],
            ),
        ],
      ),
    );
  }
}

final class _ItemsCards extends StatelessWidget {
  const _ItemsCards({required this.items});

  final List<PurchaseItem> items;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        items[i].variantName == null
                            ? items[i].productName
                            : '${items[i].productName} — ${items[i].variantName}',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.charcoal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      Money.formatPaise(items[i].lineTotalPaise),
                      style: textTheme.bodyMedium?.copyWith(
                        color: context.appColors.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (items[i].sku != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'SKU: ${items[i].sku}',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${items[i].quantity} × ${Money.formatPaise(items[i].unitCostPaise)}',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

final class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.paise,
    this.emphasized = false,
  });

  final String label;
  final int paise;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = emphasized
        ? textTheme.titleSmall?.copyWith(
            color: context.appColors.charcoal,
            fontWeight: FontWeight.w700,
          )
        : textTheme.bodyMedium?.copyWith(color: context.appColors.charcoal);
    return Row(
      children: [
        Text(label, style: style),
        const Spacer(),
        Text(Money.formatPaise(paise), style: style),
      ],
    );
  }
}
