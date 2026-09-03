import 'package:brewflow_pos/core/database/app_database.dart'
    hide Product, ProductVariant;
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/data/drift_customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';

void main() {
  group('HeldBillsController (in-memory state)', () {
    late FakeInventoryRepository inventory;
    late FakeBillingRepository billing;
    late ProviderContainer container;

    Product product({
      String id = 'p1',
      String name = 'Filter Coffee',
      int pricePaise = 12000,
      int stock = 5,
      int? memberPricePaise,
      List<ProductVariant> variants = const [],
    }) => Product(
      id: id,
      categoryId: 'c1',
      name: name,
      sku: null,
      sellingPricePaise: pricePaise,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      memberPricePaise: memberPricePaise,
      variants: variants,
    );

    ProductVariant variant({
      required String id,
      String name = 'Large',
      int pricePaise = 15000,
      int stock = 4,
    }) => ProductVariant(
      id: id,
      productId: 'p1',
      name: name,
      sku: 'V-$id',
      sellingPricePaise: pricePaise,
      memberPricePaise: null,
      stockQuantity: stock,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    setUp(() {
      inventory = FakeInventoryRepository();
      billing = FakeBillingRepository(inventory);
      container = ProviderContainer(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
          stockMovementRepositoryProvider.overrideWithValue(
            FakeStockMovementRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        ],
      );
      addTearDown(container.dispose);
    });

    Cart cart() => container.read(cartProvider);
    CartController cartController() => container.read(cartProvider.notifier);
    HeldBillsController holds() => container.read(heldBillsProvider.notifier);
    List<HeldBill> heldBills() => container.read(heldBillsProvider);

    test('holdCurrentBill parks the cart and empties it', () async {
      cartController()
        ..add(product())
        ..add(product());
      await cartController().selectCustomer('c1');
      cartController().toggleMemberPricing();

      final bill = holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.upi,
      );

      expect(bill, isNotNull);
      expect(cart().isEmpty, isTrue);
      expect(cart().selectedCustomerId, isNull);
      expect(cart().memberPricing, isFalse);
      expect(heldBills().length, 1);
      final held = heldBills().single;
      expect(held.id, 'hold-1');
      expect(held.lines.length, 1);
      expect(held.lines.single.quantity, 2);
      expect(held.lines.single.maxQuantity, 5);
      expect(held.lines.single.productId, 'p1');
      expect(held.selectedCustomerId, 'c1');
      expect(held.memberPricing, isTrue);
      expect(held.paymentStatus, PaymentStatus.paid);
      expect(held.paymentMethod, PaymentMethod.upi);
      expect(
        held.heldAt.isBefore(
          DateTime.now().toUtc().add(const Duration(seconds: 1)),
        ),
        isTrue,
      );
    });

    test('holding an empty cart is a no-op', () {
      expect(
        holds().holdCurrentBill(
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        ),
        isNull,
      );
      expect(heldBills(), isEmpty);
    });

    test('holding never touches the repository — no sale is created', () {
      cartController().add(product());
      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );

      expect(billing.checkouts, 0);
      expect(billing.storedSales, isEmpty);
      expect(billing.receiptsIssued, 0);
    });

    test('a NOT_PAID hold always snapshots a null payment method', () {
      cartController().add(product());
      final bill = holds().holdCurrentBill(
        paymentStatus: PaymentStatus.notPaid,
        paymentMethod: PaymentMethod.cash,
      );

      expect(bill!.paymentStatus, PaymentStatus.notPaid);
      expect(bill.paymentMethod, isNull);
    });

    test('resume restores the exact cart and removes the bill', () async {
      cartController()
        ..add(product())
        ..add(product());
      await cartController().selectCustomer('c1');
      cartController().toggleMemberPricing();
      final held = holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.bank,
      )!;

      final resumed = holds().resumeHeldBill(held.id);

      expect(resumed!.id, held.id);
      expect(heldBills(), isEmpty);
      expect(cart().lines.length, 1);
      expect(cart().lines.single.quantity, 2);
      expect(cart().selectedCustomerId, 'c1');
      expect(cart().memberPricing, isTrue);
      expect(resumed.paymentStatus, PaymentStatus.paid);
      expect(resumed.paymentMethod, PaymentMethod.bank);
    });

    test(
      'resume of an unknown id leaves the cart and collection untouched',
      () {
        cartController().add(product());
        holds().holdCurrentBill(
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(holds().resumeHeldBill('hold-999'), isNull);
        expect(heldBills().length, 1);
        expect(cart().isEmpty, isTrue);
      },
    );

    test('delete removes only the selected bill', () {
      cartController().add(product(id: 'p1', name: 'Coffee'));
      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );
      cartController().add(product(id: 'p2', name: 'Tea'));
      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );
      cartController().add(product(id: 'p3', name: 'Cake'));
      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );

      holds().deleteHeldBill('hold-2');

      expect(heldBills().map((b) => b.id), ['hold-1', 'hold-3']);
      expect(heldBills()[0].lines.single.productId, 'p1');
      expect(heldBills()[1].lines.single.productId, 'p3');
      expect(cart().isEmpty, isTrue);
    });

    test('delete of an unknown id is a no-op', () {
      cartController().add(product());
      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );

      holds().deleteHeldBill('hold-999');

      expect(heldBills().length, 1);
    });

    test(
      'multiple held bills stay isolated across hold, delete and resume',
      () {
        cartController().add(product(id: 'p1', name: 'Coffee'));
        holds().holdCurrentBill(
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );
        cartController().add(product(id: 'p2', name: 'Tea'));
        holds().holdCurrentBill(
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.upi,
        );
        cartController().add(product(id: 'p3', name: 'Cake'));
        holds().holdCurrentBill(paymentStatus: PaymentStatus.notPaid);

        final resumed = holds().resumeHeldBill('hold-2')!;
        expect(resumed.lines.single.productId, 'p2');
        expect(heldBills().map((b) => b.id), ['hold-1', 'hold-3']);

        cartController().clear();
        final resumedAgain = holds().resumeHeldBill('hold-1')!;
        expect(resumedAgain.lines.single.productId, 'p1');
        expect(heldBills().map((b) => b.id), ['hold-3']);

        holds().deleteHeldBill('hold-3');
        expect(heldBills(), isEmpty);
        expect(cart().lines.single.productId, 'p1');
      },
    );

    test('variant lines survive hold and resume without merging', () {
      final withVariants = product(
        variants: [
          variant(id: 'v1', name: 'Small', pricePaise: 10000),
          variant(id: 'v2', name: 'Large'),
        ],
      );
      cartController()
        ..add(withVariants, variant: withVariants.variants[0])
        ..add(withVariants, variant: withVariants.variants[1])
        ..add(withVariants, variant: withVariants.variants[1]);

      holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      );

      final bill = heldBills().single;
      expect(bill.lines.length, 2);
      expect(bill.lines[0].variantId, 'v1');
      expect(bill.lines[1].variantId, 'v2');
      expect(bill.itemCount, 3);

      holds().resumeHeldBill(bill.id);
      expect(cart().lines.length, 2);
      expect(cart().lineFor('v1')!.quantity, 1);
      expect(cart().lineFor('v2')!.quantity, 2);
      expect(cart().lineFor('v1')!.variantName, 'Small');
      expect(cart().lineFor('v1')!.unitPricePaise, 10000);
      expect(cart().lineFor('v2')!.variantName, 'Large');
      expect(cart().lineFor('v2')!.unitPricePaise, 15000);
    });

    test('member pricing survives hold and resume, including the total', () {
      cartController()
        ..add(product(memberPricePaise: 9000))
        ..toggleMemberPricing();
      final bill = holds().holdCurrentBill(
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
      )!;

      expect(bill.totalPaise, 9000);

      holds().resumeHeldBill(bill.id);
      expect(cart().memberPricing, isTrue);
      expect(cart().lines.single.chargedUnitPricePaise(true), 9000);
      expect(cart().chargedTotalPaise, 9000);
    });

    test(
      'resuming and completing a sale clears the cart and the held list',
      () async {
        inventory.storedProducts.add(product());
        cartController().add(product());
        holds().holdCurrentBill(
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.upi,
        );
        holds().resumeHeldBill('hold-1');

        final completed = await cartController().checkout(PaymentMethod.upi);

        expect(completed.sale.receiptNumber, 'BF-000001');
        expect(cart().isEmpty, isTrue);
        expect(heldBills(), isEmpty);
        expect(billing.storedSales.length, 1);
      },
    );
  });

  group('logout clears counter state', () {
    test('signOut clears held bills and the current cart', () async {
      final inventory = FakeInventoryRepository();
      final container = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(
            FakeBillingRepository(inventory),
          ),
          stockMovementRepositoryProvider.overrideWithValue(
            FakeStockMovementRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        ],
      );
      addTearDown(container.dispose);

      final product = Product(
        id: 'p1',
        categoryId: 'c1',
        name: 'Filter Coffee',
        sku: null,
        sellingPricePaise: 12000,
        costPricePaise: null,
        stockQuantity: 5,
        isActive: true,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      );
      container.read(cartProvider.notifier).add(product);
      container
          .read(heldBillsProvider.notifier)
          .holdCurrentBill(
            paymentStatus: PaymentStatus.paid,
            paymentMethod: PaymentMethod.cash,
          );
      container.read(cartProvider.notifier).add(product);
      expect(container.read(heldBillsProvider).length, 1);
      expect(container.read(cartProvider).isNotEmpty, isTrue);

      await container.read(authControllerProvider.notifier).signOut();

      expect(container.read(heldBillsProvider), isEmpty);
      expect(container.read(cartProvider).isEmpty, isTrue);
    });
  });

  group('held bills and the database (integration)', () {
    late AppDatabase database;
    late DriftBillingRepository billing;
    late DriftCustomerLedgerRepository ledger;
    late ProviderContainer container;

    setUp(() {
      database = AppDatabase(NativeDatabase.memory());
      billing = DriftBillingRepository(database);
      ledger = DriftCustomerLedgerRepository(database);
      container = ProviderContainer(
        overrides: [
          billingRepositoryProvider.overrideWithValue(billing),
          inventoryRepositoryProvider.overrideWithValue(
            FakeInventoryRepository(),
          ),
          customersRepositoryProvider.overrideWithValue(
            DriftCustomersRepository(database),
          ),
          stockMovementRepositoryProvider.overrideWithValue(
            FakeStockMovementRepository(),
          ),
          ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
          customerLedgerRepositoryProvider.overrideWithValue(
            FakeCustomerLedgerRepository(),
          ),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        ],
      );
      addTearDown(container.dispose);
    });

    tearDown(() async {
      await database.close();
    });

    Future<void> seedProduct({
      required String id,
      required String name,
      int stock = 10,
      int pricePaise = 12000,
    }) async {
      await database
          .into(database.categories)
          .insert(
            CategoriesCompanion.insert(id: Value(id), name: 'Category $id'),
          );
      await database
          .into(database.products)
          .insert(
            ProductsCompanion.insert(
              id: Value(id),
              categoryId: id,
              name: name,
              sellingPricePaise: pricePaise,
              stockQuantity: Value(stock),
            ),
          );
    }

    Future<void> seedCustomer(String id) async {
      await database
          .into(database.customers)
          .insert(
            CustomersCompanion.insert(id: Value(id), name: 'Customer $id'),
          );
    }

    Future<int> countSales() async {
      final query = database.selectOnly(database.sales)
        ..addColumns([database.sales.id.count()]);
      return query
          .map((row) => row.read(database.sales.id.count())!)
          .getSingle();
    }

    Future<int> countMovements() async {
      final query = database.selectOnly(database.stockMovements)
        ..addColumns([database.stockMovements.id.count()]);
      return query
          .map((row) => row.read(database.stockMovements.id.count())!)
          .getSingle();
    }

    Future<int> stockOf(String id) async {
      final row = await (database.select(
        database.products,
      )..where((t) => t.id.equals(id))).getSingle();
      return row.stockQuantity;
    }

    Product shelfProduct({
      required String id,
      required String name,
      int stock = 10,
      int pricePaise = 12000,
    }) => Product(
      id: id,
      categoryId: id,
      name: name,
      sku: null,
      sellingPricePaise: pricePaise,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    CartController cartController() => container.read(cartProvider.notifier);

    test('holding writes nothing to the database: no sale, no movement, '
        'no stock deduction', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      cartController()
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5))
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5));

      container
          .read(heldBillsProvider.notifier)
          .holdCurrentBill(
            paymentStatus: PaymentStatus.paid,
            paymentMethod: PaymentMethod.cash,
          );

      expect(await countSales(), 0);
      expect(await countMovements(), 0);
      expect(await stockOf('p1'), 5);
    });

    test('a resumed held bill checks out with the next receipt number and '
        'deducts stock once', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      cartController()
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5))
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5));
      container
          .read(heldBillsProvider.notifier)
          .holdCurrentBill(
            paymentStatus: PaymentStatus.paid,
            paymentMethod: PaymentMethod.upi,
          );
      expect(await countSales(), 0);

      container.read(heldBillsProvider.notifier).resumeHeldBill('hold-1');
      final completed = await cartController().checkout(PaymentMethod.upi);

      expect(completed.sale.receiptNumber, 'BF-000001');
      expect(await countSales(), 1);
      expect(await countMovements(), 1);
      expect(await stockOf('p1'), 3);
      expect(container.read(cartProvider).isEmpty, isTrue);
      expect(container.read(heldBillsProvider), isEmpty);
    });

    test('a resumed bill with reduced stock fails safely at checkout and keeps '
        'the cart', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      cartController()
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5))
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5))
        ..add(shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5));
      container
          .read(heldBillsProvider.notifier)
          .holdCurrentBill(
            paymentStatus: PaymentStatus.paid,
            paymentMethod: PaymentMethod.cash,
          );
      await (database.update(database.products)
            ..where((t) => t.id.equals('p1')))
          .write(ProductsCompanion(stockQuantity: Value(2)));

      container.read(heldBillsProvider.notifier).resumeHeldBill('hold-1');
      await expectLater(
        cartController().checkout(PaymentMethod.cash),
        throwsA(isA<InsufficientStockFailure>()),
      );

      expect(container.read(cartProvider).lines.single.quantity, 3);
      expect(await countSales(), 0);
      expect(await countMovements(), 0);
      expect(await stockOf('p1'), 2);
    });

    test(
      'a NOT_PAID held bill becomes debt only at the final checkout',
      () async {
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
        await seedCustomer('c1');
        cartController().add(
          shelfProduct(id: 'p1', name: 'Filter Coffee', stock: 5),
        );
        await cartController().selectCustomer('c1');
        container
            .read(heldBillsProvider.notifier)
            .holdCurrentBill(paymentStatus: PaymentStatus.notPaid);

        expect(await countSales(), 0);
        expect(await ledger.outstandingForCustomer('c1'), 0);

        container.read(heldBillsProvider.notifier).resumeHeldBill('hold-1');
        final completed = await cartController().checkout(
          null,
          paymentStatus: PaymentStatus.notPaid,
        );

        expect(completed.sale.paymentStatus, PaymentStatus.notPaid);
        expect(completed.sale.paymentMethod, isNull);
        expect(completed.sale.customerId, 'c1');
        expect(await ledger.outstandingForCustomer('c1'), 12000);
        expect(container.read(cartProvider).isEmpty, isTrue);
        expect(container.read(heldBillsProvider), isEmpty);
      },
    );
  });
}
