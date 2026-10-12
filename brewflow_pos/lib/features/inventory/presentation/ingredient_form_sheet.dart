/// ---------------------------------------------------------------------------
/// BrewFlow POS — New Ingredient Form (bottom sheet)
///
/// Owner-only creation of a stock-source ingredient through the existing
/// product flow ([SharedStockOverviewController.createIngredient], which
/// calls `InventoryRepository.createProduct` with `isIngredient: true`).
///
/// Behaviour contract:
/// - name, scoped category and a tracked [StockUnit] (never NONE: untracked
///   products hold no stock, so no recipe could consume them).
/// - born with zero stock and no movements; the owner stocks it through
///   Purchases, exactly like the seeded Maggi Packet.
/// - same-name twins in the writable shop are refused with a clear message;
///   nothing is ever overwritten.
/// - cancelling (close, Cancel, back, drag) writes nothing.
/// - the save button is disabled while a save is in flight, so a double tap
///   can never submit twice.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Units an ingredient may count its stock in. `NONE` is excluded on
/// purpose: an untracked product holds no stock, so mapping it into a recipe
/// would fail every sale at checkout.
const List<StockUnit> ingredientStockUnits = [
  StockUnit.count,
  StockUnit.ml,
  StockUnit.gram,
  StockUnit.kg,
];

/// Opens the new-ingredient form. Returns true only when an ingredient was
/// created (the overview invalidates itself through the controller).
Future<bool> showIngredientFormSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final created = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const IngredientFormSheet(),
  );
  return created ?? false;
}

/// Owner-only ingredient creation form. Callers hide the entry point from
/// staff; the controller refuses non-owners regardless.
final class IngredientFormSheet extends ConsumerStatefulWidget {
  const IngredientFormSheet({super.key});

  @override
  ConsumerState<IngredientFormSheet> createState() =>
      _IngredientFormSheetState();
}

final class _IngredientFormSheetState
    extends ConsumerState<IngredientFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController();
  String? _categoryId;
  StockUnit _stockUnit = StockUnit.count;
  String? _formError;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final categories = ref.watch(categoriesProvider);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.5,
          maxChildSize: 0.94,
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
                            'New ingredient',
                            style: textTheme.titleLarge?.copyWith(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'A hidden stock source dishes consume per sale. '
                            'It starts at zero — stock it through Purchases.',
                            style: textTheme.bodySmall?.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: categories.when(
                  loading: () =>
                      const LoadingState(message: 'Loading categories…'),
                  error: (error, _) => ErrorState(
                    message: inventoryErrorMessage(error),
                    onRetry: () => ref.invalidate(categoriesProvider),
                  ),
                  data: (items) => Form(
                    key: _formKey,
                    child: ListView(
                      controller: scrollController,
                      padding: AppInsets.screen,
                      children: [
                        TextFormField(
                          controller: _name,
                          enabled: !_saving,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Ingredient name *',
                            hintText: 'e.g. Sugar',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? 'Give the ingredient a name.'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          initialValue: items.any((c) => c.id == _categoryId)
                              ? _categoryId
                              : null,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          hint: const Text('Select a category'),
                          items: [
                            for (final category in items)
                              DropdownMenuItem(
                                value: category.id,
                                child: Text(
                                  category.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _categoryId = value),
                          validator: (value) =>
                              value == null ? 'Select a category.' : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<StockUnit>(
                          initialValue: _stockUnit,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Stock unit *',
                            border: OutlineInputBorder(),
                            helperText:
                                'Ingredients must track stock: an untracked '
                                'product holds no stock, so no recipe could '
                                'consume it.',
                            helperMaxLines: 3,
                          ),
                          items: [
                            for (final unit in ingredientStockUnits)
                              DropdownMenuItem(
                                value: unit,
                                child: Text(
                                  unit.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _stockUnit = value ?? StockUnit.count,
                                ),
                        ),
                        if (_formError != null) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            _formError!,
                            style: textTheme.bodyMedium?.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.lg),
                        // Plain FilledButton (never .icon): the .icon factory
                        // builds a private subclass that byType finders miss.
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_saving)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              else
                                const Icon(Icons.check),
                              const SizedBox(width: AppSpacing.sm),
                              Text(_saving ? 'Adding…' : 'Add ingredient'),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Center(
                          child: TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.of(context).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    // Guarded twice (here and by disabling the button): a double tap must
    // never submit two creates.
    if (_saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final categoryId = _categoryId;
    if (categoryId == null) {
      setState(() => _formError = 'Select a category.');
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref
          .read(sharedStockOverviewProvider.notifier)
          .createIngredient(
            categoryId: categoryId,
            name: _name.text,
            stockUnit: _stockUnit,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      // The sheet stays open with the draft intact: the owner can fix the
      // problem (or cancel) without re-entering the name.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = inventoryErrorMessage(error);
      });
    }
  }
}
