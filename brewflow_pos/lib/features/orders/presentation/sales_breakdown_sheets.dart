import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/payment_attribution.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Sales Breakdown Sheets
///
/// Bounded bottom sheets behind the dashboard and Reports Bills/Items KPI
/// cards. Both sheets are pure display over already-loaded data — they never
/// query repositories themselves, so tapping a card adds no database reads.
///
/// - [BillsBreakdownSheet]: one row per bill (receipt, payment label,
///   item count, local time, total). Split sales read through
///   [paymentDisplayLabel], which renders their NULL header method as
///   'Split' instead of throwing.
/// - [ItemsBreakdownSheet]: one row per (product, variant) aggregate
///   ([ItemSalesRow]), so variants stay distinguishable.
///
/// In the Combined view callers pass [shopLabels] to tag each bill with its
/// business; single-shop reads pass null and render no shop text.
/// ---------------------------------------------------------------------------

/// Opens [BillsBreakdownSheet] as a bounded modal bottom sheet.
Future<void> showBillsBreakdownSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<OrderSummary> bills,
  Map<String, String>? shopLabels,
  String emptyMessage = 'No bills in this period.',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => BillsBreakdownSheet(
      title: title,
      subtitle: subtitle,
      bills: bills,
      shopLabels: shopLabels,
      emptyMessage: emptyMessage,
    ),
  );
}

/// Opens [ItemsBreakdownSheet] as a bounded modal bottom sheet.
Future<void> showItemsBreakdownSheet({
  required BuildContext context,
  required String title,
  required String subtitle,
  required List<ItemSalesRow> rows,
  String emptyMessage = 'No items sold in this period.',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ItemsBreakdownSheet(
      title: title,
      subtitle: subtitle,
      rows: rows,
      emptyMessage: emptyMessage,
    ),
  );
}

/// Bill-wise drill-down: every bill in the window, newest first (callers pass
/// repository order through), with its receipt, payment, items and total.
///
/// Phone-first: single-column, scrollable, no fixed widths — safe at
/// 360–480dp.
final class BillsBreakdownSheet extends StatelessWidget {
  const BillsBreakdownSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.bills,
    this.shopLabels,
    this.emptyMessage = 'No bills in this period.',
  });

  final String title;
  final String subtitle;
  final List<OrderSummary> bills;

  /// Business labels by shop id; null in single-shop reads (no shop text).
  final Map<String, String>? shopLabels;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppInsets.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: bills.isEmpty
                    ? Padding(
                        padding: AppInsets.screen,
                        child: Text(
                          emptyMessage,
                          style: textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: AppInsets.screen,
                        itemCount: bills.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) => _BillRow(
                          bill: bills[index],
                          shopLabels: shopLabels,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One bill: receipt with total on the first line, payment label, item count,
/// local time (and business, in the Combined view) on the second.
final class _BillRow extends StatelessWidget {
  const _BillRow({required this.bill, this.shopLabels});

  final OrderSummary bill;
  final Map<String, String>? shopLabels;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = [
      paymentDisplayLabel(bill.paymentStatus, bill.paymentMethod),
      itemsLabel(bill.itemCount),
      formatDateTime(bill.createdAt),
      if (shopLabels != null)
        bill.shopId == null
            ? 'Business'
            : (shopLabels![bill.shopId] ?? 'Business'),
    ];
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    bill.receiptNumber,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  Money.formatPaise(bill.totalPaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              details.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Item-wise drill-down: one row per (product, variant) aggregate, highest
/// revenue first (callers pass sorted rows through).
final class ItemsBreakdownSheet extends StatelessWidget {
  const ItemsBreakdownSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rows,
    this.emptyMessage = 'No items sold in this period.',
  });

  final String title;
  final String subtitle;
  final List<ItemSalesRow> rows;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppInsets.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      subtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: rows.isEmpty
                    ? Padding(
                        padding: AppInsets.screen,
                        child: Text(
                          emptyMessage,
                          style: textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: AppInsets.screen,
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) =>
                            _ItemRow(row: rows[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One item aggregate: product (and variant) with units on the left, revenue
/// on the right.
final class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.row});

  final ItemSalesRow row;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row.unitsSold} pcs',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              Money.formatPaise(row.revenuePaise),
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
