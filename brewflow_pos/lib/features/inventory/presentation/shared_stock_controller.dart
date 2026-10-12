/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Stock State (Riverpod)
///
/// Composition:
/// - [sharedStockOverviewProvider] → read-only ingredient/consumer overview.
/// - [sharedStockCatalogueProvider] → scoped dish + ingredient lists for the
///   recipe editor.
/// - [SharedStockOverviewController.saveRecipe] / [clearRecipe] → owner-only
///   recipe writes through [InventoryRepository.setRecipe]; the same scope
///   rules as the overview apply, and the combined All view is refused
///   (fail-closed) because a write from it would be ambiguous about which
///   shelf it means.
///
/// Writes never touch stock quantities and never run the menu seed: only the
/// recipe rows of the exact dish + variant scope being edited are replaced.
/// Every other mapping — including the seeded Maggi Packet rows — is left
/// exactly as it was.
/// ---------------------------------------------------------------------------
library;

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/effective_stock.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One sellable product (or one of its variants) consuming an ingredient.
final class SharedStockConsumer {
  const SharedStockConsumer({
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    required this.quantityPerSale,
    required this.unitLabel,
  });

  final String productId;
  final String productName;

  /// The consuming variant id, or null when the row covers every variant.
  final String? variantId;

  /// The consuming variant, or null when the row covers every variant.
  final String? variantName;

  /// Units of the ingredient consumed per ONE unit sold. Always >= 1.
  final int quantityPerSale;

  /// Display label of the ingredient's own stock unit.
  final String unitLabel;
}

/// One stock-source ingredient with every sellable that consumes it.
final class SharedStockIngredient {
  const SharedStockIngredient({required this.product, required this.consumers});

  final Product product;
  final List<SharedStockConsumer> consumers;
}

/// The full read-only overview for the active business scope.
final class SharedStockOverview {
  const SharedStockOverview({
    required this.ingredients,
    required this.unmappedSellables,
  });

  /// Ingredients in scope, each with its consumers. Sorted by name.
  final List<SharedStockIngredient> ingredients;

  /// Sellable products in scope with no recipe rows. Sorted by name.
  final List<Product> unmappedSellables;
}

/// One recipe row with display-ready names, for the editor summary.
final class SharedStockRecipeLine {
  const SharedStockRecipeLine({
    required this.ingredientProductId,
    required this.ingredientName,
    this.ingredientVariantId,
    this.ingredientVariantName,
    required this.quantity,
    required this.unitLabel,
  });

  final String ingredientProductId;
  final String ingredientName;
  final String? ingredientVariantId;
  final String? ingredientVariantName;
  final int quantity;
  final String unitLabel;
}

/// Scoped dish + ingredient lists backing the recipe editor pickers.
final class SharedStockCatalogue {
  const SharedStockCatalogue({
    required this.sellables,
    required this.ingredients,
  });

  /// Sellable dishes in scope (mapped and unmapped). Sorted by name.
  final List<Product> sellables;

  /// Tracked stock-source ingredients in scope. Sorted by name.
  final List<Product> ingredients;
}

/// Loads [SharedStockOverview] for the active business.
///
/// Product sourcing mirrors [ProductsController.build] exactly (Cafe/combined
/// go through the scoped `products()` call, the Food Truck through
/// `productsForBusiness` plus the effective-stock overlay, and a truck that
/// does not exist yet yields an empty overview), so the overview can never
/// show a catalogue the business is not allowed to see.
final sharedStockOverviewProvider =
    AsyncNotifierProvider<SharedStockOverviewController, SharedStockOverview>(
      SharedStockOverviewController.new,
    );

/// Scoped catalogue for the recipe editor; same sourcing as the overview.
final sharedStockCatalogueProvider = FutureProvider<SharedStockCatalogue>((
  ref,
) async {
  final scoped = await loadScopedProducts(ref);
  final sellables = scoped.items.where((item) => !item.isIngredient).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  final ingredients =
      scoped.items
          .where(
            (item) => item.isIngredient && item.stockUnit != StockUnit.none,
          )
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  return SharedStockCatalogue(sellables: sellables, ingredients: ingredients);
});

/// Products visible to the active business plus the recipe scope they were
/// read under. Shared by the overview, the catalogue and the write path so
/// all three can never disagree about which catalogue is on screen.
typedef ScopedProducts = ({List<Product> items, List<String> recipeScope});

