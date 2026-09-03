import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_settings_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports & Dashboard Variant Support (Todo 11)
///
/// Real-DB integration coverage for variant-aware reporting: variant sales
/// stay distinguishable as 'Product — Variant' rows, multiple variants never
/// merge, plain products keep their old shape, COGS/profit resolves variant
/// cost prices, and historical SaleItem snapshots survive product/variant
/// renames and price changes. Dashboard assertions cover the already
/// implemented entity-based low-stock rules and variant-sale day totals.
///
/// All repositories derive from [appDatabaseProvider]; overriding it with an
/// in-memory SQLite database wires the entire real stack behind the Riverpod
/// controllers.
/// ---------------------------------------------------------------------------

void main() {
  late db.AppDatabase database;
  late ProviderContainer container;

  setUp(() {
    database = db.AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> awaitUntil(
    bool Function() condition, {
    String reason = 'condition was not met within the timeout',
  }) async {
    for (var i = 0; i < 300; i++) {
      if (condition()) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail(reason);
  }

  Future<ReportsSnapshot> reports() async {
    await awaitUntil(
      () => container.read(reportsControllerProvider) is AsyncData,
    );
    return container.read(reportsControllerProvider).requireValue;
  }

  Future<DashboardSnapshot> dashboard() async {
    await awaitUntil(
      () => container.read(dashboardControllerProvider) is AsyncData,
    );
    return container.read(dashboardControllerProvider).requireValue;
  }

  Future<void> seedCategory() async {
    await database
        .into(database.categories)
        .insert(
          db.CategoriesCompanion.insert(id: const Value('c1'), name: 'Coffee'),
        );
  }

  /// Creates one product with the given variants through the real inventory
  /// controller (the same path the UI uses).
  Future<Product> seedProduct(
    String name, {
    int? costPricePaise,
    int stockQuantity = 0,
    List<ProductVariantInput> variants = const [],
  }) async {
    final products = container.read(productsProvider.notifier);
    await products.create(
      categoryId: 'c1',
      name: name,
      sellingPricePaise: 15000,
      costPricePaise: costPricePaise,
      stockQuantity: stockQuantity,
      isActive: true,
      variants: variants,
    );
    await container.read(categoriesProvider.future);
    final list = await container.read(productsProvider.future);
    return list.firstWhere((product) => product.name == name);
  }

  ProductVariantInput variantInput(
    String name, {
    int? costPaise,
    int stock = 10,
    LowStockMode mode = LowStockMode.useDefault,
    int? threshold,
  }) => ProductVariantInput(
    name: name,
    sellingPricePaise: 15000,
    costPricePaise: costPaise,
    stockQuantity: stock,
    lowStockMode: mode,
    lowStockThreshold: threshold,
    isActive: true,
  );

  /// Completes one sale and waits until reports actually absorbed it.
  Future<void> sell(
    Product product, {
    ProductVariant? variant,
    int quantity = 1,
  }) async {
    final before =
        container.read(reportsControllerProvider).value?.sales.orderCount ?? 0;
    final cart = container.read(cartProvider.notifier);
    for (var i = 0; i < quantity; i++) {
      cart.add(product, variant: variant);
    }
    await cart.checkout(PaymentMethod.cash);
    await awaitUntil(
      () =>
          container.read(reportsControllerProvider).value?.sales.orderCount ==
          before + 1,
      reason: 'reports did not refresh after the sale',
    );
  }

  group('reports variant sales', () {
    test('a variant sale appears as its own Product — Variant row', () async {
      await seedCategory();
      final product = await seedProduct(
        'Filter Coffee',
        variants: [
          variantInput('Small', costPaise: 8000),
          variantInput('Large', costPaise: 10000),
        ],
      );
      final small = product.variants.firstWhere((v) => v.name == 'Small');

      await sell(product, variant: small);

      final snapshot = await reports();
      expect(snapshot.topProducts.single.productName, 'Filter Coffee');
      expect(snapshot.topProducts.single.variantName, 'Small');
      expect(snapshot.topProducts.single.unitsSold, 1);
      expect(snapshot.topProducts.single.revenuePaise, 15000);
      expect(snapshot.sales.totalPaise, 15000);
      expect(snapshot.sales.itemCount, 1);
      expect(snapshot.profitLoss.cogsPaise, 8000);
      expect(snapshot.profitLoss.netProfitPaise, 7000);
    });

    test(
      'two variants of one product are reported separately, never merged',
      () async {
        await seedCategory();
        final product = await seedProduct(
          'Filter Coffee',
          variants: [
            variantInput('Small', costPaise: 8000),
            variantInput('Large', costPaise: 10000),
          ],
        );
        final small = product.variants.firstWhere((v) => v.name == 'Small');
        final large = product.variants.firstWhere((v) => v.name == 'Large');

        await sell(product, variant: small, quantity: 2);
        await sell(product, variant: large);

        final snapshot = await reports();
        expect(snapshot.topProducts.length, 2);
        expect(snapshot.topProducts[0].productName, 'Filter Coffee');
        expect(snapshot.topProducts[0].variantName, 'Small');
        expect(snapshot.topProducts[0].unitsSold, 2);
        expect(snapshot.topProducts[0].revenuePaise, 30000);
        expect(snapshot.topProducts[1].variantName, 'Large');
        expect(snapshot.topProducts[1].revenuePaise, 15000);
        expect(snapshot.sales.totalPaise, 45000);
        expect(snapshot.sales.itemCount, 3);
        expect(snapshot.profitLoss.cogsPaise, 26000);
      },
    );

    test(
      'plain products stay plain while variant rows stay distinct',
      () async {
        await seedCategory();
        final variantProduct = await seedProduct(
          'Filter Coffee',
          variants: [variantInput('Small', costPaise: 8000)],
        );
        final small = variantProduct.variants.firstWhere(
          (v) => v.name == 'Small',
        );
        await seedProduct('Chai', costPricePaise: 5000, stockQuantity: 10);

        final products = await container.read(productsProvider.future);
        final chai = products.firstWhere((p) => p.name == 'Chai');
        await sell(variantProduct, variant: small);
        await sell(chai);

        final snapshot = await reports();
        expect(snapshot.topProducts.length, 2);
        final variantRow = snapshot.topProducts.firstWhere(
          (row) => row.variantName == 'Small',
        );
        final plainRow = snapshot.topProducts.firstWhere(
          (row) => row.variantName == null,
        );
        expect(variantRow.productName, 'Filter Coffee');
        expect(plainRow.productName, 'Chai');
        expect(plainRow.unitsSold, 1);
        expect(snapshot.sales.itemCount, 2);
        // Plain COGS still resolves the product cost.
        expect(snapshot.profitLoss.cogsPaise, 13000);
      },
    );

    test('variant COGS uses the variant cost, not the product cost', () async {
      await seedCategory();
      final product = await seedProduct(
        'Filter Coffee',
        costPricePaise: 5000,
        variants: [variantInput('Small', costPaise: 8000)],
      );
      final small = product.variants.firstWhere((v) => v.name == 'Small');

      await sell(product, variant: small, quantity: 2);

      final snapshot = await reports();
      expect(snapshot.profitLoss.cogsPaise, 16000);
      expect(snapshot.profitLoss.netProfitPaise, 30000 - 16000);
    });

    test('historical snapshots survive product and variant renames and '
        'price changes', () async {
      await seedCategory();
      final product = await seedProduct(
        'Filter Coffee',
        variants: [variantInput('Small', costPaise: 8000)],
      );
      final small = product.variants.firstWhere((v) => v.name == 'Small');
      await sell(product, variant: small);

      // Rename product + variant, change selling and cost prices.
      final products = container.read(productsProvider.notifier);
      await products.updateProduct(
        id: product.id,
        categoryId: product.categoryId,
        name: 'Brew Coffee',
        sku: product.sku,
        sellingPricePaise: 30000,
        costPricePaise: 20000,
        stockQuantity: product.stockQuantity,
        isActive: product.isActive,
        variants: [
          ProductVariantInput(
            id: small.id,
            name: 'Mini',
            sellingPricePaise: 30000,
            costPricePaise: 20000,
            stockQuantity: 10,
            isActive: true,
          ),
        ],
      );
      await awaitUntil(
        () =>
            container
                .read(productsProvider)
                .value
                ?.any(
                  (p) =>
                      p.name == 'Brew Coffee' &&
                      p.variants.any((v) => v.name == 'Mini'),
                ) ??
            false,
        reason: 'product rename did not apply',
      );

      // Wait until reports re-resolves costs against the edited product
      // (the first read after invalidation can return the cached snapshot).
      await awaitUntil(
        () =>
            container
                .read(reportsControllerProvider)
                .value
                ?.profitLoss
                .cogsPaise ==
            20000,
        reason: 'reports did not absorb the price changes',
      );

      final snapshot = await reports();
      // Top products still use the sale-time snapshot identity and price.
      expect(snapshot.topProducts.single.productName, 'Filter Coffee');
      expect(snapshot.topProducts.single.variantName, 'Small');
      expect(snapshot.topProducts.single.revenuePaise, 15000);
      // Profit follows the house convention: current cost prices.
      expect(snapshot.profitLoss.cogsPaise, 20000);
      expect(snapshot.profitLoss.netProfitPaise, 15000 - 20000);
    });
  });

  group('dashboard variants', () {
    test(
      'low-stock counts respect variant policies (custom, fallback, off)',
      () async {
        await seedCategory();
        await seedProduct(
          'Filter Coffee',
          variants: [
            // Custom threshold: 4 <= 8 → low.
            variantInput(
              'Small',
              stock: 4,
              mode: LowStockMode.custom,
              threshold: 8,
            ),
            // OFF: excluded even with zero stock.
            variantInput('Large', stock: 0, mode: LowStockMode.off),
          ],
        );
        await seedProduct(
          'Chai',
          variants: [
            // USE_DEFAULT: falls back to the global threshold of 5 → low.
            variantInput('Regular', stock: 3),
          ],
        );
        // Plain product with zero stock → out of stock.
        await seedProduct('Plain Low');

        final snapshot = await dashboard();
        expect(snapshot.lowStockThreshold, 5);
        expect(snapshot.lowStockCount, 2);
        expect(snapshot.outOfStockCount, 1);
      },
    );

    test('day sales and profit use variant prices and costs', () async {
      await seedCategory();
      final product = await seedProduct(
        'Filter Coffee',
        variants: [variantInput('Small', costPaise: 8000)],
      );
      final small = product.variants.firstWhere((v) => v.name == 'Small');

      final cart = container.read(cartProvider.notifier);
      cart.add(product, variant: small);
      cart.add(product, variant: small);
      await cart.checkout(PaymentMethod.cash);
      await awaitUntil(
        () =>
            container.read(dashboardControllerProvider).value?.daySalesPaise ==
            30000,
        reason: 'dashboard did not refresh after the variant sale',
      );

      final snapshot = await dashboard();
      expect(snapshot.daySalesPaise, 30000);
      expect(snapshot.dayOrderCount, 1);
      expect(snapshot.dayItemCount, 2);
      expect(snapshot.dayProfitPaise, 30000 - 2 * 8000);
    });
  });
}
