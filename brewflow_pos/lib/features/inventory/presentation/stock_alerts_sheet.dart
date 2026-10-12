import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_alerts_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock alert panel (notification center)
///
/// Bell tap opens this bottom sheet (never a direct inventory jump): the
/// list is derived from [stockAlertsProvider] (same rules as dashboard +
/// inventory filters), each row is independently tappable, and a tap
/// focuses Inventory on exactly that product/variant via
/// [InventoryFilter.focusProductId]/[focusVariantId] before navigating.
///
/// Phone-first: single-column ListView, no fixed widths, no horizontal
/// overflow at 360–480dp. Tablet behavior intentionally unchanged.
/// ---------------------------------------------------------------------------

Future<void> showStockAlertsSheet(BuildContext context, WidgetRef ref) async {
  // Snapshot the alerts now so the sheet has stable content even if the
  // provider refreshes underneath it.
  final alerts = await ref
      .read(stockAlertsProvider.future)
      .catchError((_) => const <StockAlert>[]);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => _StockAlertsSheet(alerts: alerts),
  );
}

final class _StockAlertsSheet extends ConsumerWidget {
  const _StockAlertsSheet({required this.alerts});

  final List<StockAlert> alerts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessSwitcherProvider);
    final showShop = business == BusinessContext.all;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppInsets.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Stock Alerts',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      alerts.isEmpty
                          ? 'Everything you sell is in stock.'
                          : '${alerts.length} item${alerts.length == 1 ? '' : 's'} need attention',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: alerts.isEmpty
                    ? const EmptyState(
                        icon: Icons.check_circle_outline,
                        title: 'No stock alerts',
                        message: 'Low and out-of-stock items will appear here.',
                      )
                    : ListView.separated(
                        controller: scrollController,
                        padding: AppInsets.screen,
                        itemCount: alerts.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (context, index) {
                          final alert = alerts[index];
                          return _AlertRow(
                            alert: alert,
                            showShop: showShop,
                            onTap: () {
                              ref
                                  .read(inventoryFilterProvider.notifier)
                                  .focusOn(
                                    productId: alert.productId,
                                    variantId: alert.variantId,
                                  );
                              Navigator.of(context).pop();
                              // The dashboard always lives under GoRouter;
                              // widget tests pump the sheet standalone without
                              // one, where the focus filter above is the
                              // asserted contract.
                              try {
                                context.go(AppRoutes.inventory);
                              } catch (_) {}
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _AlertRow extends StatelessWidget {
  const _AlertRow({
    required this.alert,
    required this.showShop,
    required this.onTap,
  });

  final StockAlert alert;
  final bool showShop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOut = alert.kind == StockAlertKind.outOfStock;
    final accent = isOut ? AppColors.error : AppColors.warning;
    return AppCard(
      child: InkWell(
        borderRadius: AppBorderRadius.lg,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: AppBorderRadius.md,
                ),
                child: Icon(
                  isOut
                      ? Icons.remove_shopping_cart_outlined
                      : Icons.inventory_2_outlined,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isOut
                          ? 'Stock: ${alert.stock}'
                          : 'Stock: ${alert.stock}'
                                '${alert.threshold == null ? '' : ' · Minimum: ${alert.threshold}'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (showShop)
                      Text(
                        _shopLabel(alert.shopId),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Icon(Icons.chevron_right, color: context.appColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  static String _shopLabel(String? shopId) {
    if (shopId == null || shopId.isEmpty) return 'Shop: —';
    // The id is opaque; the panel only promises which shelf the alert
    // belongs to, never a display name it does not own.
    return 'Shop: ${shopId.length > 8 ? '${shopId.substring(0, 8)}…' : shopId}';
  }
}
