import 'package:brewflow_pos/core/database/app_database.dart' show AppDatabase;
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repository tests against a real in-memory Drift database: migrations,
/// CHECK constraints, FOREIGN KEY RESTRICT and SQL filtering all behave
/// exactly like production.
void main() {
  late AppDatabase database;
  late DriftInventoryRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftInventoryRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Category> createCategory(String name) =>
      repository.createCategory(name);

  Future<Product> createProduct({
    required String categoryId,
    String name = 'Product',
    String? sku,
    int sellingPricePaise = 100,
    int? costPricePaise,
    int stockQuantity = 0,
    bool isActive = true,
  }) => repository.createProduct(
    categoryId: categoryId,
    name: name,
    sku: sku,
    sellingPricePaise: sellingPricePaise,
    costPricePaise: costPricePaise,
    stockQuantity: stockQuantity,
    isActive: isActive,
  );

  group('categories', () {
    test('createCategory persists the category with a generated id', () async {
      final category = await createCategory('Beverages');

      expect(category.id, isNotEmpty);
      expect(category.name, 'Beverages');
      expect(category.isActive, isTrue);
      expect(category.createdAt.isUtc, isTrue);
      expect(category.updatedAt.isUtc, isTrue);

      final all = await repository.categories();
      expect(all, hasLength(1));
      expect(all.single.name, 'Beverages');
    });

    test('duplicate category names are rejected case-insensitively', () async {
      await createCategory('Beverages');

      await expectLater(
        createCategory('beverages'),
        throwsA(isA<DuplicateCategoryNameFailure>()),
      );
      expect((await repository.categories()), hasLength(1));
    });

    test('renaming to another category name is rejected', () async {
      final first = await createCategory('Beverages');
      await createCategory('Snacks');

      await expectLater(
        repository.updateCategoryName(first.id, 'snacks'),
        throwsA(isA<DuplicateCategoryNameFailure>()),
      );
    });

    test('keeping its own name during rename is allowed', () async {
      final category = await createCategory('Beverages');

      await repository.updateCategoryName(category.id, 'beverages');
      expect((await repository.categories()).single.name, 'beverages');
    });

    test('rename persists the new name', () async {
      final category = await createCategory('Beverages');

      await repository.updateCategoryName(category.id, 'Drinks');
      expect((await repository.categories()).single.name, 'Drinks');
    });

    test('setCategoryActive toggles the flag', () async {
      final category = await createCategory('Beverages');

      await repository.setCategoryActive(category.id, false);
      expect((await repository.categories()).single.isActive, isFalse);

      await repository.setCategoryActive(category.id, true);
      expect((await repository.categories()).single.isActive, isTrue);
    });

    test('deleting an unused category succeeds', () async {
      final category = await createCategory('Beverages');

      await repository.deleteCategory(category.id);
      expect(await repository.categories(), isEmpty);
    });

    test('deleting a category in use throws and keeps the category', () async {
      final category = await createCategory('Beverages');
      await createProduct(categoryId: category.id, name: 'Milk');

      await expectLater(
        repository.deleteCategory(category.id),
        throwsA(isA<CategoryInUseFailure>()),
      );
      expect(await repository.categories(), hasLength(1));
      expect(await repository.products(), hasLength(1));
    });
  });

  group('products', () {
    late Category category;

    setUp(() async {
      category = await createCategory('Beverages');
    });

    test('createProduct persists values exactly in paise', () async {
      final product = await createProduct(
        categoryId: category.id,
        name: 'Milk 1L',
        sku: 'MILK-1L',
        sellingPricePaise: 14950,
        costPricePaise: 12000,
        stockQuantity: 4,
        isActive: true,
      );

      expect(product.id, isNotEmpty);
      expect(product.categoryId, category.id);
      expect(product.sellingPricePaise, 14950);
      expect(product.costPricePaise, 12000);
      expect(product.stockQuantity, 4);
      expect(product.createdAt.isUtc, isTrue);

      final all = await repository.products();
      expect(all, hasLength(1));
      expect(all.single.name, 'Milk 1L');
      expect(all.single.sku, 'MILK-1L');
    });

    test('duplicate SKUs are rejected case-insensitively', () async {
      await createProduct(categoryId: category.id, sku: 'TEA-01');

      await expectLater(
        createProduct(categoryId: category.id, sku: 'tea-01'),
        throwsA(isA<DuplicateSkuFailure>()),
      );
      expect(await repository.products(), hasLength(1));
    });

    test('a product may keep its own SKU when editing', () async {
      final product = await createProduct(
        categoryId: category.id,
        name: 'Tea',
        sku: 'TEA-01',
      );

      await repository.updateProduct(
        id: product.id,
        categoryId: category.id,
        name: 'Green Tea',
        sku: 'tea-01',
        sellingPricePaise: 150,
        costPricePaise: null,
        stockQuantity: 2,
        isActive: true,
      );
      final updated = (await repository.products()).single;
      expect(updated.name, 'Green Tea');
      expect(updated.sku, 'tea-01');
    });

    test('duplicate product names are allowed', () async {
      await createProduct(categoryId: category.id, name: 'Cola');
      await createProduct(categoryId: category.id, name: 'Cola');

      expect(await repository.products(), hasLength(2));
    });

    test('empty SKU text is stored as null', () async {
      final product = await createProduct(categoryId: category.id, sku: '   ');

      expect(product.sku, isNull);
    });

    test('negative prices are rejected', () async {
      await expectLater(
        createProduct(categoryId: category.id, sellingPricePaise: -1),
        throwsA(isA<NegativePriceFailure>()),
      );
      await expectLater(
        createProduct(
          categoryId: category.id,
          sellingPricePaise: 100,
          costPricePaise: -1,
        ),
        throwsA(isA<NegativePriceFailure>()),
      );
    });

    test('negative stock is rejected', () async {
      await expectLater(
        createProduct(categoryId: category.id, stockQuantity: -1),
        throwsA(isA<NegativeStockFailure>()),
      );
    });

    test('updateProduct persists every changed field', () async {
      final product = await createProduct(
        categoryId: category.id,
        name: 'Milk 1L',
        sku: 'MILK-1L',
        sellingPricePaise: 14950,
        costPricePaise: 12000,
        stockQuantity: 4,
      );
      final other = await createCategory('Snacks');

      await repository.updateProduct(
        id: product.id,
        categoryId: other.id,
        name: 'Milk 500ml',
        sku: 'MILK-500',
        sellingPricePaise: 8950,
        costPricePaise: null,
        stockQuantity: 9,
        isActive: false,
      );

      final updated = (await repository.products()).single;
      expect(updated.categoryId, other.id);
      expect(updated.name, 'Milk 500ml');
      expect(updated.sku, 'MILK-500');
      expect(updated.sellingPricePaise, 8950);
      expect(updated.costPricePaise, isNull);
      expect(updated.stockQuantity, 9);
      expect(updated.isActive, isFalse);
    });

    test('products() searches name and SKU case-insensitively', () async {
      await createProduct(
        categoryId: category.id,
        name: 'Milk 1L',
        sku: 'MILK-1L',
      );
      await createProduct(
        categoryId: category.id,
        name: 'Toffee Latte',
        sku: 'LAT-01',
      );

      final byName = await repository.products(search: 'milk');
      expect(byName.map((p) => p.name), ['Milk 1L']);

      final bySku = await repository.products(search: 'lat');
      expect(bySku.map((p) => p.name), ['Toffee Latte']);
    });

    test('products() filters by category', () async {
      await createProduct(categoryId: category.id, name: 'Tea');
      final snacks = await createCategory('Snacks');
      await createProduct(categoryId: snacks.id, name: 'Chips');

      final result = await repository.products(categoryId: snacks.id);
      expect(result.map((p) => p.name), ['Chips']);
    });

    test('products() filters by active state', () async {
      final tea = await createProduct(categoryId: category.id, name: 'Tea');
      await createProduct(categoryId: category.id, name: 'Coffee');
      await repository.setProductActive(tea.id, false);

      final active = await repository.products(
        status: ProductStatusFilter.active,
      );
      expect(active.map((p) => p.name), ['Coffee']);

      final inactive = await repository.products(
        status: ProductStatusFilter.inactive,
      );
      expect(inactive.map((p) => p.name), ['Tea']);

      final all = await repository.products();
      expect(all, hasLength(2));
    });

    test('products() combines search with filters', () async {
      await createProduct(categoryId: category.id, name: 'Chai Latte');
      final chaiCup = await createProduct(
        categoryId: category.id,
        name: 'Chai Cup',
        sku: 'CHAI-CUP',
      );
      await createProduct(categoryId: category.id, name: 'Espresso');
      await repository.setProductActive(chaiCup.id, false);

      final result = await repository.products(
        search: 'chai',
        categoryId: category.id,
        status: ProductStatusFilter.active,
      );
      expect(result.map((p) => p.name), ['Chai Latte']);
    });

    test('results are sorted by name', () async {
      await createProduct(categoryId: category.id, name: 'Banana');
      await createProduct(categoryId: category.id, name: 'Apple');
      await createProduct(categoryId: category.id, name: 'Cherry');

      final result = await repository.products();
      expect(result.map((p) => p.name), ['Apple', 'Banana', 'Cherry']);
    });

    test('setProductActive toggles the flag', () async {
      final product = await createProduct(categoryId: category.id);

      await repository.setProductActive(product.id, false);
      expect((await repository.products()).single.isActive, isFalse);

      await repository.setProductActive(product.id, true);
      expect((await repository.products()).single.isActive, isTrue);
    });
  });
}
