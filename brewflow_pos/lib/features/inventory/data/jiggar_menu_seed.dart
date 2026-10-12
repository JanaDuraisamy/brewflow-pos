import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — JIGGAR Tea House menu seed (P0 master data)
///
/// One-time idempotent import of the shop's LED-board menu into the EXISTING
/// master-data system. Everything goes through [InventoryRepository], so:
///   - duplicate-name rules still apply (case-insensitive, per category),
///   - every created/updated row is enqueued to the sync outbox atomically
///     and reaches other devices through the normal Supabase path,
///   - re-running the seed never duplicates anything (it reports skips).
///
/// Money: integer paise (₹1 = 100). Stock: made-to-order items use
/// [StockUnit.none] with zero quantity — billing treats NONE as untracked
/// (P0 FIX 2), so no artificial inventory numbers are ever invented here.
/// Variant products (SPL Milk Chai sizes, SPL Milkshakes flavours) carry
/// their own per-variant prices and zero opening stock for the same reason.
///
/// Names/prices are transcribed verbatim from the two LED boards. Known
/// board spellings are preserved deliberately (see [spellingNotes]).
/// ---------------------------------------------------------------------------

final class SeedVariant {
  const SeedVariant(this.name, this.sellingPriceRupees);
  final String name;
  final int sellingPriceRupees;
}

final class SeedProduct {
  const SeedProduct(
    this.name,
    this.sellingPriceRupees, {
    this.variants = const [],
  });

  /// Verbatim board name; single price when [variants] is empty.
  final String name;

  /// Display price in rupees; ignored for variant products (each variant
  /// carries its own price). Kept for shelf display parity with the board.
  final int sellingPriceRupees;
  final List<SeedVariant> variants;
}

final class SeedCategory {
  const SeedCategory(this.name, this.products);
  final String name;
  final List<SeedProduct> products;
}

final class MenuSeedResult {
  MenuSeedResult();
  int categoriesCreated = 0;
  int categoriesSkipped = 0;
  int productsCreated = 0;
  int variantsCreated = 0;
  int productsUpdated = 0;
  int productsSkipped = 0;

  /// Shared-stock ingredient products ensured by this run.
  int ingredientsEnsured = 0;

  /// Maggie dish → packet recipe mappings written by this run.
  int recipesMapped = 0;

  /// Dishes left unwired (missing dish/packet, non-ingredient packet, empty
  /// packet stock or an existing mapping the seed never overwrites).
  int recipesSkipped = 0;

  @override
  String toString() =>
      '$categoriesCreated categories & $productsCreated products created '
      '($variantsCreated variants), $productsUpdated updated, '
      '$productsSkipped already up to date. '
      '$ingredientsEnsured shared-stock ingredients ensured, '
      '$recipesMapped recipes mapped ($recipesSkipped skipped).';
}

final class JiggarMenuSeeder {
  JiggarMenuSeeder(this._repository);

  static const String tag = 'MenuSeed';

  /// The shared physical stock behind every Maggie dish: one packet consumed
  /// per dish sold. An ordinary tracked product (purchased through Purchases,
  /// alerted through the low-stock rules, synced like any other); the
  /// ingredient flag only hides it from the sale shelf.
  static const String sharedStockPacketName = 'Maggi Packet';

  /// Maggie dishes wired to the shared packet, one product-level recipe each
  /// (variantId null). Board spellings first, then the live-menu spellings a
  /// shop may already use — whatever exists gets mapped, the rest is skipped
  /// and reported. Separate products can never double-deduct: a recipe row
  /// matches only its own product id.
  static const List<String> sharedStockDishNames = [
    'Classic Maggie',
    'Egg Maggie',
    'Cheese Maggie',
    'Plain Maggi',
    'Cheese Maggi',
    'Veg Maggi',
    'Egg Maggi',
    'Masala Maggi',
  ];

