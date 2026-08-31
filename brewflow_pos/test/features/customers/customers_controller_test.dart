import 'dart:async';

import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_customers_repository.dart';

void main() {
  late FakeCustomersRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [customersRepositoryProvider.overrideWithValue(fake)],
  );

  final now = DateTime.now().toUtc();

  Customer customer(
    String id,
    String name, {
    String? phone,
    String? email,
    String? address,
    bool isActive = true,
  }) => Customer(
    id: id,
    name: name,
    phone: phone,
    email: email,
    address: address,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() => fake = FakeCustomersRepository());

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

  group('customersProvider', () {
    test('starts loading and resolves to the stored customers', () async {
      fake.storedCustomers.addAll([
        customer('c2', 'Karthik'),
        customer('c1', 'Priya'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(customersProvider), isA<AsyncLoading>());

      await container.read(customersProvider.future);

      final customers = container.read(customersProvider).value!;
      // Sorted by name by the repository.
      expect(customers.map((c) => c.name), ['Karthik', 'Priya']);
      expect(fake.customersCalls, 1);
    });

    test('resolves to empty when there are no customers', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(customersProvider.future);
      expect(container.read(customersProvider).value, isEmpty);
    });

    test('surfaces CustomersFailure without wrapping it', () async {
      fake.loadError = const DuplicatePhoneFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(customersProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(customersProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<DuplicatePhoneFailure>());
    });

    test('maps unexpected errors to UnexpectedCustomersFailure', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(customersProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(customersProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedCustomersFailure>());
    });

    test('stays loading while the load gate is closed', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final gate = Completer<void>();
      fake.loadGate = gate;
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(customersProvider);
      expect(container.read(customersProvider), isA<AsyncLoading>());

      gate.complete();
      await container.read(customersProvider.future);
      expect(container.read(customersProvider).value, hasLength(1));
    });
  });

  group('customersFilterProvider', () {
    test('rebuilds customersProvider when the filter changes', () async {
      fake.storedCustomers.addAll([
        customer('c1', 'Priya', phone: '9845012345'),
        customer('c2', 'Karthik', phone: '9000012345'),
        customer('c3', 'Meena', isActive: false),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(customersProvider.future);
      expect(container.read(customersProvider).value, hasLength(3));

      container.read(customersFilterProvider.notifier).setQuery('priya');
      await awaitUntil(
        container,
        () =>
            (container.read(customersProvider).value ?? const <Customer>[])
                .length ==
            1,
      );
      expect(container.read(customersProvider).value!.single.name, 'Priya');

      container.read(customersFilterProvider.notifier).setQuery('900001');
      await awaitUntil(container, () {
        final list =
            container.read(customersProvider).value ?? const <Customer>[];
        return list.length == 1 && list.single.name == 'Karthik';
      });
      expect(container.read(customersProvider).value!.single.name, 'Karthik');

      container.read(customersFilterProvider.notifier).setQuery('');
      await awaitUntil(
        container,
        () =>
            (container.read(customersProvider).value ?? const <Customer>[])
                .length ==
            3,
      );

      container
          .read(customersFilterProvider.notifier)
          .setStatus(CustomerStatusFilter.inactive);
      await awaitUntil(container, () {
        final list =
            container.read(customersProvider).value ?? const <Customer>[];
        return list.length == 1 && list.single.name == 'Meena';
      });
      expect(container.read(customersProvider).value!.single.name, 'Meena');

      container.read(customersFilterProvider.notifier).clear();
      await awaitUntil(
        container,
        () =>
            (container.read(customersProvider).value ?? const <Customer>[])
                .length ==
            3,
      );
      expect(container.read(customersProvider).value, hasLength(3));
    });
  });

  group('mutations', () {
    test('createCustomer adds the customer and refreshes the list', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(customersProvider.future);
      expect(container.read(customersProvider).value, isEmpty);

      await container
          .read(customersProvider.notifier)
          .create(name: 'Priya', phone: '9845012345');

      await awaitUntil(
        container,
        () => container.read(customersProvider).value?.length == 1,
      );
      expect(container.read(customersProvider).value!.single.name, 'Priya');
    });

    test('createCustomer propagates duplicate phone failures', () async {
      fake.storedCustomers.add(customer('c1', 'Priya', phone: '9845012345'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(customersProvider.notifier)
            .create(name: 'Karthik', phone: '9845012345'),
        throwsA(isA<DuplicatePhoneFailure>()),
      );
      expect(fake.storedCustomers, hasLength(1));
    });

    test('updateCustomer refreshes the list with new details', () async {
      fake.storedCustomers.add(customer('c1', 'Priya', phone: '9845012345'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(customersProvider.notifier)
          .updateCustomer(
            id: 'c1',
            name: 'Priya R',
            phone: '9000012345',
            isActive: true,
          );

      await awaitUntil(
        container,
        () => container.read(customersProvider).value?.single.name == 'Priya R',
      );
      final updated = container.read(customersProvider).value!.single;
      expect(updated.phone, '9000012345');
    });

    test('setActive refreshes the list with the new status', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(customersProvider.notifier).setActive('c1', false);

      await awaitUntil(
        container,
        () => container.read(customersProvider).value!.single.isActive == false,
      );
      expect(container.read(customersProvider).value!.single.isActive, isFalse);
    });

    test(
      'setActive reactivates and restores a customer to the active list',
      () async {
        fake.storedCustomers.add(
          customer('c1', 'Priya').copyWith(isActive: false),
        );
        final container = buildContainer();
        addTearDown(container.dispose);

        await container.read(customersProvider.notifier).setActive('c1', true);

        await awaitUntil(
          container,
          () => container.read(customersProvider).value!.single.isActive,
        );
        final restored = container.read(customersProvider).value!.single;
        expect(restored.isActive, isTrue);
        expect(restored.id, 'c1');
      },
    );

    test('unexpected mutation errors are wrapped', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      fake.loadError = const UnexpectedCustomersFailure();
      await expectLater(
        container.read(customersProvider.notifier).create(name: 'Priya'),
        throwsA(isA<UnexpectedCustomersFailure>()),
      );
    });
  });

  group('queries', () {
    test('customerById returns the stored customer', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(
        (await container.read(customersProvider.notifier).byId('c1'))!.name,
        'Priya',
      );
      expect(
        await container.read(customersProvider.notifier).byId('missing'),
        isNull,
      );
    });

    test('phoneExists reports duplicates and honours exceptId', () async {
      fake.storedCustomers.add(customer('c1', 'Priya', phone: '9845012345'));
      final container = buildContainer();
      addTearDown(container.dispose);

      final controller = container.read(customersProvider.notifier);
      expect(await controller.phoneExists('9845012345'), isTrue);
      expect(
        await controller.phoneExists('9845012345', exceptId: 'c1'),
        isFalse,
      );
      expect(await controller.phoneExists('9000012345'), isFalse);
    });
  });
}
