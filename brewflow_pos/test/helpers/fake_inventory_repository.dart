import 'dart:async';

import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';

/// In-memory [InventoryRepository] for tests.
///
/// Mirrors the Drift repository semantics that matter to state and UI:
/// case-insensitive uniqueness, SQL-like search/filtering, paise storage and
/// safe failures. Probe hooks ([loadError], [loadGate]) drive loading and
/// error states.
final class FakeInventoryRepository implements InventoryRepository {
  final List<Category> storedCategories = [];
  final List<Product> storedProducts = [];

  /// When set, every load and mutation throws this error instead of running.
  Object? loadError;

  /// When set, category/products loads wait for this (loading-state tests).
  Completer<void>? loadGate;

  /// Number of [categories] calls.
  int categoriesCalls = 0;

  /// Number of [products] calls.
  int productsCalls = 0;

  Future<void> _gate() async {
    final gate = loadGate;
    if (gate != null) {
      await gate.future;
    }
  }

  void _throwIfLoadError() {
    final error = loadError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<List<Category>> categories() async {
    categoriesCalls += 1;
    await _gate();
    _throwIfLoadError();
    return List.of(storedCategories)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  Future<List<Product>> products({
    String? search,
    String? categoryId,
    ProductStatusFilter status = ProductStatusFilter.all,
  }) async {
    productsCalls += 1;
    await _gate();
    _throwIfLoadError();
    var result = List<Product>.of(storedProducts);
    final query = search?.trim() ?? '';
    if (query.isNotEmpty) {
      final lower = query.toLowerCase();
      result = result
          .where(
            (product) =>
                product.name.toLowerCase().contains(lower) ||
                (product.sku?.toLowerCase().contains(lower) ?? false),
          )
          .toList();
    }
    if (categoryId != null) {
      result = result
          .where((product) => product.categoryId == categoryId)
          .toList();
    }
    result = switch (status) {
      ProductStatusFilter.all => result,
      ProductStatusFilter.active =>
        result.where((product) => product.isActive).toList(),
      ProductStatusFilter.inactive =>
        result.where((product) => !product.isActive).toList(),
    };
    result.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return result;
  }

  @override
  Future<bool> skuExists(String sku, {String? exceptId}) async {
    return storedProducts.any(
      (product) =>
          product.sku != null &&
          product.sku!.toLowerCase() == sku.trim().toLowerCase() &&
          product.id != exceptId,
    );
  }

  @override
  Future<Category> createCategory(String name) async {
    _throwIfLoadError();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const UnexpectedInventoryFailure('Category name is required.');
    }
    if (storedCategories.any(
      (category) => category.name.toLowerCase() == normalized.toLowerCase(),
    )) {
      throw const DuplicateCategoryNameFailure();
    }
    final now = DateTime.now().toUtc();
    final category = Category(
      id: 'category-${storedCategories.length + 1}',
      name: normalized,
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );
    storedCategories.add(category);
    return category;
  }

  @override
  Future<void> updateCategoryName(String id, String name) async {
    _throwIfLoadError();
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const UnexpectedInventoryFailure('Category name is required.');
    }
    if (storedCategories.any(
      (category) =>
          category.name.toLowerCase() == normalized.toLowerCase() &&
          category.id != id,
    )) {
      throw const DuplicateCategoryNameFailure();
    }
    _replaceCategory(
      _requireCategory(
        id,
      ).copyWith(name: normalized, updatedAt: DateTime.now().toUtc()),
    );
  }

  @override
  Future<void> setCategoryActive(String id, bool isActive) async {
    _throwIfLoadError();
    _replaceCategory(
      _requireCategory(
        id,
      ).copyWith(isActive: isActive, updatedAt: DateTime.now().toUtc()),
    );
  }

  @override
  Future<void> deleteCategory(String id) async {
    _throwIfLoadError();
    if (storedProducts.any((product) => product.categoryId == id)) {
      throw const CategoryInUseFailure();
    }
    storedCategories.removeWhere((category) => category.id == id);
  }

