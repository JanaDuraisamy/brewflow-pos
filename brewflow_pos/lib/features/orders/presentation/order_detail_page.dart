import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Order Detail Page
///
/// Read-only view of one completed sale. Every figure — names, SKUs, unit
/// prices, line totals, subtotal, total, payment — comes from the persisted
/// snapshots written by the Billing module at checkout time, so history
/// never changes when products are later renamed, repriced or deactivated.
/// Pushed from the orders list, so it carries its own scaffold and the
/// standard back navigation.
/// ---------------------------------------------------------------------------

final class OrderDetailPage extends ConsumerWidget {
  const OrderDetailPage({super.key, this.order});

  /// The list-row summary (needed for the nominal path, so the header can
  /// render instantly); null only on crafted deep links.
  final OrderSummary? order;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = order;
    if (summary == null) {
      return const _DetailScaffold(title: 'Order', child: _UnavailableBody());
    }
    final detail = ref.watch(orderDetailProvider(summary.id));
    return _DetailScaffold(
      title: summary.receiptNumber,
      shareBuilder: () => detail.value == null
          ? null
          : ReceiptDocument.fromOrder(
              shopName:
                  ref.watch(shopSettingsProvider).value?.shopName ??
                  ShopSettings.defaults().shopName,
              order: detail.value!,
            ),
      onShare: (document) {
        // Sharing is best-effort: a failure never affects the sale.
        ref
            .read(shareServiceProvider)
            .shareText(
              subject: 'Receipt ${document.receiptNumber}',
              text: document.toPlainText(),
            )
            .catchError((Object _) {});
      },
      child: detail.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _ErrorState(
          message: ordersErrorMessage(error),
          onRetry: () => ref.invalidate(orderDetailProvider(summary.id)),
        ),
        data: (data) => _DetailBody(order: data),
      ),
    );
  }
}

final class _DetailScaffold extends StatelessWidget {
  const _DetailScaffold({
    required this.title,
    required this.child,
    this.shareBuilder,
    this.onShare,
  });

  final String title;
  final Widget child;
  final ReceiptDocument? Function()? shareBuilder;
  final void Function(ReceiptDocument document)? onShare;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appColors.background,
      appBar: AppBar(
        backgroundColor: context.appColors.background,
        surfaceTintColor: Colors.transparent,
        title: Text('Order $title'),
        actions: [
          if (shareBuilder?.call() != null)
            IconButton(
              tooltip: 'Share Bill',
              icon: const Icon(Icons.share_outlined),
              onPressed: () {
                final doc = shareBuilder?.call();
                if (doc != null) onShare?.call(doc);
              },
            ),
        ],
      ),
      body: SafeArea(child: child),
    );
  }
}

final class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: AppInsets.screen,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: AppBorderRadius.lg,
            border: Border.all(color: context.appColors.divider),
          ),
          padding: AppInsets.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.receiptNumber,
                      style: textTheme.titleLarge?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (order.isVoided) ...[
                    const _VoidedBadge(),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  _PaymentBadge(
                    status: order.paymentStatus,
                    method: order.paymentMethod,
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                formatDateTime(order.createdAt),
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: context.appColors.textSecondary,
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    orderCustomerLabel(order.customerName),
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                itemsLabel(
                  order.items.fold(0, (sum, item) => sum + item.quantity),
                ),
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.lg),
        Text(
          'Products',
          style: textTheme.titleSmall?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Container(
          decoration: BoxDecoration(
            color: context.appColors.surface,
            borderRadius: AppBorderRadius.lg,
            border: Border.all(color: context.appColors.divider),
          ),
          child: Column(
            children: [
              for (var i = 0; i < order.items.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _ItemRow(item: order.items[i]),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SummaryRow(
          label: 'Subtotal',
          amount: Money.formatPaise(order.subtotalPaise),
        ),
        const SizedBox(height: AppSpacing.xs),
        _SummaryRow(
          label: 'Total',
          amount: Money.formatPaise(order.totalPaise),
          emphasized: true,
        ),
      ],
    );
  }
}

final class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final OrderItem item;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: AppInsets.card,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.variantName == null
                      ? item.productName
                      : '${item.productName} — ${item.variantName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.sku != null) ...[
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    'SKU ${item.sku}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${Money.formatPaise(item.unitPricePaise)} × ${item.quantity}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  Money.formatPaise(item.lineTotalPaise),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.amount,
    this.emphasized = false,
  });

  final String label;
  final String amount;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: emphasized ? FontWeight.w700 : null,
            ),
          ),
        ),
        SizedBox(width: AppSpacing.sm),
        Text(
          amount,
          style: textTheme.bodyMedium?.copyWith(
            color: emphasized
                ? context.appColors.textPrimary
                : context.appColors.textSecondary,
            fontWeight: emphasized ? FontWeight.w800 : null,
          ),
        ),
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
        notPaid ? 'Not paid' : paymentMethodLabel(method!),
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
                'Could not load order',
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

/// Safe body for crafted deep links that carry no order summary.
final class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: AppInsets.screen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: AppSpacing.ultra,
              color: context.appColors.textDisabled,
            ),
            SizedBox(height: AppSpacing.lg),
            Text(
              'Order not found.',
              textAlign: TextAlign.center,
              style: textTheme.titleLarge?.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