/// Loads the visible catalogue exactly like [ProductsController.build]: Cafe
/// and the combined view share one scoped `products()` call, the Food Truck
/// goes through `productsForBusiness` plus the effective-stock overlay, and
/// a truck that does not exist yet yields nothing rather than the Cafe's
/// catalogue. Reads never mint a shop row.
Future<ScopedProducts> loadScopedProducts(Ref ref) async {
  final repository = ref.watch(inventoryRepositoryProvider);
  final business = ref.watch(businessSwitcherProvider);
  final switcher = ref.read(businessSwitcherProvider.notifier);
  if (business == BusinessContext.foodTruck) {
    // Reads must never mint a Food Truck shop, so a truck that does not
    // exist yet sees nothing rather than the Cafe's catalogue.
    final ftId = await switcher.existingFoodTruckShopId();
    if (ftId == null) {
      return (items: const <Product>[], recipeScope: const <String>[]);
    }
    final items = await repository.productsForBusiness(
      shopId: ftId,
      catalogOwnerShopId: await switcher.shopIdFor(BusinessContext.cafe),
    );
    // Read the overlay only when there IS an overlay to read. Watching it
    // unconditionally would build the overlay repository — and therefore the
    // database behind it — for a plain Cafe read that never uses it.
    final effective = await applyEffectiveStock(
      products: items,
      repository: ref.read(shopProductStockRepositoryProvider),
      shopId: ftId,
    );
    return (items: effective, recipeScope: [ftId]);
  }
  final recipeScope = await switcher.shopIdsForRead(business);
  final items = await repository.products(shopIds: recipeScope);
  return (items: items, recipeScope: recipeScope);
}

/// Client-side recipe validation shared by the editor form and the write
/// path (the repository re-validates before writing; this only explains
/// problems earlier, in the user's terms).
///
/// Returns a display-ready message for the first problem found, or null when
/// the draft is well-formed. [catalogueById] is the visible catalogue, so a
/// dish or ingredient outside the active business scope is rejected here
/// rather than at the repository.
String? validateRecipeDraft({
  required Product dish,
  String? variantId,
  required List<RecipeIngredientInput> lines,
  required Map<String, Product> catalogueById,
}) {
  if (lines.isEmpty) {
    return 'Add at least one ingredient to save a recipe.';
  }
  if (variantId != null &&
      !dish.variants.any((variant) => variant.id == variantId)) {
    return const RecipeVariantMismatchFailure().message;
  }
  final seenIngredients = <String>{};
  for (final line in lines) {
    if (!seenIngredients.add(line.ingredientProductId)) {
      return 'Each ingredient can appear only once in a recipe.';
    }
    if (line.quantity < 1) {
      return const RecipeQuantityFailure().message;
    }
    if (line.ingredientProductId == dish.id) {
      return const RecipeSelfConsumptionFailure().message;
    }
    final ingredient = catalogueById[line.ingredientProductId];
    if (ingredient == null) {
      return 'This ingredient is not available in the active business.';
    }
    if (ingredient.stockUnit == StockUnit.none) {
      return const RecipeUntrackedIngredientFailure().message;
    }
    if (line.ingredientVariantId != null &&
        !ingredient.variants.any(
          (variant) => variant.id == line.ingredientVariantId,
        )) {
      return const RecipeIngredientVariantMismatchFailure().message;
    }
  }
  return null;
}

