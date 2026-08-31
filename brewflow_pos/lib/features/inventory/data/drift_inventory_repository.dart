import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/core/database/daos/categories_dao.dart';
import 'package:brewflow_pos/core/database/daos/product_variants_dao.dart';
import 'package:brewflow_pos/core/database/daos/products_dao.dart';
import 'package:brewflow_pos/core/database/daos/stock_movements_dao.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/sync/data/sync_outbox_coordinator.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Drift Inventory Repository
///
/// Implements [InventoryRepository] on the local Drift database. All SQL
/// access goes through the Inventory DAOs; all failures are translated into
/// safe [InventoryFailure] values (details logged via [AppLog], never shown).
///
/// Sync (Phase 6.1): when a [SyncOutboxCoordinator] is provided, category,
/// product and variant writes append their outbox rows in the SAME database
/// transaction as the business change; without one the repository behaves
/// exactly as before (offline-first, tests, signed-out usage).
///
/// [createProduct] runs inside one transaction: the product row and (when an
/// opening stock was provided) its single OPENING movement are written
/// together, so a product can never exist whose initial stock lives only in
/// `products.stock_quantity` without the matching audit movement. Variant
/// rows are created in the same transaction, each with its own OPENING
/// movement, and the product's stored stock becomes the sum of variant stock.
///
/// [updateProduct] never touches stock: it replaces the editable product
/// fields, updates existing variants in place (stock untouched), inserts new
/// variants with their OPENING movements and soft-deactivates variants that
/// disappeared from the desired set — history is never deleted.
/// ---------------------------------------------------------------------------

final class DriftInventoryRepository implements InventoryRepository {
  DriftInventoryRepository(
    db.AppDatabase database, {
    SyncOutboxCoordinator? outboxCoordinator,
  }) : _database = database,
       _outbox = outboxCoordinator,
       _categories = CategoriesDao(database),
       _products = ProductsDao(database),
       _variants = ProductVariantsDao(database),
       _movements = StockMovementsDao(database);

  static const String tag = 'Inventory';
  static const Uuid _uuid = Uuid();

  final db.AppDatabase _database;
  final CategoriesDao _categories;
  final ProductsDao _products;
  final ProductVariantsDao _variants;
  final StockMovementsDao _movements;

  /// Null when sync is not wired (tests / signed-out legacy flows).
  final SyncOutboxCoordinator? _outbox;

  @override
  Future<List<Category>> categories() async {
    try {
      final rows = await _categories.getAll();
      return rows.map(_categoryFromRow).toList();
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load categories', error, stackTrace);
    }
  }

  @override
  Future<List<Product>> products({
    String? search,
    String? categoryId,
    ProductStatusFilter status = ProductStatusFilter.all,
  }) async {
    try {
      final rows = await _products.query(
        search: search,
        categoryId: categoryId,
        active: switch (status) {
          ProductStatusFilter.all => null,
          ProductStatusFilter.active => true,
          ProductStatusFilter.inactive => false,
        },
      );
      final variantsByProduct = await _variants.allByProduct();
      return [
        for (final row in rows)
          _productFromRow(row, variants: variantsByProduct[row.id] ?? const []),
      ];
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to load products', error, stackTrace);
    }
  }

  @override
  Future<bool> skuExists(String sku, {String? exceptId}) async {
    try {
      return await _products.skuExists(sku, exceptId: exceptId);
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to check SKU', error, stackTrace);
    }
  }

