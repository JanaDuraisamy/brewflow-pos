import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/data/preferences_settings_repository.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_customers_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';
import '../helpers/fake_preferences_storage.dart';
import '../helpers/fake_settings_repository.dart';
import '../helpers/fake_stock_movement_repository.dart';

void main() {
  group('automatic membership pricing (POS cart)', () {
    late FakeCustomersRepository customers;
    late FakeBillingRepository billing;
    late FakeSettingsRepository settings;
    late ProviderContainer container;

    setUp(() {
      customers = FakeCustomersRepository();
      final inventory = FakeInventoryRepository();
      billing = FakeBillingRepository(inventory);
      settings = FakeSettingsRepository();
      container = ProviderContainer(
        overrides: [
          customersRepositoryProvider.overrideWithValue(customers),
          inventoryRepositoryProvider.overrideWithValue(billing.inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          settingsRepositoryProvider.overrideWithValue(settings),
          stockMovementRepositoryProvider.overrideWithValue(
            FakeStockMovementRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
        ],
      );
      addTearDown(container.dispose);
    });

    Product memberProduct({
      String id = 'p1',
      int pricePaise = 12000,
      int? memberPricePaise = 9000,
    }) => Product(
      id: id,
      categoryId: 'c1',
      name: 'Filter Coffee',
      sku: null,
      sellingPricePaise: pricePaise,
      costPricePaise: null,
      stockQuantity: 10,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      memberPricePaise: memberPricePaise,
    );

    CartController controller() => container.read(cartProvider.notifier);
    Cart cart() => container.read(cartProvider);

    test('an active member customer is charged member prices', () async {
      await customers.createCustomer(name: 'Anand', membershipActive: true);
      final created = customers.storedCustomers.single;
      controller()
        ..add(memberProduct())
        ..add(memberProduct());
      expect(cart().chargedTotalPaise, 24000);

      await controller().selectCustomer(created.id);

      expect(cart().memberPricing, isTrue);
      expect(cart().chargedTotalPaise, 18000);
    });

    test('a non-member customer pays normal prices', () async {
      await customers.createCustomer(name: 'Walkin Ravi');
      final created = customers.storedCustomers.single;
      controller().add(memberProduct());

      await controller().selectCustomer(created.id);

      expect(cart().memberPricing, isFalse);
      expect(cart().chargedTotalPaise, 12000);
    });

    test(
      'membership globally disabled forces normal prices even for members',
      () async {
        settings.stored = ShopSettings(
          shopName: 'BrewFlow POS',
          membershipEnabled: false,
        );
        // Rebuild so shopSettingsProvider picks up the stored value.
        container.invalidate(shopSettingsProvider);
        await container.read(shopSettingsProvider.future);
        await customers.createCustomer(name: 'Member', membershipActive: true);
        final created = customers.storedCustomers.single;
        controller().add(memberProduct());

        await controller().selectCustomer(created.id);

        expect(cart().memberPricing, isFalse);
        expect(cart().chargedTotalPaise, 12000);

        // The manual switch cannot override a global off.
        controller().toggleMemberPricing();
        expect(cart().memberPricing, isFalse);
      },
    );

    test(
      'changing or removing the customer recalculates existing lines',
      () async {
        await customers.createCustomer(
          name: 'Member A',
          membershipActive: true,
        );
        await customers.createCustomer(name: 'Plain B');
        final memberA = customers.storedCustomers[0];
        final plainB = customers.storedCustomers[1];
        controller().add(memberProduct());

        await controller().selectCustomer(memberA.id);
        expect(cart().chargedTotalPaise, 9000);

        await controller().selectCustomer(plainB.id);
        expect(cart().memberPricing, isFalse);
        expect(cart().chargedTotalPaise, 12000);

        await controller().selectCustomer(null);
        expect(cart().selectedCustomerId, isNull);
        expect(cart().chargedTotalPaise, 12000);
      },
    );

    test('a deactivated member no longer receives member prices', () async {
      await customers.createCustomer(
        name: 'Old Member',
        membershipActive: true,
        isActive: false,
      );
      final created = customers.storedCustomers.single;
      controller().add(memberProduct());

      await controller().selectCustomer(created.id);

      expect(cart().memberPricing, isFalse);
      expect(cart().chargedTotalPaise, 12000);
    });

    test(
      'checkout snapshot preserves the actually charged member price',
      () async {
        await customers.createCustomer(name: 'Anand', membershipActive: true);
        final created = customers.storedCustomers.single;
        final product = memberProduct();
        billing.inventory.storedProducts.add(product);
        controller().add(product);
        await controller().selectCustomer(created.id);
        final completed = await controller().checkout(PaymentMethod.cash);

        expect(completed.items.single.unitPricePaise, 9000);
        expect(completed.sale.totalPaise, 9000);
        expect(billing.storedSales.single.totalPaise, 9000);
      },
    );
  });

  group('global membership setting persistence', () {
    test('saved ON and OFF persist; missing value defaults to ON', () async {
      final storage = FakePreferencesStorage();
      final repository = PreferencesSettingsRepository(storage);

      final fresh = await repository.load();
      expect(fresh.membershipEnabled, isTrue);

      await repository.save(
        fresh.copyWith(membershipEnabled: false),
        // ignore: avoid_redundant_argument_values
      );
      expect((await repository.load()).membershipEnabled, isFalse);

      await repository.save(
        (await repository.load()).copyWith(membershipEnabled: true),
      );
      expect((await repository.load()).membershipEnabled, isTrue);
    });
  });

  group('customers With Due filter', () {
    test(
      'lists only customers with outstanding due, including deactivated',
      () async {
        final customers = FakeCustomersRepository();
        await customers.createCustomer(name: 'Due Active');
        await customers.createCustomer(name: 'Settled');
        await customers.createCustomer(name: 'Due Inactive', isActive: false);
        final ledger = FakeCustomerLedgerRepository()
          ..knownCustomers.addAll({'customer-1', 'customer-2', 'customer-3'})
          ..bills.add(
            FakeLedgerBill(
              id: 'sale-1',
              customerId: 'customer-1',
              receiptNumber: 'BF-000001',
              createdAt: DateTime.now().toUtc(),
              totalPaise: 5000,
            ),
          )
          ..bills.add(
            FakeLedgerBill(
              id: 'sale-2',
              customerId: 'customer-2',
              receiptNumber: 'BF-000002',
              createdAt: DateTime.now().toUtc(),
              totalPaise: 7000,
            ),
          )
          ..bills.add(
            FakeLedgerBill(
              id: 'sale-3',
              customerId: 'customer-3',
              receiptNumber: 'BF-000003',
              createdAt: DateTime.now().toUtc(),
              totalPaise: 3000,
            ),
          );
        // customer-2 fully settles their bill.
        await ledger.recordPayment(
          customerId: 'customer-2',
          saleId: 'sale-2',
          amountPaise: 7000,
          paymentMethod: PaymentMethod.cash,
        );

        final container = ProviderContainer(
          overrides: [
            customersRepositoryProvider.overrideWithValue(customers),
            inventoryRepositoryProvider.overrideWithValue(
              FakeInventoryRepository(),
            ),
            customerLedgerRepositoryProvider.overrideWithValue(ledger),
            stockMovementRepositoryProvider.overrideWithValue(
              FakeStockMovementRepository(),
            ),
            ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
            settingsRepositoryProvider.overrideWithValue(
              FakeSettingsRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);

        container.read(customersFilterProvider.notifier).setDueOnly(true);
        final names = [
          for (final customer in await container.read(customersProvider.future))
            customer.name,
        ];

        expect(names, containsAll(['Due Active', 'Due Inactive']));
        expect(names, isNot(contains('Settled')));
      },
    );
  });

  group('inventory Low Stock filter', () {
    late FakeInventoryRepository inventory;
    late ProviderContainer container;

    setUp(() {
      inventory = FakeInventoryRepository();
      container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          stockMovementRepositoryProvider.overrideWithValue(
            FakeStockMovementRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
        ],
      );
      addTearDown(container.dispose);
    });

    Product product({
      required String id,
      required int stock,
      LowStockMode mode = LowStockMode.useDefault,
      int? threshold,
      bool active = true,
      List<ProductVariant> variants = const [],
    }) => Product(
      id: id,
      categoryId: 'c1',
      name: 'Product $id',
      sku: null,
      sellingPricePaise: 1000,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: active,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      lowStockMode: mode,
      lowStockThreshold: threshold,
      variants: variants,
    );

    ProductVariant variant({
      required String id,
      required int stock,
      LowStockMode mode = LowStockMode.useDefault,
      int? threshold,
      bool active = true,
    }) => ProductVariant(
      id: id,
      productId: 'parent',
      name: id,
      sku: null,
      sellingPricePaise: 1000,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: active,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      lowStockMode: mode,
      lowStockThreshold: threshold,
    );

    Future<List<Product>> loadLowOnly() async {
      container.read(inventoryFilterProvider.notifier).setLowStockOnly(true);
      return container.read(productsProvider.future);
    }

    test('keeps low-stock products and excludes normal stock', () async {
      inventory.storedProducts
        ..add(product(id: 'low', stock: 2))
        ..add(product(id: 'ok', stock: 99));
      final names = [for (final p in await loadLowOnly()) p.name];
      expect(names, ['Product low']);
    });

    test(
      'respects USE_DEFAULT, CUSTOM and OFF policies on plain products',
      () async {
        inventory.storedProducts
          ..add(
            product(
              id: 'custom-low',
              stock: 8,
              mode: LowStockMode.custom,
              threshold: 10,
            ),
          )
          ..add(product(id: 'off-zero', stock: 1, mode: LowStockMode.off));
        final names = [for (final p in await loadLowOnly()) p.name];
        expect(names, ['Product custom-low']);
      },
    );

    test('variant policies decide variant products', () async {
      inventory.storedProducts.add(
        product(
          id: 'parent',
          stock: 0,
          variants: [
            variant(id: 'vLow', stock: 1),
            variant(id: 'vOk', stock: 50),
          ],
        ),
      );
      inventory.storedProducts.add(
        product(
          id: 'parentOff',
          stock: 0,
          variants: [variant(id: 'vOff', stock: 1, mode: LowStockMode.off)],
        ),
      );
      final names = [for (final p in await loadLowOnly()) p.name];
      expect(names, ['Product parent']);
    });
  });
}