  static const List<SeedCategory> menu = [
    SeedCategory('MILK & CHAI', [
      SeedProduct('Plain Milk', 15),
      SeedProduct('Horlicks, Boost, Maltova', 25),
      SeedProduct(
        'SPL Milk Chai',
        15,
        variants: [SeedVariant('100ml', 15), SeedVariant('160ml', 20)],
      ),
      SeedProduct('Chocolate Chai', 25),
      SeedProduct('Ginger / Cardamom Chai', 25),
    ]),
    SeedCategory('TEA', [
      SeedProduct('Black Tea', 12),
      SeedProduct('Green Tea', 20),
      SeedProduct('Lemon Tea', 20),
      SeedProduct('Hibiscus Tea', 25),
      SeedProduct('Butterfly Pea Tea', 25),
      SeedProduct('Stress Relief Tea', 30),
      SeedProduct('Sleep Tea', 30),
      SeedProduct('Belly Fat Tea', 30),
    ]),
    SeedCategory('COFFEE', [
      SeedProduct('Black Coffee', 15),
      SeedProduct('Filter Coffee', 25),
      SeedProduct('Hazelnut Coffee', 30),
      SeedProduct('Iris Coffee', 30),
      SeedProduct('Chocolate Coffee', 30),
    ]),
    SeedCategory('MAGGIE', [
      SeedProduct('Classic Maggie', 50),
      SeedProduct('Egg Maggie', 60),
      SeedProduct('Cheese Maggie', 70),
    ]),
    SeedCategory('FRIES', [
      SeedProduct('Classic Fries', 100),
      SeedProduct('Masala Fries', 100),
    ]),
    SeedCategory('JIGARTHANDA', [
      SeedProduct('Normal Jigarthanda', 70),
      SeedProduct('Special Jigarthanda', 90),
      SeedProduct('Super SPL Jigarthanda', 105),
      SeedProduct('Rose Milk', 50),
      SeedProduct(
        'SPL Milkshakes',
        100,
        variants: [
          SeedVariant('Mango', 100),
          SeedVariant('Vanilla', 100),
          SeedVariant('Strawberry', 100),
        ],
      ),
    ]),
    SeedCategory('DUET KULFI (NATURAL)', [
      SeedProduct('Bombay Malai', 45),
      SeedProduct('Meetha Paan', 45),
      SeedProduct('Malai / Chocolate', 45),
      SeedProduct('Malai / Pista', 45),
      SeedProduct('Strawberry / Litchi', 45),
      SeedProduct('Mango / Litchi', 45),
      SeedProduct('Strawberry / Mango', 45),
      SeedProduct('Blueberry / Blackcurrent', 45),
      SeedProduct('Blueberry / Mango', 45),
    ]),
    SeedCategory('POPSICLES (NATURAL)', [
      SeedProduct('Allpanso Mango', 65),
      SeedProduct('Rose Gulkan', 65),
      SeedProduct('Chocolate Brownie', 65),
      SeedProduct('Coffee Almond', 65),
      SeedProduct('Kitkat Popsicle', 65),
      SeedProduct('Gems Popsicle', 65),
    ]),
  ];

  /// Board spellings kept verbatim on purpose (no silent corrections):
  static const List<String> spellingNotes = [
    'Allpanso Mango',
    'Blackcurrent',
    'Iris Coffee',
    'MAGGIE',
  ];

  final InventoryRepository _repository;

  /// Runs the idempotent import. Never deletes anything; existing matching
  /// rows are reconciled (price/variant corrections) or skipped.
  Future<MenuSeedResult> run() async {
    final result = MenuSeedResult();

    final existingCategories = await _repository.categories();
    final categoryByName = {
      for (final category in existingCategories)
        category.name.toLowerCase(): category,
    };
    // Catalog loaded ONCE; lookups below filter by categoryId.
    final existingProducts = await _repository.products();

    for (final seedCategory in menu) {
      final key = seedCategory.name.toLowerCase();
      var category = categoryByName[key];
      if (category == null) {
        category = await _repository.createCategory(seedCategory.name);
        categoryByName[key] = category;
        result.categoriesCreated += 1;
      } else {
        result.categoriesSkipped += 1;
      }

      final productByName = {
        for (final product in existingProducts)
          if (product.categoryId == category.id)
            product.name.toLowerCase(): product,
      };

      for (final seedProduct in seedCategory.products) {
        final existing = productByName[seedProduct.name.toLowerCase()];
        if (existing == null) {
          await _createProduct(category.id, seedProduct);
          result.productsCreated += 1;
          result.variantsCreated += seedProduct.variants.length;
          continue;
        }

        final changed = await _reconcileProduct(existing, seedProduct);
        if (changed) {
          result.productsUpdated += 1;
        } else {
          result.productsSkipped += 1;
        }
      }
    }
    await _ensureSharedStock(result);
    return result;
  }

