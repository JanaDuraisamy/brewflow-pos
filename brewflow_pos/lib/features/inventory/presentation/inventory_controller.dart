import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_image_sync_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/effective_stock.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Inventory State (Riverpod)
///
/// Composition:
/// - [inventoryRepositoryProvider]  → Drift-backed repository (override in
///                                    tests with a fake).
/// - [categoriesProvider]           → all categories.
/// - [inventoryFilterProvider]      → current product list filter.
/// - [productsProvider]             → products matching the filter.
///
/// Mutations go through a shared [mutate] helper: run the repository call,
/// then invalidate the affected state so the UI refreshes. Every failure is
/// translated into a safe [InventoryFailure] (details logged, never shown).
/// ---------------------------------------------------------------------------

/// Owns the single inventory repository for the application scope. The outbox
/// coordinator binds master-data writes to the durable sync queue atomically
/// (no-op when no session is active).
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  SupabaseClient? client;
  try {
    client = Supabase.instance.client;
  } catch (_) {
    client = null;
  }
  return DriftInventoryRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
    imageQueue: DriftImageSyncRepository(ref.watch(appDatabaseProvider)),
    connectivityService: ref.watch(connectivityServiceProvider),
    supabaseClient: client,
  );
});

/// All product categories, sorted by name.
final categoriesProvider =
    AsyncNotifierProvider<CategoriesController, List<Category>>(
      CategoriesController.new,
    );

final class CategoriesController extends AsyncNotifier<List<Category>> {
  static const String tag = 'Inventory';

  @override
  Future<List<Category>> build() async {
    final repository = ref.watch(inventoryRepositoryProvider);
    try {
      // Reading the switcher is inside the guard on purpose: resolving a shop
      // touches storage and the staff repository, and a failure there is just
      // as much a failed load as one thrown by the query.
      final business = ref.watch(businessSwitcherProvider);
      final switcher = ref.read(businessSwitcherProvider.notifier);
      if (business == BusinessContext.foodTruck) {
        // A truck with no persisted identity shows no categories at all rather
        // than the Cafe's, and never mints a shop by browsing.
        final ftId = await switcher.existingFoodTruckShopId();
        if (ftId == null) return const [];
        return await repository.categoriesForBusiness(
          shopId: ftId,
          catalogOwnerShopId: await switcher.shopIdFor(BusinessContext.cafe),
        );
      }
      // Cafe and All keep the existing shop-scoped list; Cafe is the default and
      // is already scoped by the repository.
      return await repository.categories(
        shopIds: await switcher.shopIdsForRead(business),
      );
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load categories',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  Future<void> create(String name) async {
    requirePermission(ref, Permission.editInventory);
    final shopId = await _writeShopId();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .createCategory(name, shopId: shopId),
      label: 'category.create',
    );
  }

