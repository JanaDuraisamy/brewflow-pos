import 'package:brewflow_pos/core/database/app_database.dart' show AppDatabase;
import 'package:brewflow_pos/features/customers/data/drift_customers_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
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
}
