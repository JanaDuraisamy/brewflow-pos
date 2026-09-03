import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/drift_image_sync_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return DriftInventoryRepository(
    ref.watch(appDatabaseProvider),
    outboxCoordinator: ref.watch(syncOutboxCoordinatorProvider),
    imageQueue: DriftImageSyncRepository(ref.watch(appDatabaseProvider)),
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
      return await repository.categories();
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

  Future<void> create(String name) {
    requirePermission(ref, Permission.editInventory);
    return _mutate(
      () => ref.read(inventoryRepositoryProvider).createCategory(name),
    );
  }

  Future<void> rename(String id, String name) {
    requirePermission(ref, Permission.editInventory);
    return _mutate(
      () => ref.read(inventoryRepositoryProvider).updateCategoryName(id, name),
    );
  }

  Future<void> setActive(String id, bool isActive) {
    requirePermission(ref, Permission.editInventory);
    return _mutate(
      () =>
          ref.read(inventoryRepositoryProvider).setCategoryActive(id, isActive),
    );
  }

  Future<void> delete(String id) {
    requirePermission(ref, Permission.editInventory);
    return _mutate(
      () => ref.read(inventoryRepositoryProvider).deleteCategory(id),
    );
  }

  /// Runs [action] against the repository, then refreshes this controller's
  /// state. [InventoryFailure]s pass through untouched; anything unexpected is
  /// logged and rethrown as [UnexpectedInventoryFailure].
  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
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

  InventoryFilter withQuery(String query) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
  );

  InventoryFilter withCategory(String? categoryId) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
  );

  InventoryFilter withStatus(ProductStatusFilter status) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
  );

  InventoryFilter withLowStockOnly(bool lowStockOnly) => InventoryFilter(
    query: query,
    categoryId: categoryId,
    status: status,
    lowStockOnly: lowStockOnly,
  );
}

/// Holds the current product list filter; changes rebuild [productsProvider].
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
    try {
      var items = await repository.products(
        search: filter.query,
        categoryId: filter.categoryId,
        status: filter.status,
      );
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

        items = [
          for (final product in items)
            if (isEntityLow(product)) product,
        ];
      }
      return items;
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
    List<ProductVariantInput> variants = const [],
  }) {
    requirePermission(ref, Permission.editInventory);
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
            variants: variants,
          ),
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
    List<ProductVariantInput> variants = const [],
  }) {
    requirePermission(ref, Permission.editInventory);
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
            variants: variants,
          ),
    );
  }

  Future<void> setActive(String id, bool isActive) {
    requirePermission(ref, Permission.editInventory);
    return _mutate(
      () =>
          ref.read(inventoryRepositoryProvider).setProductActive(id, isActive),
    );
  }

  Future<ProductDeleteResult> delete(String id) async {
    requireOwner(ref);
    try {
      final result = await ref
          .read(inventoryRepositoryProvider)
          .deleteProduct(id);
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
      return result;
    } on InventoryFailure {
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
  Future<void> _mutate(Future<void> Function() action) async {
    try {
      await action();
      ref.invalidateSelf();
      ref.invalidate(dashboardControllerProvider);
      ref.invalidate(reportsControllerProvider);
    } on InventoryFailure {
      rethrow;
    } catch (error, stackTrace) {
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