  Future<void> rename(String id, String name) async {
    requirePermission(ref, Permission.editInventory);
    final shopIds = await _writeShopIds();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .updateCategoryName(id, name, shopIds: shopIds),
      label: 'category.rename',
    );
  }

  Future<void> setActive(String id, bool isActive) async {
    requirePermission(ref, Permission.editInventory);
    final shopIds = await _writeShopIds();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .setCategoryActive(id, isActive, shopIds: shopIds),
      label: 'category.set_active',
    );
  }

  /// Categories are owner-only to delete: an inventory editor may still rename
  /// and toggle categories, but removal is guarded here as well as in the UI so
  /// hiding the button is never the only protection.
  Future<void> delete(String id) async {
    requirePermission(ref, Permission.editInventory);
    requireOwner(ref);
    final shopIds = await _writeShopIds();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .deleteCategory(id, shopIds: shopIds),
      label: 'category.delete',
    );
  }

  /// The shop a new inventory row belongs to. Resolved from the active business
  /// so the Food Truck never writes into the Cafe's catalogue; the combined
  /// view is read-only and therefore refused.
  Future<String> _writeShopId() =>
      ref.read(businessSwitcherProvider.notifier).requireWritableShopId();

  /// The allow-set of shops whose existing rows a mutation may touch.
  ///
  /// Single-business contexts yield exactly one id. The combined All view is
  /// read-only, so it is refused here rather than silently narrowing to the
  /// Cafe — a mutation from that view would be ambiguous about which shelf it
  /// means.
  Future<List<String>?> _writeShopIds() async => [await _writeShopId()];

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [InventoryFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedInventoryFailure].
  ///
  /// [label] names the mutation on the trace line, so a stock edit and a
  /// product rename stay distinguishable in logcat without a trace call site
  /// per method. Tracing only observes; the invalidate pattern is unchanged.
  Future<void> _mutate(
    Future<void> Function() action, {
    required String label,
  }) async {
    try {
      await action();
      AppTrace.event('inventory.mutate', {'action': label, 'outcome': 'ok'});
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
    } on InventoryFailure catch (failure) {
      AppTrace.warn('inventory.mutate', {
        'action': label,
        'outcome': 'rejected',
        'failure': failure.runtimeType.toString(),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppTrace.fail('inventory.mutate_fail', error, stackTrace, {
        'action': label,
      });
      AppLog.error(
        'Inventory mutation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }
}

/// Immutable product list filter state.
final class InventoryFilter {
  const InventoryFilter({
    this.query = '',
    this.categoryId,
    this.status = ProductStatusFilter.all,
    this.lowStockOnly = false,
    this.outOfStockOnly = false,
  });

  /// Search text matched against product name and SKU.
  final String query;

  /// Restricts the list to one category when set.
  final String? categoryId;

  /// Active/inactive restriction.
  final ProductStatusFilter status;

  /// When true, only products with a currently low-stock entity are listed —
  /// judged with the same effective-threshold rules as the dashboard
  /// (USE_DEFAULT / CUSTOM / OFF; OFF entities never qualify). The dashboard
  /// Low Stock alert opens Inventory with this filter pre-applied.
  final bool lowStockOnly;

  /// When true, only products whose currently effective stock is exactly zero
  /// are listed. Mirrors the dashboard's Out of Stock rule: an active
  /// variant-level zero beats a non-zero parent, judged against the same
  /// active-entity rules as the low-stock filter.
  final bool outOfStockOnly;

  InventoryFilter withQuery(String query) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
    outOfStockOnly: outOfStockOnly,
  );

  InventoryFilter withCategory(String? categoryId) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
    outOfStockOnly: outOfStockOnly,
  );

  InventoryFilter withStatus(ProductStatusFilter status) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
    outOfStockOnly: outOfStockOnly,
  );

  InventoryFilter withLowStockOnly(bool lowStockOnly) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
    outOfStockOnly: outOfStockOnly,
  );

  InventoryFilter withOutOfStockOnly(bool outOfStockOnly) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
    outOfStockOnly: outOfStockOnly,
  );
}

/// Holds the current product list filter; changes rebuild [inventoryFilterProvider].
final inventoryFilterProvider =
    NotifierProvider<InventoryFilterController, InventoryFilter>(
      InventoryFilterController.new,
    );

final class InventoryFilterController extends Notifier<InventoryFilter> {
  @override
  InventoryFilter build() => const InventoryFilter();

  void setQuery(String query) => state = state.withQuery(query);

  void setCategory(String? categoryId) =>
      state = state.withCategory(categoryId);

  void setStatus(ProductStatusFilter status) =>
      state = state.withStatus(status);

  void setLowStockOnly(bool lowStockOnly) =>
      state = state.withLowStockOnly(lowStockOnly);

  void setOutOfStockOnly(bool outOfStockOnly) =>
      state = state.withOutOfStockOnly(outOfStockOnly);

  void clear() => state = const InventoryFilter();
}

/// Products matching the current [inventoryFilterProvider] state.
final productsProvider =
    AsyncNotifierProvider<ProductsController, List<Product>>(
      ProductsController.new,
    );

final class ProductsController extends AsyncNotifier<List<Product>> {
  static const String tag = 'Inventory';

