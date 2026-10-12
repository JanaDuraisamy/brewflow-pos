/// ---------------------------------------------------------------------------
/// BrewFlow POS — Recipe Mapping Editor (bottom sheet)
///
/// Owner-only editor for one dish + variant scope: pick the sellable dish,
/// optionally narrow to one variant, then map tracked ingredients with
/// per-serving quantities. Writes go through
/// [SharedStockOverviewController.saveRecipe]/[clearRecipe], which enforce
/// ownership, write scoping and overlap rules — the sheet itself only
/// explains problems early, in the user's terms.
///
/// Behaviour contract:
/// - saving over an existing mapping always shows an explicit old-vs-new
///   summary confirmation first; only the edited scope is replaced.
/// - clearing is offered only when the scope already has a mapping, and only
///   after an explicit destructive confirmation.
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

/// What the editor finished with. `saved` and `cleared` both mean the
/// overview was invalidated and will refetch; `dismissed` means nothing was
/// written.
enum RecipeEditorOutcome { saved, cleared, dismissed }

/// Opens the recipe editor for [dishId] + [variantId] (both null for a blank
/// form). Returns how the sheet closed.
Future<RecipeEditorOutcome> showRecipeEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  String? dishId,
  String? variantId,
}) async {
  final outcome = await showModalBottomSheet<RecipeEditorOutcome>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => RecipeEditorSheet(dishId: dishId, variantId: variantId),
  );
  return outcome ?? RecipeEditorOutcome.dismissed;
}

/// Owner-only recipe mapping editor. Callers hide the entry points from
/// staff; the controller refuses non-owners regardless.
final class RecipeEditorSheet extends ConsumerStatefulWidget {
  const RecipeEditorSheet({super.key, this.dishId, this.variantId});

  /// Preselected dish, resolved against the scoped catalogue on open.
  final String? dishId;

  /// Preselected variant scope (null = every variant).
  final String? variantId;

  @override
  ConsumerState<RecipeEditorSheet> createState() => _RecipeEditorSheetState();
}

final class _DraftLine {
  _DraftLine({
    required this.ingredient,
    this.ingredientVariantId,
    this.quantity = 1,
  });

  final Product ingredient;
  String? ingredientVariantId;
  int quantity;
}

