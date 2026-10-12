/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Stock Overview + Recipe Editor entry points
///
/// Shows the stock-source ingredients visible to the active business and the
/// sellable products that consume them, derived from the existing recipe
/// mappings. Owners can add or edit a mapping through [RecipeEditorSheet];
/// every write replaces only the edited dish + variant scope, so the seed
/// guards and checkout/void deduction behaviour are untouched.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/inventory/presentation/ingredient_detail_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/ingredient_form_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/recipe_editor_sheet.dart';
import 'package:brewflow_pos/features/inventory/presentation/shared_stock_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared-stock (ingredient/recipe) overview with owner-only editor entries.
///
/// Reached from the owner-only "Shared Stock" action on [InventoryPage]; the
/// route itself inherits the inventory `viewInventory` permission guard, so
/// the editor entries stay owner-gated here while the controller refuses
/// non-owners regardless of how it is reached.
final class SharedStockPage extends ConsumerStatefulWidget {
  const SharedStockPage({super.key});

  @override
  ConsumerState<SharedStockPage> createState() => _SharedStockPageState();
}

final class _SharedStockPageState extends ConsumerState<SharedStockPage> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(sharedStockOverviewProvider);
    // Editor entries are owner-only in the UI; the controller's requireOwner
    // gate is the real protection, so a deep-linked staff session can read
    // this page but never opens the sheet.
    final isOwner = ref.watch(userProfileProvider).value?.isOwner ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shared Stock'),
        actions: [
          if (isOwner) ...[
            IconButton(
              tooltip: 'New ingredient',
              onPressed: () => _openIngredientForm(),
              icon: const Icon(Icons.add_box_outlined),
            ),
            IconButton(
              tooltip: 'New recipe',
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
            ),
          ],
        ],
      ),
      body: overview.when(
        loading: () => const LoadingState(message: 'Loading shared stock…'),
        error: (error, _) => ErrorState(
          message: inventoryErrorMessage(error),
          onRetry: () => ref.invalidate(sharedStockOverviewProvider),
        ),
        data: (data) => _OverviewBody(
          overview: data,
          query: _query,
          onQueryChanged: (value) => setState(() => _query = value),
          isOwner: isOwner,
          onEditRecipe: ({required String dishId, String? variantId}) =>
              _openEditor(dishId: dishId, variantId: variantId),
          onShowIngredientDetail: _openIngredientDetail,
        ),
      ),
    );
  }

  /// Opens the ingredient form and names the outcome. The overview
  /// refetches itself through the controller's invalidation; the snackbar
  /// only tells the owner what happened — and where to stock it.
  Future<void> _openIngredientForm() async {
    final created = await showIngredientFormSheet(context, ref);
    if (!mounted || !created) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ingredient added. Stock it through Purchases.'),
      ),
    );
  }

  /// Opens the read-only detail sheet for one ingredient.
  void _openIngredientDetail(SharedStockIngredient entry) {
    showIngredientDetailSheet(context, ref, entry);
  }

  /// Opens the editor and names the outcome. The overview refetches itself
  /// through the controller's invalidation; the snackbar only tells the
  /// owner what happened.
  Future<void> _openEditor({String? dishId, String? variantId}) async {
    final outcome = await showRecipeEditorSheet(
      context,
      ref,
      dishId: dishId,
      variantId: variantId,
    );
    if (!mounted || outcome == RecipeEditorOutcome.dismissed) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          outcome == RecipeEditorOutcome.saved
              ? 'Recipe saved.'
              : 'Recipe cleared.',
        ),
      ),
    );
  }
}

final class _OverviewBody extends StatelessWidget {
  const _OverviewBody({
    required this.overview,
    required this.query,
    required this.onQueryChanged,
    required this.isOwner,
    required this.onEditRecipe,
    required this.onShowIngredientDetail,
  });

  final SharedStockOverview overview;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final bool isOwner;
  final void Function({required String dishId, String? variantId}) onEditRecipe;
  final ValueChanged<SharedStockIngredient> onShowIngredientDetail;

