import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/food_truck_stock_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Adjust Stock Dialog
///
/// The manual inventory adjustment UI: pick a direction (in/out), a quantity,
/// a reason and an optional note, preview the resulting stock, then confirm
/// through [ProductMovementsController.adjustStock] (Step 8). The controller
/// refreshes the product list, the dashboard and the movement history on
/// success. Failures surface as inline, user-safe messages and keep the dialog
/// open; Cancel never touches stock.
///
/// The preview is advisory: a negative result disables the confirm button with
/// the same message the repository would use, and a repository rejection (e.g.
/// stock changed since the dialog opened) is still surfaced verbatim.
/// ---------------------------------------------------------------------------

enum _StockDirection { stockIn, stockOut }

final class StockAdjustmentDialog extends ConsumerStatefulWidget {
  const StockAdjustmentDialog({super.key, required this.product, this.variant});

  final Product product;

  /// Preselected variant for variant products; when null and the product has
  /// variants, the first active variant is chosen automatically.
  final ProductVariant? variant;

  @override
  ConsumerState<StockAdjustmentDialog> createState() =>
      StockAdjustmentDialogState();
}

final class StockAdjustmentDialogState
    extends ConsumerState<StockAdjustmentDialog> {
  _StockDirection _direction = _StockDirection.stockIn;
  late final TextEditingController _quantity = TextEditingController();
  late final TextEditingController _note = TextEditingController();
  late ProductVariant? _variant =
      widget.variant ??
      (widget.product.variants.isEmpty
          ? null
          : widget.product.variants.firstWhere(
              (v) => v.isActive,
              orElse: () => widget.product.variants.first,
            ));
  StockAdjustmentReason? _reason;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _quantity.dispose();
    _note.dispose();
    super.dispose();
  }

  int get _currentStock =>
      _variant?.stockQuantity ?? widget.product.stockQuantity;

  Future<void> _submit() async {
    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
    if (quantity <= 0) {
      setState(() => _error = 'Enter a quantity greater than zero.');
      return;
    }
    final reason = _reason;
    if (reason == null) {
      setState(() => _error = 'Select a reason.');
      return;
    }
    final delta = _direction == _StockDirection.stockIn ? quantity : -quantity;
    final messenger = ScaffoldMessenger.of(context);
    final note = _note.text.trim();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (_variant != null) {
        await ref
            .read(
              variantMovementsProvider((
                productId: widget.product.id,
                variantId: _variant!.id,
              )).notifier,
            )
            .adjustStock(
              delta: delta,
              reason: reason,
              note: note.isEmpty ? null : note,
            );
      } else {
        await ref
            .read(productMovementsProvider(widget.product.id).notifier)
            .adjustStock(
              delta: delta,
              reason: reason,
              note: note.isEmpty ? null : note,
            );
      }
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Stock adjusted.')));
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _error = stockMovementErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final quantity = int.tryParse(_quantity.text.trim()) ?? 0;
    final delta = _direction == _StockDirection.stockIn ? quantity : -quantity;
    final newStock = _currentStock + delta;
    final insufficient = newStock < 0;
    final confirming = _submitting || insufficient;

    return AlertDialog(
      title: const Text('Adjust Stock'),
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
            if (_variant != null) ...[
              SizedBox(height: AppSpacing.xs),
              Text(
                _variant!.name,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
            SizedBox(height: AppSpacing.xs),
            Text(
              'Current stock: $_currentStock',
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            if (widget.product.variants.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<ProductVariant>(
                initialValue: _variant,
                // Fill the dialog width so long variant names ellipsize.
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
                onChanged: (variant) => setState(() {
                  _variant = variant;
                  _error = null;
                }),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<_StockDirection>(
              segments: const [
                ButtonSegment(
                  value: _StockDirection.stockIn,
                  label: Text('Stock In'),
                ),
                ButtonSegment(
                  value: _StockDirection.stockOut,
                  label: Text('Stock Out'),
                ),
              ],
              selected: {_direction},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() {
                _direction = selection.first;
                _error = null;
              }),
            ),
            SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() => _error = null),
              decoration: InputDecoration(
                labelText: 'Quantity',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppBorderRadius.md,
                  borderSide: BorderSide(color: context.appColors.divider),
                ),
              ),
            ),
            SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<StockAdjustmentReason>(
              initialValue: null,
              // Fill the dialog width like every other form dropdown.
              isExpanded: true,
              items: [
                for (final reason in StockAdjustmentReason.values)
                  DropdownMenuItem(
                    value: reason,
                    child: Text(stockAdjustmentReasonLabel(reason)),
                  ),
              ],
              onChanged: (reason) => setState(() {
                _reason = reason;
                _error = null;
              }),
              decoration: InputDecoration(
                labelText: 'Reason',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppBorderRadius.md,
                  borderSide: BorderSide(color: context.appColors.divider),
                ),
              ),
            ),
            SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(
                labelText: 'Note (optional)',
                border: const OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppBorderRadius.md,
                  borderSide: BorderSide(color: context.appColors.divider),
                ),
              ),
            ),
            SizedBox(height: AppSpacing.md),
            Text(
              'New stock: $newStock',
              style: textTheme.bodyMedium?.copyWith(
                color: insufficient
                    ? AppColors.error
                    : context.appColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (insufficient) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                stockMovementErrorMessage(
                  const AdjustmentInsufficientStockFailure(),
                ),
                style: textTheme.bodySmall?.copyWith(color: AppColors.error),
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
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: confirming ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Adjust'),
        ),
      ],
    );
  }
}

