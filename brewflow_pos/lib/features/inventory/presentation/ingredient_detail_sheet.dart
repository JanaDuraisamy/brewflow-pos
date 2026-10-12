/// ---------------------------------------------------------------------------
/// BrewFlow POS — Ingredient Detail (bottom sheet)
///
/// Read-only audit surface for one stock-source ingredient: current stock in
/// its own unit, the dishes consuming it, and links into the EXISTING
/// workflows that move its stock — history, purchase receiving and manual
/// adjustment. Nothing here writes stock directly; every movement goes
/// through the flow it has always gone through, with that flow's own
/// permissions and guards.
///
/// Opened only from owner-gated entries on [SharedStockPage]; a deep-linked
/// staff session never reaches it from the UI.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_adjustment_dialog.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_history_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Shows [entry] with links to its history, purchase and adjust flows.
Future<void> showIngredientDetailSheet(
  BuildContext context,
  WidgetRef ref,
  SharedStockIngredient entry,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => IngredientDetailSheet(entry: entry),
  );
}

final class IngredientDetailSheet extends ConsumerWidget {
  const IngredientDetailSheet({super.key, required this.entry});

  final SharedStockIngredient entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final product = entry.product;
    final consumerCount = entry.consumers.length;
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.name,
                            style: textTheme.titleLarge?.copyWith(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            '${product.stockQuantity} ${product.stockUnit.label} '
                            'in stock · $consumerCount '
                            '${consumerCount == 1 ? 'dish' : 'dishes'}',
                            style: textTheme.bodySmall?.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: AppInsets.screen,
                  children: [
                    if (entry.consumers.isEmpty)
                      Text(
                        'No dishes use this ingredient yet.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      )
                    else ...[
                      Text(
                        'Used by',
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      for (final consumer in entry.consumers)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  consumer.variantName == null
                                      ? consumer.productName
                                      : '${consumer.productName} — ${consumer.variantName}',
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                '×${consumer.quantityPerSale} ${consumer.unitLabel}',
                                style: textTheme.bodySmall?.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    SecondaryButton(
                      label: 'View stock history',
                      icon: Icons.history_outlined,
                      expanded: true,
                      onPressed: () => context.push(
                        AppRoutes.productStockHistory,
                        extra: StockHistoryArgs(product: product),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SecondaryButton(
                      label: 'Record purchase',
                      icon: Icons.shopping_cart_outlined,
                      expanded: true,
                      onPressed: () => context.push(AppRoutes.purchaseNew),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    SecondaryButton(
                      label: 'Adjust stock',
                      icon: Icons.swap_vert,
                      expanded: true,
                      onPressed: () async {
                        // The shared router picks the Cafe dialog or the
                        // Food Truck overlay editor and fails closed outside
                        // a single business — exactly like Inventory.
                        await showStockAdjustmentDialog(context, ref, product);
                        // The adjustment refreshes the product list, but this
                        // overview watches the repository directly, so it is
                        // invalidated explicitly to show the new stock.
                        if (context.mounted) {
                          ref.invalidate(sharedStockOverviewProvider);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