  @override
  Widget build(BuildContext context) {
    final normalized = query.trim().toLowerCase();
    bool matches(String name) =>
        normalized.isEmpty || name.toLowerCase().contains(normalized);

    final ingredients = overview.ingredients
        .where(
          (entry) =>
              matches(entry.product.name) ||
              entry.consumers.any((consumer) => matches(consumer.productName)),
        )
        .toList();
    final unmapped = overview.unmappedSellables
        .where((product) => matches(product.name))
        .toList();

    return ListView(
      padding: AppInsets.screen,
      children: [
        PageHeader(
          title: 'Shared Stock',
          subtitle: isOwner
              ? 'Ingredients and the dishes that consume them. Tap a dish to '
                    'add or edit its recipe.'
              : 'Ingredients and the dishes that consume them.',
        ),
        const SizedBox(height: AppSpacing.md),
        SearchField(
          hintText: 'Search ingredients or dishes',
          onChanged: onQueryChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        if (ingredients.isEmpty && unmapped.isEmpty)
          normalized.isEmpty
              ? const EmptyState(
                  icon: Icons.link_outlined,
                  title: 'No shared stock yet',
                  message:
                      'Ingredients and their recipes will appear here once '
                      'they are set up.',
                )
              : const EmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'No matches',
                  message: 'Try a different ingredient or dish name.',
                )
        else ...[
          for (final entry in ingredients) ...[
            _IngredientCard(
              entry: entry,
              isOwner: isOwner,
              onEditRecipe: onEditRecipe,
              onShowDetail: () => onShowIngredientDetail(entry),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          if (unmapped.isNotEmpty) ...[
            SectionCard(
              title: 'Dishes without a recipe',
              subtitle:
                  '${unmapped.length} ${unmapped.length == 1 ? 'dish sells' : 'dishes sell'} from their own stock.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final product in unmapped)
                    _UnmappedDishRow(
                      name: product.name,
                      isOwner: isOwner,
                      onTap: () => onEditRecipe(dishId: product.id),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}

final class _IngredientCard extends StatelessWidget {
  const _IngredientCard({
    required this.entry,
    required this.isOwner,
    required this.onEditRecipe,
    required this.onShowDetail,
  });

  final SharedStockIngredient entry;
  final bool isOwner;
  final void Function({required String dishId, String? variantId}) onEditRecipe;
  final VoidCallback onShowDetail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final product = entry.product;
    final consumerCount = entry.consumers.length;
    return SectionCard(
      title: product.name,
      subtitle:
          '${product.stockQuantity} ${product.stockUnit.label} in stock · '
          '$consumerCount ${consumerCount == 1 ? 'dish' : 'dishes'}',
      trailing: isOwner
          ? IconButton(
              tooltip: 'Ingredient details',
              onPressed: onShowDetail,
              icon: const Icon(Icons.info_outlined),
            )
          : null,
      child: entry.consumers.isEmpty
          ? Text(
              'No dishes use this ingredient yet.',
              style: textTheme.bodyMedium?.copyWith(
                color: appColors.textSecondary,
              ),
            )
          : Column(
              children: [
                for (final consumer in entry.consumers)
                  _ConsumerRow(
                    consumer: consumer,
                    isOwner: isOwner,
                    onEditRecipe: onEditRecipe,
                  ),
              ],
            ),
    );
  }
}

final class _ConsumerRow extends StatelessWidget {
  const _ConsumerRow({
    required this.consumer,
    required this.isOwner,
    required this.onEditRecipe,
  });

  final SharedStockConsumer consumer;
  final bool isOwner;
  final void Function({required String dishId, String? variantId}) onEditRecipe;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final dish = consumer.variantName == null
        ? consumer.productName
        : '${consumer.productName} — ${consumer.variantName}';
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(dish, style: textTheme.bodyMedium)),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '×${consumer.quantityPerSale} ${consumer.unitLabel}',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          if (isOwner)
            IconButton(
              tooltip: 'Edit recipe',
              onPressed: () => onEditRecipe(
                dishId: consumer.productId,
                variantId: consumer.variantId,
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
    );
  }
}

final class _UnmappedDishRow extends StatelessWidget {
  const _UnmappedDishRow({
    required this.name,
    required this.isOwner,
    required this.onTap,
  });

  final String name;
  final bool isOwner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(name, style: Theme.of(context).textTheme.bodyMedium),
          ),
          if (isOwner) const Icon(Icons.add_outlined),
        ],
      ),
    );
    if (!isOwner) return label;
    return InkWell(onTap: onTap, child: label);
  }
}
