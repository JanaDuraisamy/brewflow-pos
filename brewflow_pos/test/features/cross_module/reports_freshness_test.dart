import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/reports/domain/reports_models.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_settings_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Reports Freshness After Mutations (Phase 10 Step 9)
///
/// The reports surface is a read aggregation over orders, expenses and
/// inventory. When any of those change (a sale is completed, an expense is
/// recorded, a product's cost price is updated), the reports snapshot must be
/// invalidated so a live Reports tab never shows stale numbers.
///
/// All repositories derive from [appDatabaseProvider]; overriding it with an
/// in-memory SQLite database wires the entire real stack behind the Riverpod
/// controllers. Each test performs a mutation and asserts the reports snapshot
/// actually refreshes (it would stay stale without invalidation).
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
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedCategory() async {
    await database
        .into(database.categories)
        .insert(db.CategoriesCompanion.insert(id: Value('c1'), name: 'Coffee'));
  }

  Future<void> seedProduct({int stock = 50, int? costPricePaise}) async {
    await seedCategory();
    await database
        .into(database.products)
        .insert(
          db.ProductsCompanion.insert(
            id: Value('p1'),
            categoryId: 'c1',
            name: 'Filter Coffee',
            sellingPricePaise: 15000,
            costPricePaise: Value(costPricePaise),
            stockQuantity: Value(stock),
            isActive: const Value(true),
          ),
        );
  }

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

  test('a completed sale refreshes the reports totals', () async {
    await seedProduct(costPricePaise: 8000);
    expect((await reports()).sales.totalPaise, 0);

    final product = (await container.read(productsProvider.future)).single;
    final cart = container.read(cartProvider.notifier);
    cart.add(product);
    await cart.checkout(PaymentMethod.cash);

    await awaitUntil(() {
      final value = container.read(reportsControllerProvider).value;
      return value != null && value.sales.totalPaise == 15000;
    }, reason: 'reports sales total did not refresh after the sale');
    expect((await reports()).sales.orderCount, 1);
    expect((await reports()).sales.itemCount, 1);
    expect((await reports()).profitLoss.netProfitPaise, 7000);
  });

  test('a recorded expense refreshes the expense totals', () async {
    await seedProduct();
    expect((await reports()).expenses.totalPaise, 0);

    await container
        .read(expensesProvider.notifier)
        .create(
          name: 'Rent',
          amountPaise: 250000,
          category: ExpenseCategory.rent,
          paymentMethod: PaymentMethod.bank,
          expenseDate: DateTime.now(),
        );

    await awaitUntil(
      () {
        final value = container.read(reportsControllerProvider).value;
        return value != null && value.expenses.totalPaise == 250000;
      },
      reason:
          'reports expense total did not refresh after recording an expense',
    );
    expect((await reports()).expenses.count, 1);
  });

  test('a product cost-price update refreshes reported profit', () async {
    await seedProduct(costPricePaise: 8000);
    final product = (await container.read(productsProvider.future)).single;
    final cart = container.read(cartProvider.notifier);
    cart.add(product);
    await cart.checkout(PaymentMethod.cash);
    expect((await reports()).profitLoss.netProfitPaise, 7000);

    await container
        .read(productsProvider.notifier)
        .updateProduct(
          id: product.id,
          categoryId: product.categoryId,
          name: product.name,
          sku: product.sku,
          sellingPricePaise: product.sellingPricePaise,
          costPricePaise: 10000,
          stockQuantity: product.stockQuantity,
          isActive: product.isActive,
        );

    await awaitUntil(() {
      final value = container.read(reportsControllerProvider).value;
      return value != null && value.profitLoss.netProfitPaise == 5000;
    }, reason: 'reported profit did not refresh after a cost-price update');
  });
}