final class _RecipeEditorSheetState extends ConsumerState<RecipeEditorSheet> {
  Product? _dish;
  String? _variantId;
  final List<_DraftLine> _lines = [];
  List<SharedStockRecipeLine>? _existing;
  String? _existingError;
  bool _loadingExisting = false;
  String? _formError;
  String? _notice;
  bool _saving = false;
  bool _clearing = false;
  bool _presetResolved = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _variantId = widget.variantId;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final catalogue = ref.watch(sharedStockCatalogueProvider);
    // Resolve a preselected dish once the scoped catalogue arrives. The
    // post-frame callback keeps the synchronous build pure; a dish that is
    // no longer in scope surfaces as a notice instead of a silent blank.
    catalogue.whenData((data) {
      if (_presetResolved || widget.dishId == null) return;
      _presetResolved = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Product? dish;
        for (final sellable in data.sellables) {
          if (sellable.id == widget.dishId) dish = sellable;
        }
        setState(() {
          if (dish == null) {
            _notice =
                'The preselected dish is not available in the active '
                'business. Pick a dish below.';
          } else {
            _dish = dish;
            if (_variantId != null &&
                !dish.variants.any((variant) => variant.id == _variantId)) {
              _notice =
                  'The preselected variant is not part of ${dish.name}. '
                  'Pick a scope below.';
              _variantId = null;
            }
          }
        });
        if (dish != null) _loadExisting();
      });
    });

    final isNew = (_existing ?? const []).isEmpty;
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
                            isNew ? 'New recipe' : 'Edit recipe',
                            style: textTheme.titleLarge?.copyWith(
                              color: context.appColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'One dish uses tracked ingredients per sale. '
                            'Only this dish changes — every other recipe '
                            'stays exactly as it is.',
                            style: textTheme.bodySmall?.copyWith(
                              color: context.appColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: _saving || _clearing
                          ? null
                          : () => Navigator.of(
                              context,
                            ).pop(RecipeEditorOutcome.dismissed),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: catalogue.when(
                  loading: () => const LoadingState(
                    message: 'Loading dishes and ingredients…',
                  ),
                  error: (error, _) => ErrorState(
                    message: inventoryErrorMessage(error),
                    onRetry: () => ref.invalidate(sharedStockCatalogueProvider),
                  ),
                  data: (data) => ListView(
                    controller: scrollController,
                    padding: AppInsets.screen,
                    children: [
                      if (_notice != null) ...[
                        _NoticeCard(message: _notice!),
                        const SizedBox(height: AppSpacing.md),
                      ],
                      _DishSection(
                        dish: _dish,
                        variantId: _variantId,
                        disabled: _saving || _clearing,
                        onPickDish: () => _pickDish(data),
                        onPickScope: (value) {
                          setState(() => _variantId = value);
                          _loadExisting();
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _CurrentMappingCard(
                        dish: _dish,
                        variantId: _variantId,
                        loading: _loadingExisting,
                        error: _existingError,
                        existing: _existing,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _IngredientsCard(
                        lines: _lines,
                        disabled: _saving || _clearing,
                        onAdd: () => _pickIngredient(data),
                        onRemove: (line) => setState(() => _lines.remove(line)),
                        onQuantityChanged: (line, quantity) =>
                            setState(() => line.quantity = quantity),
                        onVariantChanged: (line, value) =>
                            setState(() => line.ingredientVariantId = value),
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
                        onPressed: _saving || _clearing ? null : _save,
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
                            Text(_saving ? 'Saving…' : 'Save recipe'),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          if (!isNew)
                            TextButton(
                              onPressed: _saving || _clearing ? null : _clear,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_clearing)
                                    const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  else
                                    const Icon(
                                      Icons.delete_outline,
                                      color: AppColors.error,
                                    ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    _clearing ? 'Clearing…' : 'Clear recipe',
                                    style: const TextStyle(
                                      color: AppColors.error,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          TextButton(
                            onPressed: _saving || _clearing
                                ? null
                                : () => Navigator.of(
                                    context,
                                  ).pop(RecipeEditorOutcome.dismissed),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDish(SharedStockCatalogue catalogue) async {
    if (_saving || _clearing) return;
    final dish = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DishPickerSheet(dishes: catalogue.sellables),
    );
    if (dish == null || !mounted) return;
    setState(() {
      _dish = dish;
      _variantId = null;
      _prefilled = true;
      _formError = null;
      _notice = null;
    });
    await _loadExisting();
  }

  Future<void> _pickIngredient(SharedStockCatalogue catalogue) async {
    if (_saving || _clearing) return;
    final taken = {for (final line in _lines) line.ingredient.id};
    if (_dish != null) taken.add(_dish!.id);
    final ingredient = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _IngredientPickerSheet(
        ingredients: [
          for (final item in catalogue.ingredients)
            if (!taken.contains(item.id)) item,
        ],
      ),
    );
    if (ingredient == null || !mounted) return;
    setState(() {
      _lines.add(_DraftLine(ingredient: ingredient));
      _formError = null;
    });
  }

  Future<void> _loadExisting() async {
    final dish = _dish;
    if (dish == null) {
      setState(() {
        _existing = const [];
        _existingError = null;
      });
      return;
    }
    setState(() {
      _loadingExisting = true;
      _existingError = null;
    });
    try {
      final rows = await ref
          .read(sharedStockOverviewProvider.notifier)
          .existingRecipe(productId: dish.id, variantId: _variantId);
      if (!mounted) return;
      setState(() {
        _existing = rows;
        _loadingExisting = false;
      });
      _maybePrefill(rows);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _existing = const [];
        _existingError = inventoryErrorMessage(error);
        _loadingExisting = false;
      });
    }
  }

  /// Prefills the form from the current mapping once, so an edit starts from
  /// what checkout actually deducts today. Rows whose ingredient has left
  /// the visible catalogue cannot be represented faithfully, so the form
  /// stays empty and a notice explains why instead of silently dropping a
  /// line the owner never saw.
  void _maybePrefill(List<SharedStockRecipeLine> rows) {
    if (_prefilled || _lines.isNotEmpty) return;
    _prefilled = true;
    if (rows.isEmpty) return;
    final catalogue = ref.read(sharedStockCatalogueProvider).value;
    if (catalogue == null) return;
    final byId = <String, Product>{
      for (final item in catalogue.ingredients) item.id: item,
    };
    final prefilled = <_DraftLine>[];
    for (final row in rows) {
      final ingredient = byId[row.ingredientProductId];
      if (ingredient == null) {
        if (!mounted) return;
        setState(() {
          _notice =
              'One mapped ingredient is outside the active business, so the '
              'form starts empty. Saving here would replace that hidden '
              'mapping — switch business to edit it instead.';
        });
        return;
      }
      prefilled.add(
        _DraftLine(
          ingredient: ingredient,
          ingredientVariantId: row.ingredientVariantId,
          quantity: row.quantity,
        ),
      );
    }
    if (!mounted) return;
    setState(() => _lines.addAll(prefilled));
  }

  Future<void> _save() async {
    // Guarded twice (here and by disabling the button): a double tap must
    // never submit two writes, and setRecipe's replace semantics would make
    // the second a silent no-op anyway.
    if (_saving || _clearing) return;
    final dish = _dish;
    if (dish == null) {
      setState(() => _formError = 'Choose a dish first.');
      return;
    }
    final catalogue = ref.read(sharedStockCatalogueProvider).value;
    if (catalogue == null) {
      setState(() => _formError = 'The catalogue is still loading. Try again.');
      return;
    }
    final byId = <String, Product>{
      for (final item in catalogue.sellables) item.id: item,
      for (final item in catalogue.ingredients) item.id: item,
    };
    final inputs = [
      for (final line in _lines)
        RecipeIngredientInput(
          ingredientProductId: line.ingredient.id,
          ingredientVariantId: line.ingredientVariantId,
          quantity: line.quantity,
        ),
    ];
    final problem = validateRecipeDraft(
      dish: dish,
      variantId: _variantId,
      lines: inputs,
      catalogueById: byId,
    );
    if (problem != null) {
      setState(() => _formError = problem);
      return;
    }
    final existing = _existing ?? const <SharedStockRecipeLine>[];
    if (existing.isNotEmpty) {
      final confirmed = await _confirmReplace(dish, existing, inputs, byId);
      if (!confirmed || !mounted) return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref
          .read(sharedStockOverviewProvider.notifier)
          .saveRecipe(productId: dish.id, variantId: _variantId, lines: inputs);
      if (!mounted) return;
      Navigator.of(context).pop(RecipeEditorOutcome.saved);
    } catch (error) {
      // The sheet stays open with the draft intact: the owner can fix the
      // problem (or cancel) without re-entering every line.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = inventoryErrorMessage(error);
      });
    }
  }

  /// Explicit old-vs-new summary before a replace: the owner sees exactly
  /// which rows disappear and which appear, for exactly which scope.
  Future<bool> _confirmReplace(
    Product dish,
    List<SharedStockRecipeLine> existing,
    List<RecipeIngredientInput> inputs,
    Map<String, Product> byId,
  ) {
    final scope = _variantId == null
        ? 'every variant'
        : _scopeName(dish, _variantId!);
    String describeExisting(SharedStockRecipeLine row) {
      final variant = row.ingredientVariantName == null
          ? ''
          : ' — ${row.ingredientVariantName}';
      final unit = row.unitLabel.isEmpty ? '' : ' ${row.unitLabel}';
      return '• ${row.ingredientName}$variant ×${row.quantity}$unit';
    }

    String describeNew(RecipeIngredientInput input) {
      final ingredient = byId[input.ingredientProductId];
      final name = ingredient?.name ?? input.ingredientProductId;
      var variant = '';
      var unit = '';
      if (ingredient != null) {
        if (input.ingredientVariantId != null) {
          for (final v in ingredient.variants) {
            if (v.id == input.ingredientVariantId) variant = ' — ${v.name}';
          }
        }
        unit = ' ${ingredient.stockUnit.label}';
      }
      return '• $name$variant ×${input.quantity}$unit';
    }

    return confirmDestructive(
      context,
      title: 'Replace recipe?',
      subject: '${dish.name} — $scope',
      consequence:
          'Current mapping:\n${existing.map(describeExisting).join('\n')}\n\n'
          'New mapping:\n${inputs.map(describeNew).join('\n')}\n\n'
          'Only this dish changes. Every other recipe stays as it is.',
      confirmLabel: 'Replace recipe',
    );
  }

  Future<void> _clear() async {
    if (_saving || _clearing) return;
    final dish = _dish;
    if (dish == null || (_existing ?? const []).isEmpty) return;
    final scope = _variantId == null
        ? 'every variant'
        : _scopeName(dish, _variantId!);
    final confirmed = await confirmDestructive(
      context,
      title: 'Clear recipe?',
      subject: '${dish.name} — $scope',
      consequence:
          'The dish will sell from its own stock again. This cannot be '
          'undone.',
      confirmLabel: 'Clear recipe',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _clearing = true;
      _formError = null;
    });
    try {
      await ref
          .read(sharedStockOverviewProvider.notifier)
          .clearRecipe(productId: dish.id, variantId: _variantId);
      if (!mounted) return;
      Navigator.of(context).pop(RecipeEditorOutcome.cleared);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clearing = false;
        _formError = inventoryErrorMessage(error);
      });
    }
  }

  String _scopeName(Product dish, String variantId) {
    for (final variant in dish.variants) {
      if (variant.id == variantId) return variant.name;
    }
    return 'this variant';
  }
}

final class _NoticeCard extends StatelessWidget {
  const _NoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: context.appColors.textSecondary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final class _DishSection extends StatelessWidget {
  const _DishSection({
    required this.dish,
    required this.variantId,
    required this.disabled,
    required this.onPickDish,
    required this.onPickScope,
  });

  final Product? dish;
  final String? variantId;
  final bool disabled;
  final VoidCallback onPickDish;
  final ValueChanged<String?> onPickScope;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = dish;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dish',
            style: textTheme.titleMedium?.copyWith(
              color: context.appColors.charcoal,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: disabled ? null : onPickDish,
            icon: const Icon(Icons.restaurant_menu_outlined),
            label: Text(selected?.name ?? 'Choose dish'),
          ),
          if (selected != null && selected.variants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Applies to',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: variantId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Every variant'),
                    ),
                    for (final variant in selected.variants)
                      DropdownMenuItem<String?>(
                        value: variant.id,
                        child: Text(variant.name),
                      ),
                  ],
                  onChanged: disabled ? null : onPickScope,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final class _CurrentMappingCard extends StatelessWidget {
  const _CurrentMappingCard({
    required this.dish,
    required this.variantId,
    required this.loading,
    required this.error,
    required this.existing,
  });

  final Product? dish;
  final String? variantId;
  final bool loading;
  final String? error;
  final List<SharedStockRecipeLine>? existing;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final selected = dish;
    Widget body;
    if (selected == null) {
      body = Text(
        'Pick a dish to see its current mapping.',
        style: textTheme.bodyMedium?.copyWith(color: appColors.textSecondary),
      );
    } else if (loading) {
      body = const LinearProgressIndicator(color: AppColors.primary);
    } else if (error != null) {
      body = Text(
        error!,
        style: textTheme.bodyMedium?.copyWith(color: AppColors.error),
      );
    } else if (existing == null || existing!.isEmpty) {
      body = Text(
        'No recipe for this scope yet — saving creates one.',
        style: textTheme.bodyMedium?.copyWith(color: appColors.textSecondary),
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in existing!)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(_describe(row), style: textTheme.bodyMedium),
            ),
        ],
      );
    }
    return SectionCard(
      title: 'Current mapping',
      subtitle: selected == null
          ? null
          : variantId == null
          ? '${selected.name} — every variant'
          : '${selected.name} — ${_scopeName(selected, variantId)}',
      child: body,
    );
  }

  String _describe(SharedStockRecipeLine row) {
    final variant = row.ingredientVariantName == null
        ? ''
        : ' — ${row.ingredientVariantName}';
    final unit = row.unitLabel.isEmpty ? '' : ' ${row.unitLabel}';
    return '${row.ingredientName}$variant ×${row.quantity}$unit';
  }

  String _scopeName(Product dish, String? variantId) {
    for (final variant in dish.variants) {
      if (variant.id == variantId) return variant.name;
    }
    return 'this variant';
  }
}

