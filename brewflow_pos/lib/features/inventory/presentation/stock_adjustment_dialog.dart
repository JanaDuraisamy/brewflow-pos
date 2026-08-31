import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
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
                decoration: const InputDecoration(
                  labelText: 'Variant',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final variant in widget.product.variants)
                    DropdownMenuItem(value: variant, child: Text(variant.name)),
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