  /// Wires the Maggie dishes to the shared Maggi Packet through the normal
  /// recipe repository (one product-level row per dish, quantity 1).
  ///
  /// Additive and never destructive: products are only created, never edited
  /// or restocked, and a dish that already carries ANY recipe rows keeps them
  /// untouched. A dish is skipped — never force-mapped — when the packet is
  /// missing, is not a tracked ingredient, or holds no stock: mapping a dish
  /// to an empty source would turn every Maggi sale into an
  /// INSUFFICIENT_STOCK failure. The owner stocks the packet through
  /// Purchases and re-runs the import to complete the wiring; every skip is
  /// logged with its reason.
  ///
  /// Like the rest of this seeder the step resolves in the active shop, so a
  /// second business wires its own packet and mappings on its own import run.
  Future<void> _ensureSharedStock(MenuSeedResult result) async {
    final categories = await _repository.categories();
    Category? maggie;
    for (final category in categories) {
      if (category.name.toLowerCase() == 'maggie') {
        maggie = category;
        break;
      }
    }
    if (maggie == null) {
      AppLog.info(
        'Shared stock skipped: no MAGGIE category (owner removed it)',
        tag: tag,
      );
      return;
    }

    final products = await _repository.products();
    Product? packet;
    for (final product in products) {
      if (product.categoryId == maggie.id &&
          product.name.toLowerCase() == sharedStockPacketName.toLowerCase()) {
        packet = product;
        break;
      }
    }
    if (packet == null) {
      packet = await _repository.createProduct(
        categoryId: maggie.id,
        name: sharedStockPacketName,
        // Never sold at the counter (hidden by the ingredient flag); the
        // price is meaningless and stays an honest zero.
        sellingPricePaise: 0,
        // Never invent an opening balance: the owner stocks the packet
        // through Purchases, which is also what restocks it later.
        stockQuantity: 0,
        stockUnit: StockUnit.count,
        isIngredient: true,
        isActive: true,
      );
      result.ingredientsEnsured += 1;
    }
    final source = packet;

    // Someone's live configuration (a same-named normal product, or an
    // untracked row) is never reinterpreted as our stock source, and a dish
    // is never mapped to an empty source (every Maggi sale would fail).
    final packetUsable =
        source.isIngredient &&
        source.stockUnit != StockUnit.none &&
        source.stockQuantity > 0;
    if (!packetUsable) {
      AppLog.info(
        'Shared stock wiring deferred for ${source.name}: stock it through '
        'Purchases as a tracked ingredient, then re-run the import',
        tag: tag,
      );
    }

    final dishByName = {
      for (final product in products)
        if (product.categoryId == maggie.id)
          product.name.toLowerCase(): product,
    };
    for (final dishName in sharedStockDishNames) {
      final dish = dishByName[dishName.toLowerCase()];
      if (dish == null) continue;
      if ((await _repository.recipesForProduct(dish.id)).isNotEmpty) {
        AppLog.info(
          'Shared stock kept: ${dish.name} already has a recipe mapping',
          tag: tag,
        );
        result.recipesSkipped += 1;
        continue;
      }
      if (!packetUsable) {
        result.recipesSkipped += 1;
        continue;
      }
      await _repository.setRecipe(
        productId: dish.id,
        ingredients: [RecipeIngredientInput(ingredientProductId: source.id)],
      );
      result.recipesMapped += 1;
    }
  }