final class _IngredientsCard extends StatelessWidget {
  const _IngredientsCard({
    required this.lines,
    required this.disabled,
    required this.onAdd,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onVariantChanged,
  });

  final List<_DraftLine> lines;
  final bool disabled;
  final VoidCallback onAdd;
  final ValueChanged<_DraftLine> onRemove;
  final void Function(_DraftLine line, int quantity) onQuantityChanged;
  final void Function(_DraftLine line, String? variantId) onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Ingredients',
      subtitle: lines.isEmpty
          ? 'Each sale consumes these per serving.'
          : '${lines.length} ${lines.length == 1 ? 'ingredient' : 'ingredients'} per serving.',
      trailing: OutlinedButton.icon(
        onPressed: disabled ? null : onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      child: lines.isEmpty
          ? Text(
              'No ingredients yet. Add at least one tracked ingredient.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            )
          : Column(
              children: [
                for (final line in lines)
                  _DraftLineRow(
                    line: line,
                    disabled: disabled,
                    onRemove: () => onRemove(line),
                    onQuantityChanged: (quantity) =>
                        onQuantityChanged(line, quantity),
                    onVariantChanged: (value) => onVariantChanged(line, value),
                  ),
              ],
            ),
    );
  }
}

final class _DraftLineRow extends StatelessWidget {
  const _DraftLineRow({
    required this.line,
    required this.disabled,
    required this.onRemove,
    required this.onQuantityChanged,
    required this.onVariantChanged,
  });