final class SharedStockOverviewController
    extends AsyncNotifier<SharedStockOverview> {
  static const String tag = 'SharedStock';

  @override
  Future<SharedStockOverview> build() async {
    try {
      final scoped = await loadScopedProducts(ref);
      final effective = scoped.items;
      final recipeScope = scoped.recipeScope;
      final repository = ref.watch(inventoryRepositoryProvider);

      final byId = <String, Product>{
        for (final item in effective) item.id: item,
      };
      final consumersByIngredient = <String, List<SharedStockConsumer>>{};
      final mappedSellableIds = <String>{};
      for (final sellable in effective) {
        if (sellable.isIngredient) continue;
        final rows = await repository.recipesForProduct(
          sellable.id,
          shopIds: recipeScope,
        );
        if (rows.isEmpty) continue;
        mappedSellableIds.add(sellable.id);
        for (final row in rows) {
          final ingredient = byId[row.ingredientProductId];
          // The ingredient is outside the visible scope (or deleted): its row
          // still deducts at checkout, but this business cannot audit it, so
          // it is skipped rather than shown half-labelled.
          if (ingredient == null) continue;
          final variantName = row.variantId == null
              ? null
              : _variantName(sellable, row.variantId!);
          consumersByIngredient
              .putIfAbsent(ingredient.id, () => [])
              .add(
                SharedStockConsumer(
                  productId: sellable.id,
                  productName: sellable.name,
                  variantId: row.variantId,
                  variantName: variantName,
                  quantityPerSale: row.quantity,
                  unitLabel: ingredient.stockUnit.label,
                ),
              );
        }
      }

      final ingredients = <SharedStockIngredient>[];
      for (final item in effective) {
        if (!item.isIngredient) continue;
        final consumers = List.of(
          consumersByIngredient[item.id] ?? const <SharedStockConsumer>[],
        );
        consumers.sort(_byConsumerName);
        ingredients.add(
          SharedStockIngredient(product: item, consumers: List.of(consumers)),
        );
      }
      ingredients.sort((a, b) => a.product.name.compareTo(b.product.name));

      final unmapped =
          effective
              .where(
                (item) =>
                    !item.isIngredient && !mappedSellableIds.contains(item.id),
              )
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));

      return SharedStockOverview(
        ingredients: ingredients,
        unmappedSellables: unmapped,
      );
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load the shared-stock overview.',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      if (error is InventoryFailure) rethrow;
      throw const UnexpectedInventoryFailure(
        'Could not load shared stock. Please try again.',
      );
    }
  }

  /// Existing recipe rows for one dish + variant scope, attributed to the
  /// writable shop (the exact rows a save would replace). Empty when the
  /// scope has no mapping yet.
  Future<List<SharedStockRecipeLine>> existingRecipe({
    required String productId,
    String? variantId,
  }) async {
    final shopId = await _writeShopId();
    final repository = ref.read(inventoryRepositoryProvider);
    final scoped = await loadScopedProducts(ref);
    final byId = <String, Product>{
      for (final item in scoped.items) item.id: item,
    };
    final rows = await repository.recipesForProduct(
      productId,
      shopIds: [shopId],
    );
    final lines = <SharedStockRecipeLine>[];
    for (final row in rows) {
      if (row.variantId != variantId) continue;
      final ingredient = byId[row.ingredientProductId];
      // Rows pointing outside the visible catalogue still deduct at
      // checkout; they are shown with the stored id rather than hidden, so
      // the replace summary never understates what a save would remove.
      lines.add(
        SharedStockRecipeLine(
          ingredientProductId: row.ingredientProductId,
          ingredientName: ingredient?.name ?? row.ingredientProductId,
          ingredientVariantId: row.ingredientVariantId,
          ingredientVariantName: row.ingredientVariantId == null
              ? null
              : _variantName(ingredient, row.ingredientVariantId!),
          quantity: row.quantity,
          unitLabel: ingredient?.stockUnit.label ?? '',
        ),
      );
    }
    return lines;
  }

  /// Creates or replaces the recipe mapping of one dish + variant scope.
  ///
  /// Owner-only (guarded here, not just in the UI), attributed to the
  /// writable shop, and refused from the read-only All view. Only the rows
  /// of the edited scope are replaced; every other dish keeps its mapping.
  /// [InventoryFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedInventoryFailure].
  Future<void> saveRecipe({
    required String productId,
    String? variantId,
    required List<RecipeIngredientInput> lines,
  }) async {
    requirePermission(ref, Permission.editInventory);
    requireOwner(ref);
    final shopId = await _writeShopId();
    final repository = ref.read(inventoryRepositoryProvider);
    final scoped = await loadScopedProducts(ref);
    final byId = <String, Product>{
      for (final item in scoped.items) item.id: item,
    };
    final dish = byId[productId];
    if (dish == null || dish.isIngredient) {
      throw const UnexpectedInventoryFailure(
        'This dish is not available in the active business.',
      );
    }
    final problem = validateRecipeDraft(
      dish: dish,
      variantId: variantId,
      lines: lines,
      catalogueById: byId,
    );
    if (problem != null) {
      throw _failureForMessage(problem);
    }
    await _rejectOverlap(
      repository: repository,
      dish: dish,
      variantId: variantId,
      shopId: shopId,
    );
    try {
      await repository.setRecipe(
        productId: productId,
        variantId: variantId,
        ingredients: lines,
        shopId: shopId,
      );
      AppTrace.event('inventory.mutate', {
        'action': 'recipe.save',
        'outcome': 'ok',
      });
      _refreshAfterWrite(
        dishId: productId,
        ingredientIds: [for (final line in lines) line.ingredientProductId],
      );
    } on InventoryFailure catch (failure) {
      AppTrace.warn('inventory.mutate', {
        'action': 'recipe.save',
        'outcome': 'rejected',
        'failure': failure.runtimeType.toString(),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppTrace.fail('inventory.mutate_fail', error, stackTrace, {
        'action': 'recipe.save',
      });
      AppLog.error(
        'Recipe save failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  /// Clears the recipe mapping of one dish + variant scope (the dish sells
  /// from its own stock again). Owner-only, write-scoped, and a no-op when
  /// the scope already has no mapping. The UI confirms destructively before
  /// calling; the controller stays safe to call regardless.
  Future<void> clearRecipe({
    required String productId,
    String? variantId,
  }) async {
    requirePermission(ref, Permission.editInventory);
    requireOwner(ref);
    final shopId = await _writeShopId();
    final repository = ref.read(inventoryRepositoryProvider);
    try {
      final rows = await repository.recipesForProduct(
        productId,
        shopIds: [shopId],
      );
      if (!rows.any((row) => row.variantId == variantId)) return;
      await repository.setRecipe(
        productId: productId,
        variantId: variantId,
        ingredients: const [],
        shopId: shopId,
      );
      AppTrace.event('inventory.mutate', {
        'action': 'recipe.clear',
        'outcome': 'ok',
      });
      _refreshAfterWrite(dishId: productId, ingredientIds: const []);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Recipe clear failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  /// Creates a stock-source ingredient through the existing product flow.
  ///
  /// Owner-only (guarded here, not just in the UI), attributed to the
  /// writable shop, and refused from the read-only All view. The ingredient
  /// is born with zero stock and no movements — the owner stocks it through
  /// Purchases, exactly like the seeded Maggi Packet — and is hidden from
  /// the sale shelf by the ingredient flag. No existing product, recipe, or
  /// stock quantity is touched.
  ///
  /// [InventoryFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedInventoryFailure].
  Future<Product> createIngredient({
    required String categoryId,
    required String name,
    required StockUnit stockUnit,
  }) async {
    requirePermission(ref, Permission.editInventory);
    requireOwner(ref);
    final shopId = await _writeShopId();
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const UnexpectedInventoryFailure('Give the ingredient a name.');
    }
    if (stockUnit == StockUnit.none) {
      // Untracked products hold no stock to consume; a recipe naming one
      // would fail every sale, so the ingredient itself is refused first.
      throw const RecipeUntrackedIngredientFailure();
    }
    final repository = ref.read(inventoryRepositoryProvider);
    final scoped = await loadScopedProducts(ref);
    final categories = await ref.read(categoriesProvider.future);
    if (!categories.any((category) => category.id == categoryId)) {
      throw const UnexpectedInventoryFailure(
        'Select a category for the ingredient.',
      );
    }
    final lowered = trimmed.toLowerCase();
    for (final item in scoped.items) {
      // Same-shop twins only: another business may legitimately reuse a
      // name, and its row is a different stock source. Legacy rows without
      // a shop are treated as this shop's, so they can never be shadowed
      // silently.
      if ((item.shopId ?? shopId) == shopId &&
          item.name.toLowerCase() == lowered) {
        throw DuplicateIngredientNameFailure(item.name);
      }
    }
    try {
      final created = await repository.createProduct(
        categoryId: categoryId,
        name: trimmed,
        // Never sold at the counter (hidden by the ingredient flag); the
        // price is meaningless and stays an honest zero.
        sellingPricePaise: 0,
        // Never invent an opening balance: zero creates the product without
        // any movement, and Purchases is what stocks it later.
        stockQuantity: 0,
        stockUnit: stockUnit,
        isActive: true,
        shopId: shopId,
        isIngredient: true,
      );
      AppTrace.event('inventory.mutate', {
        'action': 'ingredient.create',
        'outcome': 'ok',
      });
      ref.invalidateSelf();
      ref.invalidate(productsProvider);
      return created;
    } on InventoryFailure catch (failure) {
      AppTrace.warn('inventory.mutate', {
        'action': 'ingredient.create',
        'outcome': 'rejected',
        'failure': failure.runtimeType.toString(),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppTrace.fail('inventory.mutate_fail', error, stackTrace, {
        'action': 'ingredient.create',
      });
      AppLog.error(
        'Ingredient creation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  /// The shop new recipe rows belong to. Resolved from the active business
  /// so the Food Truck never writes into the Cafe's catalogue; the combined
  /// All view is read-only and therefore refused with a display-ready
  /// failure instead of a raw [StateError].
  Future<String> _writeShopId() async {
    try {
      return await ref
          .read(businessSwitcherProvider.notifier)
          .requireWritableShopId();
    } on StateError catch (error, stackTrace) {
      AppLog.error(
        'Recipe write refused: no writable shop.',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const RecipeReadOnlyScopeFailure();
    }
  }

  /// Refuses a save that would leave product-level AND variant-specific rows
  /// on one dish: both scopes match the same sale at checkout, so the
  /// ingredient would be deducted twice. The message names the conflicting
  /// scope so the owner knows exactly what to clear first.
  Future<void> _rejectOverlap({
    required InventoryRepository repository,
    required Product dish,
    required String? variantId,
    required String shopId,
  }) async {
    final rows = await repository.recipesForProduct(dish.id, shopIds: [shopId]);
    final conflicting = rows.where((row) => row.variantId != variantId);
    if (conflicting.isEmpty) return;
    if (variantId == null) {
      final names = conflicting
          .map((row) => _variantName(dish, row.variantId!) ?? 'a variant')
          .toSet()
          .join(', ');
      throw RecipeOverlapFailure(
        '${dish.name} already has a recipe for $names. Clear the variant '
        'recipe first, or edit that variant instead of every variant.',
      );
    }
    throw RecipeOverlapFailure(
      '${dish.name} already has a recipe for every variant. Clear it first, '
      'or edit every variant instead of just ${_variantName(dish, variantId) ?? 'this one'}.',
    );
  }

  /// Refreshes the overview plus the product list and the stock histories of
  /// the touched products, so the new mapping is visible everywhere without
  /// a restart. Recipe rows carry no movements themselves, but the histories
  /// are the audit surface an owner checks next, and they must not serve a
  /// stale first paint.
  void _refreshAfterWrite({
    required String dishId,
    required List<String> ingredientIds,
  }) {
    ref.invalidateSelf();
    ref.invalidate(productsProvider);
    ref.invalidate(productMovementsProvider(dishId));
    for (final id in ingredientIds.toSet()) {
      ref.invalidate(productMovementsProvider(id));
    }
  }

  /// Maps a [validateRecipeDraft] message back to its failure so the write
  /// path throws typed failures (the messages are identical either way).
  InventoryFailure _failureForMessage(String message) {
    if (message == const RecipeVariantMismatchFailure().message) {
      return const RecipeVariantMismatchFailure();
    }
    if (message == const RecipeQuantityFailure().message) {
      return const RecipeQuantityFailure();
    }
    if (message == const RecipeSelfConsumptionFailure().message) {
      return const RecipeSelfConsumptionFailure();
    }
    if (message == const RecipeUntrackedIngredientFailure().message) {
      return const RecipeUntrackedIngredientFailure();
    }
    if (message == const RecipeIngredientVariantMismatchFailure().message) {
      return const RecipeIngredientVariantMismatchFailure();
    }
    return UnexpectedInventoryFailure(message);
  }

  String? _variantName(Product? product, String variantId) {
    if (product == null) return null;
    for (final variant in product.variants) {
      if (variant.id == variantId) return variant.name;
    }
    return null;
  }

  int _byConsumerName(SharedStockConsumer a, SharedStockConsumer b) {
    final byProduct = a.productName.compareTo(b.productName);
    if (byProduct != 0) return byProduct;
    return (a.variantName ?? '').compareTo(b.variantName ?? '');
  }
}
