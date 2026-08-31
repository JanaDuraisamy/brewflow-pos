import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock Movement History Page
///
/// The append-only audit trail for one stock entity: a product (product-level
/// movements only) or one of its variants. Newest first, with the signed
/// quantity change and the before → after stock snapshot per record.
/// ---------------------------------------------------------------------------

/// Navigation payload: the owning product and the optional variant whose
/// history should be shown (variant history when present).
final class StockHistoryArgs {
  StockHistoryArgs({required this.product, this.variant});

  final Product product;
  final ProductVariant? variant;
}

final class StockMovementHistoryPage extends ConsumerWidget {
  const StockMovementHistoryPage({super.key, this.args});

  final StockHistoryArgs? args;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final product = args?.product;
    if (product == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Stock History')),
        body: Center(
          child: Text(
            'No product selected.',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
        ),
      );
    }
    final variant = args!.variant;
    final unit = _unitSuffix(product.stockUnit);

    final movements = variant != null
        ? ref.watch(
            variantMovementsProvider((
              productId: product.id,
              variantId: variant.id,
            )),
          )
        : ref.watch(productMovementsProvider(product.id));

    final currentStock = variant?.stockQuantity ?? product.stockQuantity;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock History')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: AppInsets.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: textTheme.titleMedium?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
                if (variant != null) ...[
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    variant.name,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Current stock: $currentStock${unit.isEmpty ? '' : ' $unit'}',
                  style: textTheme.bodyMedium?.copyWith(
                    color: currentStock <= 0
                        ? AppColors.outOfStock
                        : context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.appColors.divider),
          Expanded(
            child: movements.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Padding(
                  padding: AppInsets.screen,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stockMovementErrorMessage(error),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                      SizedBox(height: AppSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () => ref.invalidate(
                          variant != null
                              ? variantMovementsProvider((
                                  productId: product.id,
                                  variantId: variant.id,
                                ))
                              : productMovementsProvider(product.id),
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              ),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text(
                        'No stock movements yet.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: AppInsets.screen,
                      itemCount: items.length,
                      separatorBuilder: (_, _) =>
                          SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) =>
                          _MovementTile(movement: items[index], unit: unit),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _MovementTile extends StatelessWidget {
  const _MovementTile({required this.movement, required this.unit});

  final StockMovement movement;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final added = movement.quantity > 0;
    final color = added ? AppColors.success : AppColors.error;
    final details = [
      if (movement.reason != null) stockAdjustmentReasonLabel(movement.reason!),
      if (movement.note != null) movement.note!,
    ].join(' · ');

    return Card(
      color: context.appColors.surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.md,
        side: BorderSide(color: context.appColors.divider),
      ),
      child: Padding(
        padding: AppInsets.card,
        child: Row(
          children: [
            Icon(_iconFor(movement.movementType), size: 28, color: color),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stockMovementTypeLabel(movement.movementType),
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    formatDateTime(movement.createdAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textDisabled,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${added ? '+' : ''}${movement.quantity} $unit'.trim(),
                  style: textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${movement.stockBefore} → ${movement.stockAfter}',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _iconFor(StockMovementType type) => switch (type) {
  StockMovementType.opening => Icons.play_circle_outline,
  StockMovementType.sale => Icons.receipt_long_outlined,
  StockMovementType.purchase => Icons.local_shipping_outlined,
  StockMovementType.adjustmentIn => Icons.add_circle_outline,
  StockMovementType.adjustmentOut => Icons.remove_circle_outline,
};

String _unitSuffix(StockUnit unit) => switch (unit) {
  StockUnit.ml => 'ml',
  StockUnit.gram => 'g',
  StockUnit.kg => 'kg',
  StockUnit.count || StockUnit.none => '',
};