  @override
  Future<List<Product>> build() async {
    final filter = ref.watch(inventoryFilterProvider);
    final repository = ref.watch(inventoryRepositoryProvider);
    // The active business decides which catalogue this list is: Cafe sees its
    // own products, Food Truck sees its own products plus the Cafe products the
    // owner has shared, and the combined view sees both shops' own products.
    final business = ref.watch(businessSwitcherProvider);
    final switcher = ref.read(businessSwitcherProvider.notifier);
    try {
      final List<Product> items;
      String? overlayShopId;
      if (business == BusinessContext.foodTruck) {
        // Reads must never mint a Food Truck shop, so a truck that does not
        // exist yet shows nothing rather than the Cafe's catalogue.
        final ftId = await switcher.existingFoodTruckShopId();
        if (ftId == null) return const [];
        items = await repository.productsForBusiness(
          shopId: ftId,
          catalogOwnerShopId: await switcher.shopIdFor(BusinessContext.cafe),
          search: filter.query,
          status: filter.status,
          categoryId: filter.categoryId,
        );
        // Shared products are sold from the truck's own shelf, so the numbers
        // the truck filters and displays on must be the truck's, not the
        // Cafe's. Applied before the stock filters so low/out-of-stock are
        // judged on the same figures the user will be billed against.
        overlayShopId = ftId;
      } else if (business == BusinessContext.all) {
        // Only the multi-business view needs the shop list; Cafe is the default
        // and is already scoped by the repository, so it keeps the unscoped
        // call it has always made.
        items = await repository.products(
          search: filter.query,
          status: filter.status,
          categoryId: filter.categoryId,
          shopIds: await switcher.shopIdsForRead(business),
        );
      } else {
        items = await repository.products(
          search: filter.query,
          status: filter.status,
          categoryId: filter.categoryId,
        );
      }
      // Read the overlay only when there IS an overlay to read. Watching it
      // unconditionally would build the overlay repository — and therefore the
      // database behind it — for a plain Cafe read that never uses it.
      final withEffectiveStock = overlayShopId == null
          ? items
          : await applyEffectiveStock(
              products: items,
              repository: ref.read(shopProductStockRepositoryProvider),
              shopId: overlayShopId,
            );
      return await _applyStockFilters(withEffectiveStock, filter);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to load products',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  /// Applies the low-stock / out-of-stock filters shared by every business, so
  /// the Food Truck list is judged by exactly the same rules as the Cafe one.
  Future<List<Product>> _applyStockFilters(
    List<Product> items,
    InventoryFilter filter,
  ) async {
    var result = items;
    if (filter.lowStockOnly) {
      // Same threshold source as the dashboard: the saved shop settings,
      // falling back to the built-in default when settings are unavailable.
      var globalThreshold = ShopSettings.defaultLowStockThreshold;
      try {
        globalThreshold = (await ref.read(settingsRepositoryProvider).load())
            .lowStockThreshold;
      } on Object {
        AppLog.info(
          'Low-stock filter fell back to the default threshold',
          tag: tag,
        );
      }
      bool isEntityLow(Product product) {
        if (product.variants.isNotEmpty) {
          return product.variants.any(
            (variant) =>
                variant.isActive &&
                switch (effectiveVariantLowStockThreshold(
                  variant,
                  product,
                  globalThreshold,
                )) {
                  null => false,
                  final threshold => isLowStock(
                    stock: variant.stockQuantity,
                    threshold: threshold,
                  ),
                },
          );
        }
        return switch (effectiveLowStockThreshold(product, globalThreshold)) {
          null => false,
          final threshold => isLowStock(
            stock: product.stockQuantity,
            threshold: threshold,
          ),
        };
      }

      result = [
        for (final product in result)
          if (isEntityLow(product)) product,
      ];
    }
    if (filter.outOfStockOnly) {
      // Mirrors the dashboard's Out of Stock rule: any active line whose
      // currently effective stock is exactly zero (a variant-level zero
      // beats a non-zero parent, judged against the same active-variant
      // rules as the low-stock filter).
      bool isEntityOut(Product product) {
        if (product.variants.isNotEmpty) {
          return product.variants.any(
            (variant) => variant.isActive && variant.stockQuantity <= 0,
          );
        }
        return product.stockQuantity <= 0;
      }

      result = [
        for (final product in result)
          if (isEntityOut(product)) product,
      ];
    }
    return result;
  }

  /// The shop a new inventory row belongs to. Resolved from the active business
  /// so the Food Truck never writes into the Cafe's catalogue; the combined
  /// view is read-only and therefore refused.
  Future<String> _writeShopId() =>
      ref.read(businessSwitcherProvider.notifier).requireWritableShopId();

  /// The allow-set of shops whose existing rows a mutation may touch.
  ///
  /// Sharing makes a Cafe product *visible* in the truck, never *owned* by it,
  /// so every ID-only mutation is resolved against this list. The combined All
  /// view is read-only and is refused, since a delete from that view does not
  /// say which business meant it.
  Future<List<String>?> _writeShopIds() async => [await _writeShopId()];

  Future<bool> skuExists(String sku, {String? exceptId}) async {
    try {
      return await ref
          .read(inventoryRepositoryProvider)
          .skuExists(sku, exceptId: exceptId);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Failed to check SKU uniqueness',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  Future<void> create({
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    bool visibleInShops = false,
    List<ProductVariantInput> variants = const [],
  }) async {
    requirePermission(ref, Permission.editInventory);
    final shopId = await _writeShopId();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .createProduct(
            categoryId: categoryId,
            name: name,
            sku: sku,
            sellingPricePaise: sellingPricePaise,
            costPricePaise: costPricePaise,
            stockQuantity: stockQuantity,
            imagePath: imagePath,
            stockUnit: stockUnit,
            lowStockMode: lowStockMode,
            lowStockThreshold: lowStockThreshold,
            membershipEnabled: membershipEnabled,
            memberPricePaise: memberPricePaise,
            isActive: isActive,
            visibleInShops: visibleInShops,
            variants: variants,
            shopId: shopId,
          ),
      label: 'product.create',
    );
  }

  Future<void> updateProduct({
    required String id,
    required String categoryId,
    required String name,
    String? sku,
    required int sellingPricePaise,
    int? costPricePaise,
    required int stockQuantity,
    String? imagePath,
    StockUnit stockUnit = StockUnit.count,
    LowStockMode lowStockMode = LowStockMode.useDefault,
    int? lowStockThreshold,
    bool membershipEnabled = false,
    int? memberPricePaise,
    required bool isActive,
    bool visibleInShops = false,
    List<ProductVariantInput> variants = const [],
  }) async {
    requirePermission(ref, Permission.editInventory);
    final shopId = await _writeShopId();
    final shopIds = await _writeShopIds();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .updateProduct(
            id: id,
            categoryId: categoryId,
            name: name,
            sku: sku,
            sellingPricePaise: sellingPricePaise,
            costPricePaise: costPricePaise,
            stockQuantity: stockQuantity,
            imagePath: imagePath,
            stockUnit: stockUnit,
            lowStockMode: lowStockMode,
            lowStockThreshold: lowStockThreshold,
            membershipEnabled: membershipEnabled,
            memberPricePaise: memberPricePaise,
            isActive: isActive,
            visibleInShops: visibleInShops,
            variants: variants,
            shopId: shopId,
            shopIds: shopIds,
          ),
      label: 'product.update',
    );
  }