  @override
  Future<Product> createProduct({
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
  }) async {
    _throwIfLoadError();
    _validatePrices(sellingPricePaise, costPricePaise);
    _validateStock(stockQuantity);
    final normalizedName = name.trim();
    final normalizedSku = _normalizedSku(sku);
    if (normalizedName.isEmpty) {
      throw const UnexpectedInventoryFailure('Product name is required.');
    }
    if (normalizedSku != null &&
        storedProducts.any(
          (product) =>
              product.sku != null &&
              product.sku!.toLowerCase() == normalizedSku.toLowerCase(),
        )) {
      throw const DuplicateSkuFailure();
    }
    if (membershipEnabled && memberPricePaise == null) {
      throw const MissingMemberPriceFailure();
    }
    if (variants.isNotEmpty && stockQuantity != 0) {
      throw const UnexpectedInventoryFailure(
        'Set stock on the variants instead of the product.',
      );
    }
    _validateVariantInputs(variants);
    final now = DateTime.now().toUtc();
    final createdVariants = [
      for (final (index, input) in variants.indexed)
        ProductVariant(
          id: 'variant-${storedProducts.length + 1}-$index',
          productId: 'product-${storedProducts.length + 1}',
          name: input.name.trim(),
          sku: _normalizedSku(input.sku),
          sellingPricePaise: input.sellingPricePaise,
          costPricePaise: input.costPricePaise,
          stockQuantity: input.stockQuantity,
          lowStockMode: input.lowStockMode,
          lowStockThreshold: input.lowStockThreshold,
          membershipEnabled: input.membershipEnabled,
          memberPricePaise: input.memberPricePaise,
          isActive: input.isActive,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    final product = Product(
      id: 'product-${storedProducts.length + 1}',
      categoryId: categoryId,
      name: normalizedName,
      sku: normalizedSku,
      sellingPricePaise: sellingPricePaise,
      costPricePaise: costPricePaise,
      stockQuantity: createdVariants.isEmpty
          ? stockQuantity
          : createdVariants.fold(
              0,
              (sum, variant) => sum + variant.stockQuantity,
            ),
      imagePath: imagePath,
      stockUnit: stockUnit,
      lowStockMode: lowStockMode,
      lowStockThreshold: lowStockThreshold,
      membershipEnabled: membershipEnabled,
      memberPricePaise: memberPricePaise,
      isActive: isActive,
      createdAt: now,
      updatedAt: now,
      variants: createdVariants,
    );
    storedProducts.add(product);
    return product;
  }

  @override
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
  }) async {
    _throwIfLoadError();
    _validatePrices(sellingPricePaise, costPricePaise);
    _validateStock(stockQuantity);
    final normalizedName = name.trim();
    final normalizedSku = _normalizedSku(sku);
    if (normalizedName.isEmpty) {
      throw const UnexpectedInventoryFailure('Product name is required.');
    }
    if (normalizedSku != null &&
        storedProducts.any(
          (product) =>
              product.sku != null &&
              product.sku!.toLowerCase() == normalizedSku.toLowerCase() &&
              product.id != id,
        )) {
      throw const DuplicateSkuFailure();
    }
    if (membershipEnabled && memberPricePaise == null) {
      throw const MissingMemberPriceFailure();
    }
    _validateVariantInputs(variants);
    final existing = storedProducts.firstWhere(
      (product) => product.id == id,
      orElse: () => throw const UnexpectedInventoryFailure(),
    );
    // Mirrors the Drift repository: edits never touch stock; the stored
    // mirror is the preserved existing variant stock plus new opening stock.
    final keptStock = existing.variants.fold(
      0,
      (sum, variant) => sum + variant.stockQuantity,
    );
    final newStock = variants
        .where((v) => v.id == null)
        .fold(0, (sum, v) => sum + v.stockQuantity);
    final updatedVariants = [
      for (final (index, input) in variants.indexed)
        input.id == null
            ? ProductVariant(
                id: 'variant-${storedProducts.length + 1}-$index',
                productId: id,
                name: input.name.trim(),
                sku: _normalizedSku(input.sku),
                sellingPricePaise: input.sellingPricePaise,
                costPricePaise: input.costPricePaise,
                stockQuantity: input.stockQuantity,
                lowStockMode: input.lowStockMode,
                lowStockThreshold: input.lowStockThreshold,
                membershipEnabled: input.membershipEnabled,
                memberPricePaise: input.memberPricePaise,
                isActive: input.isActive,
                createdAt: DateTime.now().toUtc(),
                updatedAt: DateTime.now().toUtc(),
              )
            : (existing.variants.firstWhere(
                (v) => v.id == input.id,
                orElse: () => throw const UnexpectedInventoryFailure(),
              )).copyWith(
                name: input.name.trim(),
                sku: _normalizedSku(input.sku),
                sellingPricePaise: input.sellingPricePaise,
                costPricePaise: input.costPricePaise,
                lowStockMode: input.lowStockMode,
                lowStockThreshold: input.lowStockThreshold,
                membershipEnabled: input.membershipEnabled,
                memberPricePaise: input.memberPricePaise,
                isActive: input.isActive,
                updatedAt: DateTime.now().toUtc(),
              ),
    ];
    final hasVariants = existing.variants.isNotEmpty || variants.isNotEmpty;
    _replaceProduct(
      existing.copyWith(
        categoryId: categoryId,
        name: normalizedName,
        sku: normalizedSku,
        sellingPricePaise: sellingPricePaise,
        costPricePaise: costPricePaise,
        stockQuantity: hasVariants ? keptStock + newStock : stockQuantity,
        imagePath: imagePath,
        stockUnit: stockUnit,
        lowStockMode: lowStockMode,
        lowStockThreshold: lowStockThreshold,
        membershipEnabled: membershipEnabled,
        memberPricePaise: memberPricePaise,
        isActive: isActive,
        updatedAt: DateTime.now().toUtc(),
        variants: updatedVariants,
      ),
    );
  }