/// Opens the stock editor for [product] in the active business.
///
/// The two businesses keep separate stock, so the editor has to route: a Cafe
/// product adjust writes `products.stock_quantity`, while a product the Cafe
/// shares into the Food Truck has no truck stock of its own and must be edited
/// through the `shop_product_stock` overlay instead. Sending a shared product
/// down the Cafe path is how a truck adjustment would silently move the Cafe's
/// shelf, so the routing is explicit rather than inferred from the UI.
///
/// Fails closed whenever no single concrete shop can be named, because a stock
/// write is a movement row plus a quantity update and both are irreversible
/// from the user's point of view:
///
///  * `BusinessContext.all` is a read-only view spanning two independent
///    shelves. There is no correct shelf to write, so guessing Cafe would move
///    the Cafe's stock on a tap the user made while looking at both.
///  * Food Truck with no persisted truck id has no shelf to move. Falling
///    through to the Cafe path would let a truck action edit Cafe stock.
Future<void> showStockAdjustmentDialog(
  BuildContext context,
  WidgetRef ref,
  Product product, {
  ProductVariant? variant,
}) async {
  final switcher = ref.read(businessSwitcherProvider.notifier);
  final business = ref.watch(businessSwitcherProvider);
  if (business == BusinessContext.all) {
    showAmbiguousScopeNotice(context);
    return;
  }
  if (business == BusinessContext.foodTruck) {
    final truckShopId = await switcher.existingFoodTruckShopId();
    if (!context.mounted) return;
    if (truckShopId == null) {
      // No persisted truck: there is no Food Truck shelf to move, and the Cafe
      // path would write the wrong business. Refuse rather than guess.
      showAmbiguousScopeNotice(context);
      return;
    }
    // A product the truck owns outright edits its own stock row, exactly like
    // the Cafe. Only a shared product needs the overlay editor.
    if (product.shopId == truckShopId) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) =>
            StockAdjustmentDialog(product: product, variant: variant),
      );
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => FoodTruckStockDialog(
        shopId: truckShopId,
        product: product,
        variant: variant,
      ),
    );
    return;
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => StockAdjustmentDialog(product: product, variant: variant),
  );
}

/// Explains, in the user's own terms, why stock cannot be edited right now.
///
/// Deliberately not an error dialog: nothing failed, and the fix is on screen
/// already (pick the single business, or let the Food Truck finish setting up).
void showAmbiguousScopeNotice(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text(
        'Pick a single business to adjust stock. The All businesses view is '
        'read-only, and stock is kept separately for the Cafe and the '
        'Food Truck.',
      ),
    ),
  );
}
