import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inventory_repository.dart';

void main() {
  late FakeInventoryRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [inventoryRepositoryProvider.overrideWithValue(fake)],
  );

  final now = DateTime.now().toUtc();

  Category category(String id, String name, {bool isActive = true}) => Category(
    id: id,
    name: name,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  Product product(
    String id,
    String name, {
    String categoryId = 'c1',
    String? sku,
    int sellingPricePaise = 100,
    bool isActive = true,
  }) => Product(
    id: id,
    categoryId: categoryId,
    name: name,
    sku: sku,
    sellingPricePaise: sellingPricePaise,
    costPricePaise: null,
    stockQuantity: 0,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() => fake = FakeInventoryRepository());

  /// Waits (in real async) for invalidation-triggered rebuilds to settle,
  /// since reading `.future` right after a mutation can race the rebuild.
  Future<void> awaitUntil(
    ProviderContainer container,
    bool Function() condition,
  ) async {
    for (var i = 0; i < 200; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('condition was not met within the timeout');
  }

  group('categoriesProvider', () {
    test('starts loading and resolves to the stored categories', () async {
      fake.storedCategories.addAll([
        category('c2', 'Snacks'),
        category('c1', 'Beverages'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(categoriesProvider), isA<AsyncLoading>());
      await container.read(categoriesProvider.future);

      final categories = container.read(categoriesProvider).value!;
      // Sorted by name by the repository.
      expect(categories.map((c) => c.name), ['Beverages', 'Snacks']);
      expect(fake.categoriesCalls, 1);
    });

    test('resolves to empty when there are no categories', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(categoriesProvider.future);
      expect(container.read(categoriesProvider).value, isEmpty);
    });

    test('surfaces InventoryFailure without wrapping it', () async {
      fake.loadError = const DuplicateCategoryNameFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(categoriesProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(categoriesProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<DuplicateCategoryNameFailure>());
    });

    test('maps unexpected errors to UnexpectedInventoryFailure', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(categoriesProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(categoriesProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedInventoryFailure>());
    });

    test('create refreshes the list', () async {
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(categoriesProvider.future);
      expect(container.read(categoriesProvider).value, isEmpty);

      await container.read(categoriesProvider.notifier).create('Beverages');
      await awaitUntil(
        container,
        () => (container.read(categoriesProvider).value ?? const <Category>[])
            .isNotEmpty,
      );

      expect(
        container.read(categoriesProvider).value!.single.name,
        'Beverages',
      );
    });

    test('rename errors surface the safe duplicate message', () async {
      fake.storedCategories.addAll([
        category('c1', 'Beverages'),
        category('c2', 'Snacks'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(categoriesProvider.future);

      await expectLater(
        container.read(categoriesProvider.notifier).rename('c2', 'beverages'),
        throwsA(isA<DuplicateCategoryNameFailure>()),
      );
    });

    test('delete removes the category and refreshes', () async {
      fake.storedCategories.add(category('c1', 'Beverages'));
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(categoriesProvider.future);

      await container.read(categoriesProvider.notifier).delete('c1');
      await awaitUntil(
        container,
        () => container.read(categoriesProvider).value?.isEmpty ?? false,
      );

      expect(container.read(categoriesProvider).value, isEmpty);
    });
  });

  group('productsProvider', () {
    test('resolves to products, initially loading', () async {
      fake.storedProducts.addAll([product('p1', 'Milk'), product('p2', 'Tea')]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(productsProvider), isA<AsyncLoading>());
      await container.read(productsProvider.future);

      expect(container.read(productsProvider).value, hasLength(2));
    });

    test('rebuilds when the search query changes', () async {
      fake.storedProducts.addAll([
        product('p1', 'Milk 1L'),
        product('p2', 'Chai Latte', sku: 'MILK-LAT'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      container.read(inventoryFilterProvider.notifier).setQuery('milk');

      await container.read(productsProvider.future);
      expect(container.read(productsProvider).value!.map((p) => p.name), [
        'Chai Latte',
        'Milk 1L',
      ]);
    });

    test('rebuilds when the status filter changes', () async {
      fake.storedProducts.addAll([
        product('p1', 'Milk', isActive: true),
        product('p2', 'Tea', isActive: false),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      container
          .read(inventoryFilterProvider.notifier)
          .setStatus(ProductStatusFilter.inactive);

      await container.read(productsProvider.future);
      expect(container.read(productsProvider).value!.map((p) => p.name), [
        'Tea',
      ]);
    });

    test('rebuilds when the category filter changes', () async {
      fake.storedProducts.addAll([
        product('p1', 'Milk', categoryId: 'c1'),
        product('p2', 'Chips', categoryId: 'c2'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      container.read(inventoryFilterProvider.notifier).setCategory('c2');

      await container.read(productsProvider.future);
      expect(container.read(productsProvider).value!.map((p) => p.name), [
        'Chips',
      ]);

      container.read(inventoryFilterProvider.notifier).setCategory(null);
      await container.read(productsProvider.future);
      expect(container.read(productsProvider).value, hasLength(2));
    });

    test('clear resets every filter', () async {
      fake.storedProducts.add(product('p1', 'Milk', isActive: false));
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      container.read(inventoryFilterProvider.notifier)
        ..setQuery('x')
        ..setStatus(ProductStatusFilter.inactive)
        ..setCategory('c1')
        ..clear();

      await container.read(productsProvider.future);
      expect(container.read(productsProvider).value, hasLength(1));
    });

    test('create refreshes the product list', () async {
      fake.storedCategories.add(category('c1', 'Beverages'));
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      await container
          .read(productsProvider.notifier)
          .create(
            categoryId: 'c1',
            name: 'Milk',
            sellingPricePaise: 5000,
            stockQuantity: 3,
            isActive: true,
          );
      await awaitUntil(
        container,
        () => container.read(productsProvider).value?.isNotEmpty ?? false,
      );

      final products = container.read(productsProvider).value!;
      expect(products, hasLength(1));
      expect(products.single.name, 'Milk');
      expect(products.single.sellingPricePaise, 5000);
    });

    test('create failures surface safe messages', () async {
      fake.storedCategories.add(category('c1', 'Beverages'));
      fake.storedProducts.add(product('p1', 'Milk', sku: 'MILK'));
      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(productsProvider.future);

      await expectLater(
        container
            .read(productsProvider.notifier)
            .create(
              categoryId: 'c1',
              name: 'Milk 2',
              sku: 'milk',
              sellingPricePaise: 100,
              stockQuantity: 1,
              isActive: true,
            ),
        throwsA(isA<DuplicateSkuFailure>()),
      );
    });

    test('skuExists probes the repository, skipping exceptId', () async {
      fake.storedProducts.add(product('p1', 'Milk', sku: 'MILK'));
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(
        await container.read(productsProvider.notifier).skuExists('milk'),
        isTrue,
      );
      expect(
        await container
            .read(productsProvider.notifier)
            .skuExists('milk', exceptId: 'p1'),
        isFalse,
      );
    });
  });

  group('inventoryErrorMessage', () {
    test('returns safe messages for known failures', () {
      expect(
        inventoryErrorMessage(const DuplicateCategoryNameFailure()),
        'A category with this name already exists.',
      );
      expect(
        inventoryErrorMessage(const CategoryInUseFailure()),
        'This category is used by products and cannot be deleted.',
      );
      expect(
        inventoryErrorMessage(const DuplicateSkuFailure()),
        'A product with this SKU already exists.',
      );
      expect(
        inventoryErrorMessage(const NegativeStockFailure()),
        'Stock quantity cannot be negative.',
      );
      expect(
        inventoryErrorMessage(const NegativePriceFailure()),
        'Prices cannot be negative.',
      );
    });

    test('falls back to a generic message for anything else', () {
      expect(
        inventoryErrorMessage(StateError('boom')),
        'Something went wrong. Please try again.',
      );
      expect(
        inventoryErrorMessage(StateError('boom'), fallback: 'Try again.'),
        'Try again.',
      );
    });
  });
}