  Future<void> _createProduct(String categoryId, SeedProduct seed) async {
    await _repository.createProduct(
      categoryId: categoryId,
      name: seed.name,
      sellingPricePaise: seed.sellingPriceRupees * 100,
      stockQuantity: 0,
      stockUnit: StockUnit.none,
      lowStockMode: LowStockMode.off,
      membershipEnabled: false,
      isActive: true,
      variants: [
        for (final variant in seed.variants)
          ProductVariantInput(
            name: variant.name,
            sellingPricePaise: variant.sellingPriceRupees * 100,
            stockQuantity: 0,
            lowStockMode: LowStockMode.off,
            isActive: true,
          ),
      ],
    );
  }

  /// Reconciles an existing row with the board: corrects the selling price,
  /// missing/mispriced variants and legacy tracked-stock units while
  /// PRESERVING variant identities (ids) and every stock quantity. Returns
  /// true when any write was made.
  Future<bool> _reconcileProduct(Product existing, SeedProduct seed) async {
    var dirty = false;

    var sellingPricePaise = existing.sellingPricePaise;
    final desiredPlainPrice = seed.sellingPriceRupees * 100;
    final hasVariantsNow = existing.variants.isNotEmpty;
    if (!hasVariantsNow &&
        seed.variants.isEmpty &&
        sellingPricePaise != desiredPlainPrice) {
      sellingPricePaise = desiredPlainPrice;
      dirty = true;
    }
    if (existing.stockUnit != StockUnit.none ||
        existing.lowStockMode != LowStockMode.off) {
      dirty = true;
    }

    // Variant reconciliation by lowercase name; extra local variants stay
    // untouched (never deleted by the seed).
    final existingByName = {
      for (final variant in existing.variants)
        variant.name.toLowerCase(): variant,
    };
    final variantInputs = <ProductVariantInput>[];
    for (final desired in seed.variants) {
      final paise = desired.sellingPriceRupees * 100;
      final match = existingByName[desired.name.toLowerCase()];
      if (match == null) {
        dirty = true;
        variantInputs.add(
          ProductVariantInput(
            name: desired.name,
            sellingPricePaise: paise,
            stockQuantity: 0,
            lowStockMode: LowStockMode.off,
            isActive: true,
          ),
        );
        continue;
      }
      final same =
          match.sellingPricePaise == paise &&
          match.isActive &&
          match.lowStockMode == LowStockMode.off;
      variantInputs.add(
        ProductVariantInput(
          id: match.id,
          name: match.name,
          sku: match.sku,
          sellingPricePaise: paise,
          costPricePaise: match.costPricePaise,
          stockQuantity: match.stockQuantity,
          lowStockMode: LowStockMode.off,
          lowStockThreshold: match.lowStockThreshold,
          membershipEnabled: match.membershipEnabled,
          memberPricePaise: match.memberPricePaise,
          isActive: true,
        ),
      );
      if (!same) dirty = true;
    }
    // Carry over untouched local variants so updateProduct never sees an
    // incomplete desired set (missing ids would soft-deactivate them).
    for (final variant in existing.variants) {
      final seeded = seed.variants.any(
        (d) => d.name.toLowerCase() == variant.name.toLowerCase(),
      );
      if (!seeded) {
        variantInputs.add(
          ProductVariantInput(
            id: variant.id,
            name: variant.name,
            sku: variant.sku,
            sellingPricePaise: variant.sellingPricePaise,
            costPricePaise: variant.costPricePaise,
            stockQuantity: variant.stockQuantity,
            lowStockMode: variant.lowStockMode,
            lowStockThreshold: variant.lowStockThreshold,
            membershipEnabled: variant.membershipEnabled,
            memberPricePaise: variant.memberPricePaise,
            isActive: variant.isActive,
          ),
        );
      }
    }

    if (!dirty) return false;

    await _repository.updateProduct(
      id: existing.id,
      categoryId: existing.categoryId,
      name: existing.name,
      sku: existing.sku,
      sellingPricePaise: sellingPricePaise,
      costPricePaise: existing.costPricePaise,
      stockQuantity: existing.stockQuantity,
      imagePath: existing.imagePath,
      stockUnit: StockUnit.none,
      lowStockMode: LowStockMode.off,
      lowStockThreshold: existing.lowStockThreshold,
      membershipEnabled: existing.membershipEnabled,
      memberPricePaise: existing.memberPricePaise,
      isActive: true,
      variants: variantInputs,
    );
    return true;
  }
}
