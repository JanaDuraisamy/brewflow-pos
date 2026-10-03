/// ---------------------------------------------------------------------------
/// BrewFlow POS — Food Truck Stock Sheet
///
/// The Food Truck counterpart of `StockAdjustmentDialog`. A shared Cafe product
/// has no Food Truck stock of its own until the owner stocks it here, so this
/// sheet is where a shelf is created, corrected or removed.
///
/// Two rules drive the design:
///
///  * The Cafe's quantity is read-only here. This sheet writes the
///    `shop_product_stock` overlay, never `products.stock_quantity`, so a
///    correction in the truck can never move the Cafe's shelf.
///  * A product the truck does not carry reads back as zero, which is a
///    "stock it" prompt rather than an error — that is the difference between
///    [StockSource.notCarried] and an ordinary out-of-stock unit.
/// ---------------------------------------------------------------------------
library;

import 'dart:async';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/shop_product_stock_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/food_truck_stock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the Food Truck shelf editor for [product].
///
/// [shopId] must be the Food Truck's own id. The caller resolves it; this sheet
/// never guesses, because writing the Cafe's stock would be a silent data-loss
/// bug rather than a visible failure.
Future<void> showFoodTruckStockSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String shopId,
  required Product product,
  ProductVariant? variant,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => FoodTruckStockDialog(
      shopId: shopId,
      product: product,
      variant: variant,
    ),
  );
}

final class FoodTruckStockDialog extends ConsumerStatefulWidget {
  const FoodTruckStockDialog({
    super.key,
    required this.shopId,
    required this.product,
    this.variant,
  });

  /// The Food Truck business this shelf belongs to.
  final String shopId;

  final Product product;

  /// Preselected variant for variant products.
  final ProductVariant? variant;

  @override
  ConsumerState<FoodTruckStockDialog> createState() =>
      _FoodTruckStockDialogState();
}

final class _FoodTruckStockDialogState
    extends ConsumerState<FoodTruckStockDialog> {
  late final TextEditingController _quantity = TextEditingController();
  ProductVariant? _variant;
  EffectiveStock? _stock;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _variant =
        widget.variant ??
        (widget.product.variants.isEmpty
            ? null
            : widget.product.variants.firstWhere(
                (v) => v.isActive,
                orElse: () => widget.product.variants.first,
              ));
    unawaited(_load());
  }

  @override
  void dispose() {
    _quantity.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = ref.read(foodTruckStockControllerProvider);
    try {
      final stock = await controller.load(
        shopId: widget.shopId,
        productId: widget.product.id,
        variantId: _variant?.id,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _stock = stock;
        _quantity.text = stock.quantity.toString();
        _loading = false;
      });
    } on ShopStockFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = failure.message;
        _loading = false;
      });
    }
  }

  Future<void> _selectVariant(ProductVariant? variant) async {
    setState(() {
      _variant = variant;
      _error = null;
      _loading = true;
    });
    await _load();
  }

  Future<void> _save() async {
    final quantity = int.tryParse(_quantity.text.trim());
    if (quantity == null || quantity < 0) {
      setState(() => _error = 'Enter a quantity of zero or more.');
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(foodTruckStockControllerProvider)
          .upsertShelf(
            shopId: widget.shopId,
            productId: widget.product.id,
            variantId: _variant?.id,
            quantity: quantity,
          );
      invalidateShelfReaders(ref);
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Food Truck stock updated.')),
      );
    } on ShopStockFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    }
  }

  Future<void> _remove() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(foodTruckStockControllerProvider)
          .removeShelf(
            shopId: widget.shopId,
            productId: widget.product.id,
            variantId: _variant?.id,
          );
      invalidateShelfReaders(ref);
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(content: Text('Removed from the Food Truck.')),
      );
    } on ShopStockFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = failure.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final stock = _stock;
    final notCarried = stock?.source == StockSource.notCarried;

    return AlertDialog(
      title: const Text('Food Truck Stock'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.product.name,
              style: textTheme.titleSmall?.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Cafe stock: ${widget.product.stockQuantity}',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Text(
                'Food Truck stock: ${stock?.quantity ?? 0}',
                style: textTheme.bodyMedium?.copyWith(
                  color: notCarried
                      ? AppColors.error
                      : context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (notCarried) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Not stocked in this business yet. Set a quantity to carry it.',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
              if (widget.product.variants.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<ProductVariant>(
                  initialValue: _variant,
                  // Fill the sheet width so long variant names ellipsize.
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Variant',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final variant in widget.product.variants)
                      DropdownMenuItem(
                        value: variant,
                        child: Text(
                          variant.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _selectVariant,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _quantity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (_) => setState(() => _error = null),
                decoration: InputDecoration(
                  labelText: 'Quantity',
                  helperText: 'This changes the Food Truck only',
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppBorderRadius.md,
                    borderSide: BorderSide(color: context.appColors.divider),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: AppColors.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting || _loading
              ? null
              : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        if (stock != null && !notCarried)
          TextButton(
            onPressed: _submitting ? null : _remove,
            child: const Text('Remove'),
          ),
        FilledButton(
          onPressed: _submitting || _loading ? null : _save,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
