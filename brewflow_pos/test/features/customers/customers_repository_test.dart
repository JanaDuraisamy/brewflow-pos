import 'package:brewflow_pos/core/database/app_database.dart'
    show AppDatabase, CustomerPaymentsCompanion, SalesCompanion, ShopsCompanion;
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repository tests against a real in-memory Drift database: migrations,
/// UNIQUE constraints and SQL filtering all behave exactly like production.
void main() {
  late AppDatabase database;
  late DriftCustomersRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftCustomersRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  Future<Customer> createCustomer({
    String name = 'Customer',
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
  }) => repository.createCustomer(
    name: name,
    phone: phone,
    email: email,
    address: address,
    isActive: isActive,
  );

  group('createCustomer', () {
    test(
      'persists a customer with a generated id and UTC timestamps',
      () async {
        final customer = await createCustomer(
          name: 'Priya',
          phone: '9845012345',
          email: 'priya@example.com',
          address: 'Anna Nagar, Chennai',
        );

        expect(customer.id, isNotEmpty);
        expect(customer.name, 'Priya');
        expect(customer.phone, '9845012345');
        expect(customer.email, 'priya@example.com');
        expect(customer.address, 'Anna Nagar, Chennai');
        expect(customer.isActive, isTrue);
        expect(customer.createdAt.isUtc, isTrue);
        expect(customer.updatedAt.isUtc, isTrue);

        final all = await repository.customers();
        expect(all, hasLength(1));
        expect(all.single.name, 'Priya');
      },
    );

    test('trims name and treats blank optional fields as absent', () async {
      final customer = await createCustomer(
        name: '  Arjun  ',
        phone: '   ',
        email: '',
        address: null,
      );

      expect(customer.name, 'Arjun');
      expect(customer.phone, isNull);
      expect(customer.email, isNull);
      expect(customer.address, isNull);
    });

    test('blank name is rejected', () async {
      await expectLater(
        createCustomer(name: '   '),
        throwsA(isA<UnexpectedCustomersFailure>()),
      );
      expect(await repository.customers(), isEmpty);
    });

    test('defaults to an active customer', () async {
      final customer = await createCustomer();
      expect(customer.isActive, isTrue);
    });

    test('multiple customers without a phone are allowed', () async {
      await createCustomer(name: 'One');
      await createCustomer(name: 'Two');

      expect(await repository.customers(), hasLength(2));
    });
  });

  group('phone uniqueness', () {
    test('a phone is unique when present (case-insensitive)', () async {
      await createCustomer(name: 'Priya', phone: '9845012345');

      await expectLater(
        createCustomer(name: 'Karthik', phone: '9845012345'),
        throwsA(isA<DuplicatePhoneFailure>()),
      );
    });

    test('same phone with different case is rejected', () async {
      await createCustomer(name: 'Priya', phone: 'ABCDE12345');

      await expectLater(
        createCustomer(name: 'Karthik', phone: 'abcde12345'),
        throwsA(isA<DuplicatePhoneFailure>()),
      );
      expect(await repository.customers(), hasLength(1));
    });

    test('phoneExists honours exceptId (edit keeps its own phone)', () async {
      final customer = await createCustomer(name: 'Priya', phone: '9845012345');

      final exists = await repository.phoneExists(
        '9845012345',
        exceptId: customer.id,
      );
      expect(exists, isFalse);

      final existsElsewhere = await repository.phoneExists(
        '9845012345',
        exceptId: 'some-other-id',
      );
      expect(existsElsewhere, isTrue);
    });
  });

  group('updateCustomer', () {
    test('updates details and the UTC updatedAt', () async {
      final customer = await createCustomer(name: 'Priya', phone: '9845012345');

      await repository.updateCustomer(
        id: customer.id,
        name: 'Priya R',
        phone: '9000012345',
        email: 'priya.r@example.com',
        address: null,
        isActive: true,
      );

      final updated = await repository.customerById(customer.id);
      expect(updated!.name, 'Priya R');
      expect(updated.phone, '9000012345');
      expect(updated.email, 'priya.r@example.com');
      expect(updated.address, isNull);
      expect(updated.createdAt, customer.createdAt);
      expect(
        updated.updatedAt.isAfter(customer.updatedAt),
        isTrue,
        reason: 'updatedAt must advance on every change',
      );
    });

    test('changing the phone to another customer phone is rejected', () async {
      final first = await createCustomer(name: 'Priya', phone: '9845012345');
      await createCustomer(name: 'Karthik', phone: '9000012345');

      await expectLater(
        repository.updateCustomer(
          id: first.id,
          name: 'Priya',
          phone: '9000012345',
          isActive: true,
        ),
        throwsA(isA<DuplicatePhoneFailure>()),
      );
    });

    test(
      'keeping its own phone during edit is allowed (self-exclusion)',
      () async {
        final customer = await createCustomer(
          name: 'Priya',
          phone: '9845012345',
        );

        await repository.updateCustomer(
          id: customer.id,
          name: 'Priya Updated',
          phone: '9845012345',
          isActive: true,
        );

        expect(
          (await repository.customerById(customer.id))!.name,
          'Priya Updated',
        );
      },
    );

    test('clearing the phone is allowed', () async {
      final customer = await createCustomer(name: 'Priya', phone: '9845012345');

      await repository.updateCustomer(
        id: customer.id,
        name: 'Priya',
        phone: '',
        isActive: true,
      );

      expect((await repository.customerById(customer.id))!.phone, isNull);
    });
  });

  group('customerById', () {
    test('returns the customer', () async {
      final customer = await createCustomer(name: 'Priya');

      expect((await repository.customerById(customer.id))!.name, 'Priya');
    });

    test('returns null for an unknown id', () async {
      expect(await repository.customerById('missing'), isNull);
    });
  });

  group('setCustomerActive', () {
    test('deactivates and reactivates a customer', () async {
      final customer = await createCustomer(name: 'Priya');
      expect(customer.isActive, isTrue);

      await repository.setCustomerActive(customer.id, false);
      expect((await repository.customerById(customer.id))!.isActive, isFalse);

      await repository.setCustomerActive(customer.id, true);
      expect((await repository.customerById(customer.id))!.isActive, isTrue);
    });

    test('deactivation does not delete the customer', () async {
      final customer = await createCustomer(name: 'Priya');
      await repository.setCustomerActive(customer.id, false);

      final all = await repository.customers();
      expect(all, hasLength(1));
      expect(all.single.isActive, isFalse);
    });
  });

  group('deleteCustomer', () {
    /// Seeds one customer-linked sale plus one allocated payment, i.e. exactly
    /// the history that used to force the old deactivate-instead-of-delete path.
    Future<void> seedLedger(String customerId) async {
      final now = DateTime.now().toUtc();
      await database
          .into(database.sales)
          .insert(
            SalesCompanion.insert(
              id: const Value('sale-1'),
              receiptNumber: 'BF-000001',
              customerId: Value(customerId),
              subtotalPaise: 50000,
              totalPaise: 50000,
              paymentStatus: const Value('NOT_PAID'),
              paymentMethod: const Value('CASH'),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
      await database
          .into(database.customerPayments)
          .insert(
            CustomerPaymentsCompanion.insert(
              id: const Value('pay-1'),
              customerId: customerId,
              amountPaise: 20000,
              paymentMethod: 'CASH',
              saleId: const Value('sale-1'),
              paidAt: now,
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
    }

    test('deletes a customer with no history outright', () async {
      final customer = await createCustomer(name: 'Priya');

      final result = await repository.deleteCustomer(customer.id);

      expect(result, CustomerDeleteResult.deleted);
      expect(await repository.customerById(customer.id), isNull);
      expect(await repository.customers(), isEmpty);
    });

    test(
      'deletes a customer WITH ledger history instead of deactivating',
      () async {
        // This is the whole point of schema v25 -> v26: the customer row goes
        // away even though it owns a sale and a payment. Before, the app had to
        // keep a hidden/deactivated master row alive to satisfy the FKs.
        final customer = await createCustomer(name: 'Priya');
        await seedLedger(customer.id);

        final result = await repository.deleteCustomer(customer.id);

        expect(result, CustomerDeleteResult.deleted);
        expect(await repository.customerById(customer.id), isNull);
      },
    );

    test(
      'keeps the ledger intact and still attributed after the delete',
      () async {
        final customer = await createCustomer(name: 'Priya');
        await seedLedger(customer.id);

        await repository.deleteCustomer(customer.id);

        final sale = await (database.select(
          database.sales,
        )..where((t) => t.id.equals('sale-1'))).getSingle();
        expect(sale.totalPaise, 50000);
        // The id is preserved, not nulled: history keeps its attribution.
        expect(sale.customerId, customer.id);

        final payment = await (database.select(
          database.customerPayments,
        )..where((t) => t.id.equals('pay-1'))).getSingle();
        expect(payment.amountPaise, 20000);
        expect(payment.customerId, customer.id);
        expect(payment.saleId, 'sale-1');
      },
    );

    test('leaves no deactivated zombie holding the unique phone', () async {
      final customer = await createCustomer(name: 'Priya', phone: '9845012345');

      await repository.deleteCustomer(customer.id);

      final rows = await database.select(database.customers).get();
      expect(rows, isEmpty);
      // The phone is genuinely free now, so a new customer can reuse it. A
      // deactivated row would have kept squatting on this global UNIQUE column.
      final reused = await repository.createCustomer(
        name: 'New Priya',
        phone: '9845012345',
      );
      expect(reused.phone, '9845012345');
    });

    test('fails loudly when the customer is already gone', () async {
      final customer = await createCustomer(name: 'Priya');
      await repository.deleteCustomer(customer.id);

      await expectLater(
        repository.deleteCustomer(customer.id),
        throwsA(isA<CustomersFailure>()),
      );
    });

    test('customer_payments.sale_id stays enforced after the delete', () async {
      // Deleting the CUSTOMER must not have cost us the sale->payment
      // relationship, which is a real RESTRICT FK and is what stops a payment
      // from outliving the sale it was allocated to.
      final customer = await createCustomer(name: 'Priya');
      await seedLedger(customer.id);
      await repository.deleteCustomer(customer.id);

      await expectLater(
        database
            .into(database.customerPayments)
            .insert(
              CustomerPaymentsCompanion.insert(
                id: const Value('pay-2'),
                customerId: customer.id,
                amountPaise: 100,
                paymentMethod: 'CASH',
                saleId: const Value('sale-missing'),
                paidAt: DateTime.now().toUtc(),
                createdAt: Value(DateTime.now().toUtc()),
                updatedAt: Value(DateTime.now().toUtc()),
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('customers query', () {
    setUp(() async {
      await createCustomer(name: 'Priya', phone: '9845012345');
      await createCustomer(name: 'Karthik', phone: '9000012345');
      await createCustomer(name: 'Meena', phone: null);
    });

    test('returns all customers sorted by name', () async {
      final all = await repository.customers();
      expect(all.map((c) => c.name).toList(), ['Karthik', 'Meena', 'Priya']);
    });

    test('searches by name case-insensitively', () async {
      final results = await repository.customers(search: 'priya');
      expect(results.map((c) => c.name).toList(), ['Priya']);
    });

    test('searches by phone', () async {
      final results = await repository.customers(search: '900001');
      expect(results.map((c) => c.name).toList(), ['Karthik']);
    });

    test('searches by email', () async {
      await repository.updateCustomer(
        id: (await repository.customers()).last.id,
        name: 'Meena',
        phone: null,
        email: 'meena@example.com',
        isActive: true,
      );

      final results = await repository.customers(search: 'meena@example');
      expect(results.map((c) => c.name).toList(), ['Meena']);
    });

    test('filters by status', () async {
      final karthik = (await repository.customers()).firstWhere(
        (c) => c.name == 'Karthik',
      );
      await repository.setCustomerActive(karthik.id, false);

      final active = await repository.customers(
        status: CustomerStatusFilter.active,
      );
      expect(active.map((c) => c.name).toList(), ['Meena', 'Priya']);

      final inactive = await repository.customers(
        status: CustomerStatusFilter.inactive,
      );
      expect(inactive.map((c) => c.name).toList(), ['Karthik']);
    });
  });

  // Regression: customer rows are shop-owned (name, phone, outstanding
  // balance). Reads used to route through `resolveWritableShopId`, which both
  // minted a shop row as a side effect of listing and silently widened to the
  // writable business. Reads now take the session's scope explicitly.
  group('read scope', () {
    const cafe = 'shop-cafe';
    const truck = 'shop-truck';

    setUp(() async {
      // `customers.shop_id` is a real FK, so the businesses have to exist
      // before rows can be attributed to them.
      for (final entry in {cafe: 'Cafe', truck: 'Food Truck'}.entries) {
        await database
            .into(database.shops)
            .insert(
              ShopsCompanion.insert(id: Value(entry.key), name: entry.value),
            );
      }
    });

    Future<Customer> seed(String shopId, String name, {String? phone}) =>
        repository.createCustomer(name: name, phone: phone, shopId: shopId);

    test('an empty scope returns nothing instead of every shop', () async {
      await seed(cafe, 'Priya');
      await seed(truck, 'Karthik');

      // Fail closed. Reading `[]` as "unscoped" would hand a Food Truck session
      // the Cafe's entire debtor book.
      final results = await repository.customers(shopIds: const []);
      expect(results, isEmpty);
    });

    test('scoped read returns only the requested business', () async {
      await seed(cafe, 'Priya');
      await seed(truck, 'Karthik');

      final cafeOnly = await repository.customers(shopIds: const [cafe]);
      expect(cafeOnly.map((c) => c.name).toList(), ['Priya']);

      final truckOnly = await repository.customers(shopIds: const [truck]);
      expect(truckOnly.map((c) => c.name).toList(), ['Karthik']);
    });

    test('a multi-shop scope (Combined) merges both businesses', () async {
      await seed(cafe, 'Priya');
      await seed(truck, 'Karthik');

      final combined = await repository.customers(shopIds: const [cafe, truck]);
      expect(combined.map((c) => c.name).toSet(), {'Priya', 'Karthik'});
    });

    test('scoped read still honours search and status filters', () async {
      await seed(cafe, 'Priya', phone: '9845012345');
      await seed(cafe, 'Karthik');
      await seed(truck, 'Meena');

      final searched = await repository.customers(
        search: 'meena',
        shopIds: const [cafe, truck],
      );
      expect(searched.map((c) => c.name).toList(), ['Meena']);

      await repository.setCustomerActive(
        (await repository.customers(
          shopIds: const [cafe],
        )).firstWhere((c) => c.name == 'Karthik').id,
        false,
      );
      final active = await repository.customers(
        status: CustomerStatusFilter.active,
        shopIds: const [cafe],
      );
      expect(active.map((c) => c.name).toList(), ['Priya']);
    });

    test('a null scope keeps the legacy unscoped read', () async {
      await seed(cafe, 'Priya');
      await seed(truck, 'Karthik');

      final all = await repository.customers();
      expect(all.map((c) => c.name).toSet(), {'Priya', 'Karthik'});
    });

    test(
      'customerById does not resolve a customer outside the scope',
      () async {
        final truckCustomer = await seed(truck, 'Karthik');

        // A Food Truck session must not be able to read a Cafe profile by id.
        expect(
          await repository.customerById(
            truckCustomer.id,
            shopIds: const [cafe],
          ),
          isNull,
        );
        expect(
          await repository.customerById(truckCustomer.id, shopIds: const []),
          isNull,
        );
        expect(
          (await repository.customerById(
            truckCustomer.id,
            shopIds: const [truck],
          ))?.name,
          'Karthik',
        );
        // Unscoped still resolves it (single-shop legacy installs).
        expect(
          (await repository.customerById(truckCustomer.id))?.name,
          'Karthik',
        );
      },
    );

    test('reading a scoped customer list does not mint a shop row', () async {
      await seed(cafe, 'Priya');

      // Drive a scope that names a business which does not exist yet. A
      // writable-shop fallback would insert it here.
      await repository.customers(shopIds: const ['never-created-shop']);

      final shopIds = await database
          .select(database.shops)
          .get()
          .then((rows) => rows.map((r) => r.id).toList());
      expect(shopIds, isNot(contains('never-created-shop')));
    });

    test(
      'phoneExists stays global so a cross-business clash is reported',
      () async {
        await seed(cafe, 'Priya', phone: '9845012345');

        // `customers.phone` carries one global UNIQUE index, so a shop-narrowed
        // check would report this free and the insert would then be rejected.
        expect(
          await repository.phoneExists('9845012345'),
          isTrue,
          reason:
              'the number is taken under another business and SQLite would '
              'still reject the insert',
        );
        // exceptId still excludes the holder so an edit can keep its own number.
        final priya = (await repository.customers(
          shopIds: const [cafe],
        )).single;
        expect(
          await repository.phoneExists('9845012345', exceptId: priya.id),
          isFalse,
        );
        expect(await repository.phoneExists('9999999999'), isFalse);
      },
    );
  });
}