  Future<void> setActive(String id, bool isActive) async {
    requirePermission(ref, Permission.editInventory);
    final shopIds = await _writeShopIds();
    return _mutate(
      () => ref
          .read(inventoryRepositoryProvider)
          .setProductActive(id, isActive, shopIds: shopIds),
      label: 'product.set_active',
    );
  }

  Future<ProductDeleteResult> delete(String id) async {
    requireOwner(ref);
    final shopIds = await _writeShopIds();
    try {
      final result = await ref
          .read(inventoryRepositoryProvider)
          .deleteProduct(id, shopIds: shopIds);
      AppTrace.event('inventory.mutate', {
        'action': 'product.delete',
        'outcome': 'ok',
        'productRef': AppTrace.userRef(id),
        // Which of the two destructive outcomes actually happened: hard delete
        // vs deactivate-because-still-referenced. This is the line that settles
        // "did it delete the product, or only detach it from this shop?".
        'result': result.name,
      });
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
      return result;
    } on InventoryFailure catch (failure) {
      AppTrace.warn('inventory.mutate', {
        'action': 'product.delete',
        'outcome': 'rejected',
        'failure': failure.runtimeType.toString(),
        'productRef': AppTrace.userRef(id),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppLog.error(
        'Inventory delete failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [InventoryFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedInventoryFailure].
  ///
  /// [label] names the mutation on the trace line, so a stock edit and a
  /// product rename stay distinguishable in logcat without a trace call site
  /// per method. Tracing only observes; the invalidate pattern is unchanged.
  Future<void> _mutate(
    Future<void> Function() action, {
    required String label,
  }) async {
    try {
      await action();
      AppTrace.event('inventory.mutate', {'action': label, 'outcome': 'ok'});
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
    } on InventoryFailure catch (failure) {
      AppTrace.warn('inventory.mutate', {
        'action': label,
        'outcome': 'rejected',
        'failure': failure.runtimeType.toString(),
      });
      rethrow;
    } catch (error, stackTrace) {
      AppTrace.fail('inventory.mutate_fail', error, stackTrace, {
        'action': label,
      });
      AppLog.error(
        'Inventory mutation failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      throw const UnexpectedInventoryFailure();
    }
  }
}

/// Maps any thrown object to a user-safe message.
///
/// [InventoryFailure]s already carry display-ready text; anything else falls
/// back to a generic message (with [fallback] when provided).
String inventoryErrorMessage(Object error, {String? fallback}) {
  if (error is InventoryFailure) {
    return error.message;
  }
  return fallback ?? 'Something went wrong. Please try again.';
}
