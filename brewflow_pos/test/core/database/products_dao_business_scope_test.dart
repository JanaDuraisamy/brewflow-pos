import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/daos/products_dao.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// ProductsDao.queryForBusiness — Cafe / Food Truck catalogue scoping
///
/// Runs against a real in-memory database rather than the fake repository, so
/// it exercises the actual SQL. The fake mirrors the *intended* scoping rules,
/// which is exactly why a chained-`where()` defect in the DAO could ship with a
/// fully green suite while the real Food Truck catalogue came back empty.
/// ---------------------------------------------------------------------------
void main() {
  late AppDatabase database;
  late ProductsDao products;

  const cafeId = 'shop-cafe';
  const truckId = 'shop-truck';
  const otherTruckId = 'shop-truck-2';

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    products = ProductsDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedShop(String id, String name) async {
    await database
        .into(database.shops)
        .insert(ShopsCompanion.insert(id: Value(id), name: name));
  }

  Future<void> seedCategory(String id, {String name = 'Drinks'}) async {
    await database
        .into(database.categories)
        .insert(CategoriesCompanion.insert(id: Value(id), name: name));
  }

  /// A product owned by [shopId]. [visibleInShops] is the owner-controlled
  /// switch that decides whether another business may see it.
  Future<void> seedProduct({
    required String id,
    required String name,
    required String shopId,
    String? categoryId = 'cat-1',
    bool visibleInShops = false,
    bool isActive = true,
    String? sku,
  }) async {
    await database
        .into(database.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            categoryId: categoryId ?? 'cat-1',
            name: name,
            sku: Value(sku),
            sellingPricePaise: 12000,
            stockQuantity: const Value(5),
            isActive: Value(isActive),
            visibleInShops: Value(visibleInShops),
          ),
        );
  }

  Future<void> seedCatalogue() async {
    await seedShop(cafeId, 'Cafe');
    await seedShop(truckId, 'Food Truck');
    await seedShop(otherTruckId, 'Food Truck 2');
    await seedCategory('cat-1');
    await seedCategory('cat-2', name: 'Snacks');
    // Food Truck's own products.
    await seedProduct(
      id: 'p-truck-1',
      name: 'Truck Latte',
      shopId: truckId,
      sku: 'FT-1',
    );
    await seedProduct(
      id: 'p-truck-2',
      name: 'Truck Vada',
      shopId: truckId,
      categoryId: 'cat-2',
      sku: 'FT-2',
    );
    // Cafe master products, one shared with the truck and one not.
    await seedProduct(
      id: 'p-cafe-shared',
      name: 'Filter Coffee',
      shopId: cafeId,
      visibleInShops: true,
      sku: 'BF-1',
    );
    await seedProduct(
      id: 'p-cafe-private',
      name: 'Cafe Special',
      shopId: cafeId,
      visibleInShops: false,
      sku: 'BF-2',
    );
    // A different business' unshared product must never leak into the truck.
    await seedProduct(
      id: 'p-other-truck',
      name: 'Other Truck Tea',
      shopId: otherTruckId,
      sku: 'FT2-1',
    );
  }

  Future<List<String>> namesFor({
    required String shopId,
    required String catalogOwnerShopId,
    String? search,
    String? categoryId,
    bool? active,
  }) async {
    final rows = await products.queryForBusiness(
      shopId: shopId,
      catalogOwnerShopId: catalogOwnerShopId,
      search: search,
      categoryId: categoryId,
      active: active,
    );
    return rows.map((r) => r.name).toList();
  }

  group('queryForBusiness scoping', () {
    test('Food Truck sees its own products', () async {
      await seedCatalogue();

      final names = await namesFor(shopId: truckId, catalogOwnerShopId: cafeId);

      expect(names, containsAll(['Truck Latte', 'Truck Vada']));
    });

    test(
      'Food Truck sees catalog-owner products only when visibleInShops allows',
      () async {
        await seedCatalogue();

        final names = await namesFor(
          shopId: truckId,
          catalogOwnerShopId: cafeId,
        );

        // Shared Cafe master is visible...
        expect(names, contains('Filter Coffee'));
        // ...but the Cafe's unshared product is not.
        expect(names, isNot(contains('Cafe Special')));
      },
    );

    test("Food Truck never sees another business' unshared products", () async {
      await seedCatalogue();

      final names = await namesFor(shopId: truckId, catalogOwnerShopId: cafeId);

      expect(names, isNot(contains('Other Truck Tea')));
    });

    test('Food Truck results are exactly its own plus shared', () async {
      await seedCatalogue();

      final names = await namesFor(shopId: truckId, catalogOwnerShopId: cafeId);

      expect(names, hasLength(3));
    });

    test('catalog-owner context returns its own products only', () async {
      await seedCatalogue();

      // When both ids are the same the query must collapse to "own products":
      // shared and unshared alike, and nothing from the truck.
      final names = await namesFor(shopId: cafeId, catalogOwnerShopId: cafeId);

      expect(names, containsAll(['Filter Coffee', 'Cafe Special']));
      expect(names, isNot(contains('Truck Latte')));
      expect(names, isNot(contains('Truck Vada')));
      expect(names, hasLength(2));
    });
  });

  group('queryForBusiness regression — the old AND predicate', () {
    test(
      'chained where() calls asked for one row owned by two shops, matching '
      'nothing; the single OR expression returns the Food Truck catalogue',
      () async {
        await seedCatalogue();

        // Reproduce the pre-fix predicate exactly as the DAO built it: two
        // successive where() calls, which Drift combines with AND. For the
        // Food Truck this demands shop_id = truckId AND shop_id = cafeId,
        // which no row can satisfy — the bug behind an always-empty catalogue.
        final legacyQuery = database.select(database.products)
          ..orderBy([(t) => OrderingTerm.asc(t.name)])
          ..where((t) => t.shopId.equals(truckId))
          ..where((t) => t.shopId.equals(cafeId) & t.visibleInShops);
        expect(await legacyQuery.get(), isEmpty);

        // The fixed single-OR predicate returns the rows it should.
        final rows = await products.queryForBusiness(
          shopId: truckId,
          catalogOwnerShopId: cafeId,
        );
        expect(rows, isNotEmpty);
        expect(
          rows.map((r) => r.name),
          containsAll(['Truck Latte', 'Truck Vada', 'Filter Coffee']),
        );
      },
    );
  });

  group('queryForBusiness filters still compose with the scope', () {
    test('category filter applies within the Food Truck scope', () async {
      await seedCatalogue();

      final names = await namesFor(
        shopId: truckId,
        catalogOwnerShopId: cafeId,
        categoryId: 'cat-2',
      );

      expect(names, ['Truck Vada']);
    });

    test('search filter applies within the Food Truck scope', () async {
      await seedCatalogue();

      final names = await namesFor(
        shopId: truckId,
        catalogOwnerShopId: cafeId,
        search: 'latte',
      );

      expect(names, ['Truck Latte']);
    });

    test('active filter still splits active and inactive rows', () async {
      await seedCatalogue();
      await seedProduct(
        id: 'p-truck-off',
        name: 'Truck Disabled',
        shopId: truckId,
        isActive: false,
        sku: 'FT-3',
      );

      final active = await namesFor(
        shopId: truckId,
        catalogOwnerShopId: cafeId,
        active: true,
      );
      expect(active, isNot(contains('Truck Disabled')));

      final inactive = await namesFor(
        shopId: truckId,
        catalogOwnerShopId: cafeId,
        active: false,
      );
      expect(inactive, ['Truck Disabled']);
    });

    test('a category cannot reach a product outside the scope', () async {
      await seedCatalogue();

      // 'Cafe Special' exists but is unshared, so filtering by its category
      // must not surface it to the truck.
      final names = await namesFor(
        shopId: truckId,
        catalogOwnerShopId: cafeId,
        categoryId: 'cat-1',
      );

      expect(names, isNot(contains('Cafe Special')));
      expect(names, contains('Filter Coffee'));
    });
  });
}