  @override
  Future<Category> createCategory(String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const UnexpectedInventoryFailure('Category name is required.');
    }
    if (await _categories.nameExists(normalized)) {
      throw const DuplicateCategoryNameFailure();
    }
    try {
      final id = _uuid.v4();
      final now = DateTime.now().toUtc();
      final row = await (_outbox == null
          ? _insertCategory(id: id, name: normalized, now: now)
          : _outbox.run(
              write: () => _insertCategory(id: id, name: normalized, now: now),
              snapshots: (row, context) async => [
                OutboxAppend(
                  entity: MasterEntity.category,
                  entityId: row.id,
                  payload: SyncCategory(
                    id: row.id,
                    shopId: context.shopId,
                    name: row.name,
                    isActive: row.isActive,
                    createdAt: row.createdAt,
                  ).toJson(),
                ),
              ],
            ));
      return _categoryFromRow(row);
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create category', error, stackTrace);
    }
  }

  Future<db.Category> _insertCategory({
    required String id,
    required String name,
    required DateTime now,
  }) => _categories.insert(
    db.CategoriesCompanion.insert(
      id: Value(id),
      name: name,
      createdAt: Value(now),
      updatedAt: Value(now),
    ),
  );

  @override
  Future<void> updateCategoryName(String id, String name) async {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      throw const UnexpectedInventoryFailure('Category name is required.');
    }
    if (await _categories.nameExists(normalized, exceptId: id)) {
      throw const DuplicateCategoryNameFailure();
    }
    try {
      await _writeWithSnapshot(
        entityId: id,
        write: () => _categories.updateName(id, normalized),
        readRow: () => _categories.getById(id),
      );
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to rename category', error, stackTrace);
    }
  }

  @override
  Future<void> setCategoryActive(String id, bool isActive) async {
    try {
      await _writeWithSnapshot(
        entityId: id,
        write: () => _categories.updateActive(id, isActive),
        readRow: () => _categories.getById(id),
      );
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update category', error, stackTrace);
    }
  }

  /// Shared category upsert path: writes, then snapshots the REAL row state,
  /// both inside the outbox transaction when sync is wired.
  Future<void> _writeWithSnapshot({
    required String entityId,
    required Future<void> Function() write,
    required Future<db.Category?> Function() readRow,
  }) {
    final coordinator = _outbox;
    if (coordinator == null) {
      return write();
    }
    return coordinator.run<void>(
      write: write,
      snapshots: (_, context) async {
        final row = await readRow();
        if (row == null) return const [];
        return [
          OutboxAppend(
            entity: MasterEntity.category,
            entityId: row.id,
            payload: SyncCategory(
              id: row.id,
              shopId: context.shopId,
              name: row.name,
              isActive: row.isActive,
              createdAt: row.createdAt,
            ).toJson(),
          ),
        ];
      },
    );
  }

  @override
  Future<void> deleteCategory(String id) async {
    try {
      final coordinator = _outbox;
      Future<void> deleteNow() async {
        final inUse = await _products.countByCategory(id);
        if (inUse > 0) {
          throw const CategoryInUseFailure();
        }
        await _categories.deleteById(id);
      }

      if (coordinator == null) {
        await _database.transaction(deleteNow);
      } else {
        // Hard delete travels as a tombstone so every other device learns it.
        await coordinator.run<void>(
          write: () => _database.transaction(deleteNow),
          snapshots: (_, context) async => [
            OutboxAppend(
              entity: MasterEntity.category,
              entityId: id,
              operation: 'DELETE',
              payload: {'id': id, 'shopId': context.shopId},
            ),
          ],
        );
      }
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to delete category', error, stackTrace);
    }
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
    _validateProductInput(
      name: name,
      sellingPricePaise: sellingPricePaise,
      costPricePaise: costPricePaise,
      stockQuantity: stockQuantity,
      membershipEnabled: membershipEnabled,
      memberPricePaise: memberPricePaise,
    );
    if (variants.isNotEmpty && stockQuantity != 0) {
      // At creation the variants own the stock; an ambiguous product-level
      // opening alongside variants is rejected.
      throw const UnexpectedInventoryFailure(
        'Set stock on the variants instead of the product.',
      );
    }
    _validateVariantInputs(variants);
    final normalizedName = name.trim();
    final normalizedSku = _normalizedSku(sku);
    if (normalizedName.isEmpty) {
      throw const UnexpectedInventoryFailure('Product name is required.');
    }
    if (normalizedSku != null && await _skuExistsAnywhere(normalizedSku)) {
      throw const DuplicateSkuFailure();
    }
    if (variants.isNotEmpty) {
      for (final variant in variants) {
        final variantSku = _normalizedSku(variant.sku);
        if (variantSku != null && await _skuExistsAnywhere(variantSku)) {
          throw const DuplicateVariantSkuFailure();
        }
      }
    }
    // When the product has variants the variant rows own the stock; the
    // product's stored stock mirrors the sum of variant opening stock.
    final effectiveStock = variants.isEmpty
        ? stockQuantity
        : variants.fold(0, (sum, v) => sum + v.stockQuantity);
    Future<Product> doCreate() {
      return _database.transaction(() async {
        final now = DateTime.now().toUtc();
        final row = await _products.insert(
          db.ProductsCompanion.insert(
            categoryId: categoryId,
            name: normalizedName,
            sku: Value(normalizedSku),
            sellingPricePaise: sellingPricePaise,
            costPricePaise: Value(costPricePaise),
            stockQuantity: Value(effectiveStock),
            imagePath: Value(imagePath),
            stockUnit: Value(stockUnit.dbValue),
            lowStockMode: Value(lowStockMode.dbValue),
            lowStockThreshold: Value(lowStockThreshold),
            membershipEnabled: Value(membershipEnabled),
            memberPricePaise: Value(memberPricePaise),
            isActive: Value(isActive),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
        if (variants.isEmpty) {
          await _recordOpeningIfAny(
            productId: row.id,
            quantity: stockQuantity,
            now: now,
          );
        } else {
          for (final variant in variants) {
            final variantRow = await _variants.insert(
              _variantCompanion(productId: row.id, input: variant, now: now),
            );
            await _recordOpeningIfAny(
              productId: row.id,
              variantId: variantRow.id,
              quantity: variant.stockQuantity,
              now: now,
            );
          }
        }
        final variantRows = await _variants.forProduct(row.id);
        return _productFromRow(row, variants: variantRows);
      });
    }

    try {
      final product = await (_outbox == null
          ? doCreate()
          : _outbox.run(
              write: doCreate,
              snapshots: (product, context) async => [
                _productAppend(product, context),
                for (final variant in product.variants)
                  _variantAppend(variant, context),
              ],
            ));
      return product;
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to create product', error, stackTrace);
    }
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
    _validateProductInput(
      name: name,
      sellingPricePaise: sellingPricePaise,
      costPricePaise: costPricePaise,
      stockQuantity: stockQuantity,
      membershipEnabled: membershipEnabled,
      memberPricePaise: memberPricePaise,
    );
    _validateVariantInputs(variants);
    final normalizedName = name.trim();
    final normalizedSku = _normalizedSku(sku);
    if (normalizedName.isEmpty) {
      throw const UnexpectedInventoryFailure('Product name is required.');
    }
    if (normalizedSku != null &&
        await _skuExistsAnywhere(normalizedSku, exceptProductId: id)) {
      throw const DuplicateSkuFailure();
    }
    final existing = await _variants.forProduct(id);
    final existingById = {for (final v in existing) v.id: v};
    final updateIds = <String>{};
    for (final variant in variants) {
      final variantId = variant.id;
      final variantSku = _normalizedSku(variant.sku);
      if (variantId == null) {
        if (variantSku != null && await _skuExistsAnywhere(variantSku)) {
          throw const DuplicateVariantSkuFailure();
        }
      } else {
        updateIds.add(variantId);
        if (existingById[variantId] == null) {
          // A stale edit screen sent an id this product does not own; treat
          // the variant as missing rather than silently writing a foreign
          // row (the id is regenerated as a new variant below instead).
          throw const UnexpectedInventoryFailure(
            'A variant in this edit is no longer part of the product.',
          );
        }
        if (variantSku != null &&
            await _skuExistsAnywhere(variantSku, exceptVariantId: variantId)) {
          throw const DuplicateVariantSkuFailure();
        }
      }
    }
    Future<void> doUpdate() {
      return _database.transaction(() async {
        final now = DateTime.now().toUtc();

        // The desired stock mirror: for products with variants it is the sum
        // of the (preserved) existing variant stock plus the opening stock of
        // newly added variants — never the caller's number. Products without
        // variants keep the caller's unchanged stock figure.
        final existingStockSum = existing.fold(
          0,
          (sum, v) => sum + v.stockQuantity,
        );
        final newOpeningSum = variants
            .where((v) => v.id == null)
            .fold(0, (sum, v) => sum + v.stockQuantity);
        final effectiveStock = existing.isNotEmpty || variants.isNotEmpty
            ? existingStockSum + newOpeningSum
            : stockQuantity;

        await _products.update(
          id,
          db.ProductsCompanion(
            categoryId: Value(categoryId),
            name: Value(normalizedName),
            sku: Value(normalizedSku),
            sellingPricePaise: Value(sellingPricePaise),
            costPricePaise: Value(costPricePaise),
            stockQuantity: Value(effectiveStock),
            imagePath: Value(imagePath),
            stockUnit: Value(stockUnit.dbValue),
            lowStockMode: Value(lowStockMode.dbValue),
            lowStockThreshold: Value(lowStockThreshold),
            membershipEnabled: Value(membershipEnabled),
            memberPricePaise: Value(memberPricePaise),
            isActive: Value(isActive),
          ),
        );

        for (final variant in variants) {
          final variantId = variant.id;
          if (variantId != null) {
            // Update in place — stock is never touched by an edit.
            await _variants.update(
              variantId,
              db.ProductVariantsCompanion(
                name: Value(variant.name.trim()),
                sku: Value(_normalizedSku(variant.sku)),
                sellingPricePaise: Value(variant.sellingPricePaise),
                costPricePaise: Value(variant.costPricePaise),
                lowStockMode: Value(variant.lowStockMode.dbValue),
                lowStockThreshold: Value(variant.lowStockThreshold),
                membershipEnabled: Value(variant.membershipEnabled),
                memberPricePaise: Value(variant.memberPricePaise),
                isActive: Value(variant.isActive),
              ),
            );
          } else {
            final variantRow = await _variants.insert(
              _variantCompanion(productId: id, input: variant, now: now),
            );
            await _recordOpeningIfAny(
              productId: id,
              variantId: variantRow.id,
              quantity: variant.stockQuantity,
              now: now,
            );
          }
        }

        // Any existing variant missing from the desired set is soft-
        // deactivated — its history stays intact and its stock is preserved.
        if (existing.isNotEmpty) {
          await _variants.deactivateMissing(id, updateIds);
        }
      });
    }

    try {
      final write = _outbox == null
          ? doUpdate()
          : _outbox.run(
              write: doUpdate,
              snapshots: (_, context) async {
                final row = await _products.byId(id);
                // ignore: avoid_print
                print('updateProduct snapshot id=$id row=${row?.name}');
                if (row == null) return const [];
                final variantRows = await _variants.forProduct(id);
                return [
                  _productAppend(
                    _productFromRow(row, variants: variantRows),
                    context,
                  ),
                  for (final variant in variantRows)
                    _variantAppend(_variantFromRow(variant), context),
                ];
              },
            );
      await write;
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update product', error, stackTrace);
    }
  }

  @override
  Future<void> setProductActive(String id, bool isActive) async {
    try {
      final coordinator = _outbox;
      await (coordinator == null
          ? _products.updateActive(id, isActive)
          : coordinator.run<void>(
              write: () => _products.updateActive(id, isActive),
              snapshots: (_, context) async {
                final row = await _products.byId(id);
                if (row == null) return const [];
                return [_productAppend(_productFromRow(row), context)];
              },
            ));
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to update product', error, stackTrace);
    }
  }

  @override
  Future<ProductDeleteResult> deleteProduct(String id) async {
    try {
      // Decide the branch once: a product that is referenced (variants, sale
      // lines, purchase lines or stock movements) degrades to a safe soft
      // deactivation; a fully unreferenced one is hard-deleted.
      final decision = await _database.transaction(() async {
        final row = await _products.byId(id);
        if (row == null) {
          throw const UnexpectedInventoryFailure('Product not found.');
        }
        final referenced = await _products.countReferences(id) > 0;
        return (referenced: referenced, row: row);
      });

      final coordinator = _outbox;
      Future<ProductDeleteResult> commit() async {
        if (decision.referenced) {
          await _products.updateActive(id, false);
          return ProductDeleteResult.deactivated;
        }
        await _products.deleteById(id);
        return ProductDeleteResult.deleted;
      }

      if (coordinator == null) {
        return _database.transaction(commit);
      }
      return coordinator.run<ProductDeleteResult>(
        write: () => _database.transaction(commit),
        snapshots: (_, context) async {
          if (decision.referenced) {
            return [_productAppend(_productFromRow(decision.row), context)];
          }
          return [
            OutboxAppend(
              entity: MasterEntity.product,
              entityId: id,
              operation: 'DELETE',
              payload: {'id': id, 'shopId': context.shopId},
            ),
          ];
        },
      );
    } on InventoryFailure {
      rethrow;
    } on Exception catch (error, stackTrace) {
      throw _unexpected('Failed to delete product', error, stackTrace);
    }
  }

  /// Whether a SKU is taken by a product or a variant (the catalog treats
  /// SKUs as one namespace; both tables enforce uniqueness within
  /// themselves).
  Future<bool> _skuExistsAnywhere(
    String sku, {
    String? exceptProductId,
    String? exceptVariantId,
  }) async {
    if (await _products.skuExists(sku, exceptId: exceptProductId)) {
      return true;
    }
    return _variants.skuExists(sku, exceptId: exceptVariantId);
  }

  // ---- Sync payload builders (Phase 6.1) -----------------------------------
  //
  // imagePath is deliberately NOT part of the wire contract: image files are
  // device-local until a storage phase exists.

  static OutboxAppend _productAppend(
    Product product,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.product,
    entityId: product.id,
    payload: SyncProduct(
      id: product.id,
      shopId: context.shopId,
      categoryId: product.categoryId,
      name: product.name,
      sku: product.sku,
      sellingPricePaise: product.sellingPricePaise,
      costPricePaise: product.costPricePaise,
      stockQuantity: product.stockQuantity,
      stockUnit: switch (product.stockUnit) {
        StockUnit.count => SyncStockUnit.count,
        StockUnit.ml => SyncStockUnit.ml,
        StockUnit.gram => SyncStockUnit.gram,
        StockUnit.kg => SyncStockUnit.kg,
        StockUnit.none => SyncStockUnit.none,
      },
      lowStockMode: switch (product.lowStockMode) {
        LowStockMode.useDefault => SyncLowStockMode.useDefault,
        LowStockMode.custom => SyncLowStockMode.custom,
        LowStockMode.off => SyncLowStockMode.off,
      },
      lowStockThreshold: product.lowStockThreshold,
      membershipEnabled: product.membershipEnabled,
      memberPricePaise: product.memberPricePaise,
      isActive: product.isActive,
      createdAt: product.createdAt,
    ).toJson(),
  );

  static OutboxAppend _variantAppend(
    ProductVariant variant,
    SyncSessionContext context,
  ) => OutboxAppend(
    entity: MasterEntity.productVariant,
    entityId: variant.id,
    payload: SyncProductVariant(
      id: variant.id,
      shopId: context.shopId,
      productId: variant.productId,
      name: variant.name,
      sku: variant.sku,
      sellingPricePaise: variant.sellingPricePaise,
      costPricePaise: variant.costPricePaise,
      stockQuantity: variant.stockQuantity,
      lowStockMode: switch (variant.lowStockMode) {
        LowStockMode.useDefault => SyncLowStockMode.useDefault,
        LowStockMode.custom => SyncLowStockMode.custom,
        LowStockMode.off => SyncLowStockMode.off,
      },
      lowStockThreshold: variant.lowStockThreshold,
      membershipEnabled: variant.membershipEnabled,
      memberPricePaise: variant.memberPricePaise,
      isActive: variant.isActive,
      createdAt: variant.createdAt,
    ).toJson(),
  );

  /// Writes one OPENING movement for a positive opening stock of a stock
  /// entity (product, or variant when [variantId] is given).
  Future<void> _recordOpeningIfAny({
    required String productId,
    String? variantId,
    required int quantity,
    required DateTime now,
  }) async {
    if (quantity <= 0) {
      return;
    }
    await _movements.insert(
      db.StockMovementsCompanion.insert(
        productId: productId,
        variantId: Value(variantId),
        movementType: StockMovementType.opening.dbValue,
        quantity: quantity,
        stockBefore: 0,
        stockAfter: quantity,
        reason: const Value(null),
        note: const Value(null),
        referenceType: const Value(null),
        referenceId: const Value(null),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  static db.ProductVariantsCompanion _variantCompanion({
    required String productId,
    required ProductVariantInput input,
    required DateTime now,
  }) => db.ProductVariantsCompanion.insert(
    productId: productId,
    name: input.name.trim(),
    sku: Value(_normalizedSku(input.sku)),
    sellingPricePaise: input.sellingPricePaise,
    costPricePaise: Value(input.costPricePaise),
    stockQuantity: Value(input.stockQuantity),
    lowStockMode: Value(input.lowStockMode.dbValue),
    lowStockThreshold: Value(input.lowStockThreshold),
    membershipEnabled: Value(input.membershipEnabled),
    memberPricePaise: Value(input.memberPricePaise),
    isActive: Value(input.isActive),
    createdAt: Value(now),
    updatedAt: Value(now),
  );

  static void _validateProductInput({
    required String name,
    required int sellingPricePaise,
    required int? costPricePaise,
    required int stockQuantity,
    required bool membershipEnabled,
    required int? memberPricePaise,
  }) {
    if (name.trim().isEmpty) {
      throw const UnexpectedInventoryFailure('Product name is required.');
    }
    _validatePrices(sellingPricePaise, costPricePaise);
    _validateStock(stockQuantity);
    _validateMemberPrice(membershipEnabled, memberPricePaise);
  }

  static void _validateVariantInputs(List<ProductVariantInput> variants) {
    for (final variant in variants) {
      if (variant.name.trim().isEmpty) {
        throw const VariantNameRequiredFailure();
      }
      _validatePrices(variant.sellingPricePaise, variant.costPricePaise);
      _validateStock(variant.stockQuantity);
      _validateMemberPrice(variant.membershipEnabled, variant.memberPricePaise);
    }
  }

  static void _validateMemberPrice(
    bool membershipEnabled,
    int? memberPricePaise,
  ) {
    if (membershipEnabled && memberPricePaise == null) {
      throw const MissingMemberPriceFailure();
    }
    if (memberPricePaise != null && memberPricePaise < 0) {
      throw const NegativePriceFailure();
    }
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

  Never _unexpected(String message, Object error, StackTrace stackTrace) {
    AppLog.error(message, tag: tag, error: error, stackTrace: stackTrace);
    throw const UnexpectedInventoryFailure();
  }

  static Category _categoryFromRow(db.Category row) => Category(
    id: row.id,
    name: row.name,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static Product _productFromRow(
    db.Product row, {
    List<db.ProductVariant> variants = const [],
  }) => Product(
    id: row.id,
    categoryId: row.categoryId,
    name: row.name,
    sku: row.sku,
    sellingPricePaise: row.sellingPricePaise,
    costPricePaise: row.costPricePaise,
    stockQuantity: variants.isEmpty
        ? row.stockQuantity
        : variants.fold(0, (sum, v) => sum + v.stockQuantity),
    imagePath: row.imagePath,
    stockUnit: StockUnit.fromDbValue(row.stockUnit),
    lowStockMode: LowStockMode.fromDbValue(row.lowStockMode),
    lowStockThreshold: row.lowStockThreshold,
    membershipEnabled: row.membershipEnabled,
    memberPricePaise: row.memberPricePaise,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    variants: [for (final v in variants) _variantFromRow(v)],
  );

  static ProductVariant _variantFromRow(db.ProductVariant row) =>
      ProductVariant(
        id: row.id,
        productId: row.productId,
        name: row.name,
        sku: row.sku,
        sellingPricePaise: row.sellingPricePaise,
        costPricePaise: row.costPricePaise,
        stockQuantity: row.stockQuantity,
        lowStockMode: LowStockMode.fromDbValue(row.lowStockMode),
        lowStockThreshold: row.lowStockThreshold,
        membershipEnabled: row.membershipEnabled,
        memberPricePaise: row.memberPricePaise,
        isActive: row.isActive,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
}