  final _DraftLine line;
  final bool disabled;
  final VoidCallback onRemove;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<String?> onVariantChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final ingredient = line.ingredient;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ingredient.name,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${ingredient.stockQuantity} ${ingredient.stockUnit.label} in stock',
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Decrease',
                onPressed: disabled || line.quantity <= 1
                    ? null
                    : () => onQuantityChanged(line.quantity - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '×${line.quantity} ${ingredient.stockUnit.label}',
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              IconButton(
                tooltip: 'Increase',
                onPressed: disabled
                    ? null
                    : () => onQuantityChanged(line.quantity + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              IconButton(
                tooltip: 'Remove ingredient',
                onPressed: disabled ? null : onRemove,
                icon: const Icon(Icons.close, color: AppColors.error),
              ),
            ],
          ),
          if (ingredient.variants.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Use stock of',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: line.ingredientVariantId,
                  isExpanded: true,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Product-level stock'),
                    ),
                    for (final variant in ingredient.variants)
                      DropdownMenuItem<String?>(
                        value: variant.id,
                        child: Text(variant.name),
                      ),
                  ],
                  onChanged: disabled ? null : onVariantChanged,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Sellable-dish picker: search + list, returns the tapped dish.
final class _DishPickerSheet extends StatefulWidget {
  const _DishPickerSheet({required this.dishes});