  @override
  Future<void> setProductActive(String id, bool isActive) async {
    _throwIfLoadError();
    final existing = storedProducts.firstWhere(
      (product) => product.id == id,
      orElse: () => throw const UnexpectedInventoryFailure(),
    );
    _replaceProduct(
      existing.copyWith(isActive: isActive, updatedAt: DateTime.now().toUtc()),
    );
  }

  /// Product ids that have variants / sale / purchase / stock history (so a
  /// delete degrades to deactivation). Tests populate this to exercise the
  /// safe path.
  final Set<String> productsWithHistory = {};

  @override
  Future<ProductDeleteResult> deleteProduct(String id) async {
    _throwIfLoadError();
    final existing = storedProducts.firstWhere(
      (product) => product.id == id,
      orElse: () => throw const UnexpectedInventoryFailure(),
    );
    if (productsWithHistory.contains(id)) {
      _replaceProduct(
        existing.copyWith(isActive: false, updatedAt: DateTime.now().toUtc()),
      );
      return ProductDeleteResult.deactivated;
    }
    storedProducts.removeWhere((product) => product.id == id);
    return ProductDeleteResult.deleted;
  }

  Category _requireCategory(String id) => storedCategories.firstWhere(
    (category) => category.id == id,
    orElse: () => throw const UnexpectedInventoryFailure(),
  );

  void _replaceCategory(Category category) {
    final index = storedCategories.indexWhere((c) => c.id == category.id);
    if (index == -1) {
      throw const UnexpectedInventoryFailure();
    }
    storedCategories[index] = category;
  }

  void _replaceProduct(Product product) {
    final index = storedProducts.indexWhere((p) => p.id == product.id);
    if (index == -1) {
      throw const UnexpectedInventoryFailure();
    }
    storedProducts[index] = product;
  }

  static String? _normalizedSku(String? sku) {
    final trimmed = sku?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static void _validatePrices(int sellingPricePaise, int? costPricePaise) {
    if (sellingPricePaise < 0 || (costPricePaise ?? 0) < 0) {
      throw const NegativePriceFailure();
    }
  }

  static void _validateStock(int stockQuantity) {
    if (stockQuantity < 0) {
      throw const NegativeStockFailure();
    }
  }

  static void _validateVariantInputs(List<ProductVariantInput> variants) {
    for (final input in variants) {
      if (input.name.trim().isEmpty) {
        throw const VariantNameRequiredFailure();
      }
      if (input.stockQuantity < 0) {
        throw const NegativeStockFailure();
      }
      if (input.sellingPricePaise < 0 || (input.costPricePaise ?? 0) < 0) {
        throw const NegativePriceFailure();
      }
      if (input.membershipEnabled && input.memberPricePaise == null) {
        throw const MissingMemberPriceFailure();
      }
    }
  }
}
