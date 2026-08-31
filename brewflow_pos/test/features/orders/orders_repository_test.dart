import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/orders/data/drift_orders_repository.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/domain/orders_repository.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late DriftBillingRepository billing;
  late DriftOrdersRepository orders;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    billing = DriftBillingRepository(database);
    orders = DriftOrdersRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<void> seedProduct({
    required String id,
    required String name,
    int stock = 50,
    String? sku,
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
            sku: Value(sku),
            sellingPricePaise: pricePaise,
            stockQuantity: Value(stock),
          ),
        );
  }

  List<CartLine> lines(List<(String, int)> entries, {int pricePaise = 12000}) =>
      [
        for (final (id, quantity) in entries)
          CartLine(
            productId: id,
            productName: 'Name $id',
            sku: null,
            unitPricePaise: pricePaise,
            quantity: quantity,
            maxQuantity: 99,
          ),
      ];

  Future<CompletedSale> checkout({
    required List<CartLine> saleLines,
    required PaymentMethod method,
    PaymentStatus paymentStatus = PaymentStatus.paid,
    String? customerId,
  }) => billing.completeSale(
    lines: saleLines,
    paymentMethod: paymentStatus == PaymentStatus.notPaid ? null : method,
    paymentStatus: paymentStatus,
    customerId: customerId,
  );

  /// Moves a sale to a specific UTC instant (for deterministic range tests).
  Future<void> setSaleTime(String saleId, DateTime utc) async {
    await (database.update(database.sales)..where((t) => t.id.equals(saleId)))
        .write(SalesCompanion(createdAt: Value(utc)));
  }

  group('list', () {
    test('empty history returns an empty page', () async {
      final page = await orders.orders();
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('completed sales surface with receipt, time, item count, total and '
        'payment method', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5, sku: 'FC-1');
      final completed = await checkout(
        saleLines: [
          const CartLine(
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: 'FC-1',
            unitPricePaise: 12000,
            quantity: 2,
            maxQuantity: 5,
          ),
        ],
        method: PaymentMethod.upi,
      );

      final page = await orders.orders();
      expect(page.items.length, 1);
      final row = page.items.single;
      expect(row.receiptNumber, completed.sale.receiptNumber);
      expect(row.itemCount, 2);
      expect(row.totalPaise, 24000);
      expect(row.paymentMethod, PaymentMethod.upi);
      expect(row.createdAt.isUtc, isTrue);
      expect(page.hasMore, isFalse);
    });

    test('NOT_PAID credit sales list without a payment method', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5);
      await database
          .into(database.customers)
          .insert(CustomersCompanion.insert(id: Value('c1'), name: 'Anand'));
      final completed = await checkout(
        saleLines: lines([('p1', 2)]),
        method: PaymentMethod.cash,
        paymentStatus: PaymentStatus.notPaid,
        customerId: 'c1',
      );

      final page = await orders.orders();
      final row = page.items.single;
      expect(row.paymentStatus, PaymentStatus.notPaid);
      expect(row.paymentMethod, isNull);
      expect(row.customerName, 'Anand');
      expect(row.totalPaise, 24000);

      final detail = await orders.orderById(completed.sale.id);
      expect(detail.paymentStatus, PaymentStatus.notPaid);
      expect(detail.paymentMethod, isNull);
      expect(detail.customerName, 'Anand');
    });

    test('multiple sales are listed newest first', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      final first = await checkout(
        saleLines: lines([('p1', 1)]),
        method: PaymentMethod.cash,
      );
      final second = await checkout(
        saleLines: lines([('p1', 2)]),
        method: PaymentMethod.upi,
      );
      final third = await checkout(
        saleLines: lines([('p1', 3)]),
        method: PaymentMethod.bank,
      );

      final page = await orders.orders();
      expect(page.items.map((o) => o.id), [
        third.sale.id,
        second.sale.id,
        first.sale.id,
      ]);
      expect(page.items.map((o) => o.receiptNumber), [
        'BF-000003',
        'BF-000002',
        'BF-000001',
      ]);
      expect(page.items.map((o) => o.itemCount), [3, 2, 1]);
    });

    test('pages through large histories without loading everything', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);

      Future<void> charge(String receipt, DateTime at) async {
        final done = await checkout(
          saleLines: lines([('p1', 1)]),
          method: PaymentMethod.cash,
        );
        await setSaleTime(done.sale.id, at);
      }

      final base = DateTime.utc(2026, 1, 1);
      for (var i = 0; i < 5; i++) {
        await charge('sale-$i', base.add(Duration(hours: i + 1)));
      }

      final page1 = await orders.orders(limit: 2, offset: 0);
      expect(page1.items.map((o) => o.receiptNumber), [
        'BF-000005',
        'BF-000004',
      ]);
      expect(page1.hasMore, isTrue);

      final page2 = await orders.orders(limit: 2, offset: 2);
      expect(page2.items.map((o) => o.receiptNumber), [
        'BF-000003',
        'BF-000002',
      ]);
      expect(page2.hasMore, isTrue);

      final page3 = await orders.orders(limit: 2, offset: 4);
      expect(page3.items.map((o) => o.receiptNumber), ['BF-000001']);
      expect(page3.hasMore, isFalse);

      final ids = {
        ...page1.items.map((o) => o.id),
        ...page2.items.map((o) => o.id),
        ...page3.items.map((o) => o.id),
      };
      expect(ids.length, 5, reason: 'no overlap, no gaps between pages');
    });
  });

  group('search', () {
    Future<void> seedTwoSales() async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 50);
      await checkout(
        saleLines: [
          const CartLine(
            productId: 'p1',
            productName: 'Filter Coffee',
            unitPricePaise: 12000,
            quantity: 1,
            maxQuantity: 50,
          ),
        ],
        method: PaymentMethod.cash,
      );
      await checkout(
        saleLines: [
          const CartLine(
            productId: 'p2',
            productName: 'Green Tea',
            unitPricePaise: 8000,
            quantity: 1,
            maxQuantity: 50,
          ),
        ],
        method: PaymentMethod.upi,
      );
    }

    test('matches receipt numbers (partial, case-insensitive)', () async {
      await seedTwoSales();
      expect(
        (await orders.orders(
          filter: const OrdersFilter(query: 'BF-000001'),
        )).items.length,
        1,
      );
      expect(
        (await orders.orders(
          filter: const OrdersFilter(query: 'bf-00000'),
        )).items.length,
        2,
      );
      expect(
        (await orders.orders(
          filter: const OrdersFilter(query: 'BF-999999'),
        )).items,
        isEmpty,
      );
    });

    test('matches persisted product-name snapshots (partial)', () async {
      await seedTwoSales();
      final tea = await orders.orders(
        filter: const OrdersFilter(query: 'green tea'),
      );
      expect(tea.items.length, 1);
      expect(tea.items.single.paymentMethod, PaymentMethod.upi);

      final coffee = await orders.orders(
        filter: const OrdersFilter(query: 'coffee'),
      );
      expect(coffee.items.length, 1);
      expect(coffee.items.single.paymentMethod, PaymentMethod.cash);
    });

    test('searches without loading unrelated rows into memory', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      await checkout(saleLines: lines([('p1', 1)]), method: PaymentMethod.cash);
      final page = await orders.orders(
        filter: const OrdersFilter(query: 'no-such-product'),
        limit: 10,
        offset: 0,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('LIKE wildcards in the query are matched literally', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      await checkout(saleLines: lines([('p1', 1)]), method: PaymentMethod.cash);
      final page = await orders.orders(filter: const OrdersFilter(query: '%'));
      expect(page.items, isEmpty, reason: '% must not act as a wildcard');
    });
  });

  group('filters', () {
    test('payment method narrows the list', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      await checkout(saleLines: lines([('p1', 1)]), method: PaymentMethod.cash);
      await checkout(saleLines: lines([('p1', 1)]), method: PaymentMethod.upi);

      final cash = await orders.orders(
        filter: const OrdersFilter(paymentMethod: PaymentMethod.cash),
      );
      expect(cash.items.length, 1);
      expect(cash.items.single.paymentMethod, PaymentMethod.cash);

      final none = await orders.orders(
        filter: const OrdersFilter(paymentMethod: PaymentMethod.bank),
      );
      expect(none.items, isEmpty);
    });

    test('date range narrows the list with inclusive UTC bounds', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      final first = await checkout(
        saleLines: lines([('p1', 1)]),
        method: PaymentMethod.cash,
      );
      final second = await checkout(
        saleLines: lines([('p1', 1)]),
        method: PaymentMethod.cash,
      );
      await setSaleTime(first.sale.id, DateTime.utc(2026, 1, 10, 6));
      await setSaleTime(second.sale.id, DateTime.utc(2026, 2, 20, 18));

      final feb = await orders.orders(
        filter: OrdersFilter(
          fromUtc: DateTime.utc(2026, 2, 1),
          toUtc: DateTime.utc(2026, 2, 28, 23, 59, 59, 999),
        ),
      );
      expect(feb.items.map((o) => o.id), [second.sale.id]);

      final janOnly = await orders.orders(
        filter: OrdersFilter(
          fromUtc: DateTime.utc(2026, 1, 1),
          toUtc: DateTime.utc(2026, 1, 31, 23, 59, 59, 999),
        ),
      );
      expect(janOnly.items.map((o) => o.id), [first.sale.id]);

      final boundary = await orders.orders(
        filter: OrdersFilter(
          fromUtc: DateTime.utc(2026, 2, 20),
          toUtc: DateTime.utc(2026, 2, 20, 23, 59, 59, 999, 999),
        ),
      );
      expect(boundary.items.length, 1, reason: 'range end is inclusive');
    });

    test('search and filters combine', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 50);
      await checkout(
        saleLines: [
          const CartLine(
            productId: 'p1',
            productName: 'Filter Coffee',
            unitPricePaise: 12000,
            quantity: 1,
            maxQuantity: 50,
          ),
        ],
        method: PaymentMethod.cash,
      );
      await checkout(
        saleLines: [
          const CartLine(
            productId: 'p2',
            productName: 'Green Tea',
            unitPricePaise: 8000,
            quantity: 1,
            maxQuantity: 50,
          ),
        ],
        method: PaymentMethod.upi,
      );

      final page = await orders.orders(
        filter: const OrdersFilter(
          query: 'green tea',
          paymentMethod: PaymentMethod.cash,
        ),
      );
      expect(page.items, isEmpty);

      final matching = await orders.orders(
        filter: const OrdersFilter(
          query: 'green tea',
          paymentMethod: PaymentMethod.upi,
        ),
      );
      expect(matching.items.length, 1);
    });
  });

  group('details', () {
    test('orderById returns the header with snapshot items', () async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 5, sku: 'FC-1');
      await seedProduct(id: 'p2', name: 'Green Tea', stock: 3, sku: 'GT-1');
      final completed = await checkout(
        saleLines: [
          const CartLine(
            productId: 'p1',
            productName: 'Filter Coffee',
            sku: 'FC-1',
            unitPricePaise: 12000,
            quantity: 2,
            maxQuantity: 5,
          ),
          const CartLine(
            productId: 'p2',
            productName: 'Green Tea',
            sku: 'GT-1',
            unitPricePaise: 8000,
            quantity: 1,
            maxQuantity: 3,
          ),
        ],
        method: PaymentMethod.bank,
      );

      final order = await orders.orderById(completed.sale.id);
      expect(order.receiptNumber, completed.sale.receiptNumber);
      expect(order.subtotalPaise, 32000);
      expect(order.totalPaise, 32000);
      expect(order.paymentMethod, PaymentMethod.bank);
      expect(order.items.length, 2);
      expect(order.items[0].productName, 'Filter Coffee');
      expect(order.items[0].sku, 'FC-1');
      expect(order.items[0].unitPricePaise, 12000);
      expect(order.items[0].quantity, 2);
      expect(order.items[0].lineTotalPaise, 24000);
    });

    test(
      'historical snapshots survive later product renames and repricing',
      () async {
        await seedProduct(
          id: 'p1',
          name: 'Filter Coffee',
          stock: 5,
          sku: 'FC-1',
          pricePaise: 12000,
        );
        final completed = await checkout(
          saleLines: [
            const CartLine(
              productId: 'p1',
              productName: 'Filter Coffee',
              sku: 'FC-1',
              unitPricePaise: 12000,
              quantity: 2,
              maxQuantity: 5,
            ),
          ],
          method: PaymentMethod.upi,
        );

        await (database.update(
          database.products,
        )..where((t) => t.id.equals('p1'))).write(
          ProductsCompanion(
            name: Value('Cold Brew Special'),
            sellingPricePaise: const Value(99999),
          ),
        );

        final order = await orders.orderById(completed.sale.id);
        expect(order.items.single.productName, 'Filter Coffee');
        expect(order.items.single.sku, 'FC-1');
        expect(order.items.single.unitPricePaise, 12000);
        expect(order.items.single.lineTotalPaise, 24000);
        expect(order.totalPaise, 24000);
        expect(
          (await orders.orders()).items.single.itemCount,
          2,
          reason: 'list counts also come from persisted snapshots',
        );
      },
    );

    test('orderById throws MissingOrderFailure for unknown ids', () async {
      await expectLater(
        orders.orderById('missing'),
        throwsA(isA<MissingOrderFailure>()),
      );
    });
  });

  group('customer names', () {
    Future<void> seedCustomer({
      required String id,
      required String name,
    }) async {
      await database
          .into(database.customers)
          .insert(CustomersCompanion.insert(id: Value(id), name: name));
    }

    Future<void> linkCustomer(String saleId, String customerId) async {
      await (database.update(database.sales)..where((t) => t.id.equals(saleId)))
          .write(SalesCompanion(customerId: Value(customerId)));
    }

    Future<String> checkoutWalkIn() async {
      await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
      final done = await checkout(
        saleLines: lines([('p1', 1)]),
        method: PaymentMethod.cash,
      );
      return done.sale.id;
    }

    test(
      'list carries the linked customer name; walk-in rows stay null',
      () async {
        await seedCustomer(id: 'c1', name: 'Priya');
        await seedProduct(id: 'p1', name: 'Filter Coffee', stock: 50);
        final namedSale = await checkout(
          saleLines: lines([('p1', 1)]),
          method: PaymentMethod.cash,
        );
        await linkCustomer(namedSale.sale.id, 'c1');
        final walkInSale = await checkout(
          saleLines: lines([('p1', 1)]),
          method: PaymentMethod.cash,
        );

        final page = await orders.orders();
        expect(page.items.length, 2);
        final byId = {for (final row in page.items) row.id: row};
        expect(byId[namedSale.sale.id]!.customerName, 'Priya');
        expect(byId[walkInSale.sale.id]!.customerName, isNull);
      },
    );

    test('orderById carries the linked customer name', () async {
      await seedCustomer(id: 'c1', name: 'Priya');
      final saleId = await checkoutWalkIn();
      await linkCustomer(saleId, 'c1');

      final order = await orders.orderById(saleId);
      expect(order.customerName, 'Priya');
    });

    test('deactivated customers still resolve their name on history', () async {
      await seedCustomer(id: 'c1', name: 'Priya');
      final saleId = await checkoutWalkIn();
      await linkCustomer(saleId, 'c1');
      await (database.update(database.customers)
            ..where((t) => t.id.equals('c1')))
          .write(CustomersCompanion(isActive: const Value(false)));

      final page = await orders.orders();
      expect(page.items.single.customerName, 'Priya');
      expect((await orders.orderById(saleId)).customerName, 'Priya');
    });
  });
}