  final List<Product> dishes;

  @override
  State<_DishPickerSheet> createState() => _DishPickerSheetState();
}

final class _DishPickerSheetState extends State<_DishPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Choose dish',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SearchField(controller: _search, hintText: 'Search dishes'),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _search,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
                  final matches = [
                    for (final dish in widget.dishes)
                      if (query.isEmpty ||
                          dish.name.toLowerCase().contains(query))
                        dish,
                  ];
                  if (matches.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? 'No dishes available to map.'
                            : 'No dishes match your search.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: AppInsets.screen,
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final dish = matches[index];
                      return ListTile(
                        title: Text(dish.name),
                        subtitle: dish.variants.isEmpty
                            ? null
                            : Text(
                                '${dish.variants.length} ${dish.variants.length == 1 ? 'variant' : 'variants'}',
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).pop(dish),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tracked-ingredient picker: search + list with stock, returns the tapped
/// ingredient. Already-added ingredients and the dish itself are excluded by
/// the caller.
final class _IngredientPickerSheet extends StatefulWidget {
  const _IngredientPickerSheet({required this.ingredients});

  final List<Product> ingredients;

  @override
  State<_IngredientPickerSheet> createState() => _IngredientPickerSheetState();
}

final class _IngredientPickerSheetState extends State<_IngredientPickerSheet> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Add ingredient',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Only tracked ingredients are listed.',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SearchField(
                    controller: _search,
                    hintText: 'Search ingredients',
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: _search,
                builder: (context, value, _) {
                  final query = value.text.trim().toLowerCase();
                  final matches = [
                    for (final ingredient in widget.ingredients)
                      if (query.isEmpty ||
                          ingredient.name.toLowerCase().contains(query))
                        ingredient,
                  ];
                  if (matches.isEmpty) {
                    return Center(
                      child: Text(
                        query.isEmpty
                            ? 'No tracked ingredients yet.'
                            : 'No ingredients match your search.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: context.appColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scrollController,
                    padding: AppInsets.screen,
                    itemCount: matches.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ingredient = matches[index];
                      return ListTile(
                        title: Text(ingredient.name),
                        subtitle: Text(
                          '${ingredient.stockQuantity} ${ingredient.stockUnit.label} in stock',
                        ),
                        trailing: const Icon(Icons.add),
                        onTap: () => Navigator.of(context).pop(ingredient),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
