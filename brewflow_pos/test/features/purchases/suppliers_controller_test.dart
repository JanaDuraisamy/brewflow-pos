import 'dart:async';

import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/domain/suppliers_repository.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_suppliers_repository.dart';

void main() {
  late FakeSuppliersRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [suppliersRepositoryProvider.overrideWithValue(fake)],
  );

  final now = DateTime.now().toUtc();

  Supplier supplier(
    String id,
    String name, {
    String? phone,
    String? email,
    String? address,
    String? notes,
    bool isActive = true,
  }) => Supplier(
    id: id,
    name: name,
    phone: phone,
    email: email,
    address: address,
    notes: notes,
    isActive: isActive,
    createdAt: now,
    updatedAt: now,
  );

  setUp(() => fake = FakeSuppliersRepository());

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

  group('suppliersProvider', () {
    test('starts loading and resolves to the stored suppliers', () async {
      fake.storedSuppliers.addAll([
        supplier('s2', 'Karthik Trading'),
        supplier('s1', 'Priya Exports'),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(suppliersProvider), isA<AsyncLoading>());

      await container.read(suppliersProvider.future);

      final suppliers = container.read(suppliersProvider).value!;
      // Sorted by name by the repository.
      expect(suppliers.map((s) => s.name), [
        'Karthik Trading',
        'Priya Exports',
      ]);
      expect(fake.suppliersCalls, 1);
    });

    test('resolves to empty when there are no suppliers', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(suppliersProvider.future);
      expect(container.read(suppliersProvider).value, isEmpty);
    });

    test('rebuilds the list when search or status changes', () async {
      fake.storedSuppliers.addAll([
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
        supplier('s2', 'Brew Traders', phone: '9000012345'),
        supplier('s3', 'Old Mills', isActive: false),
      ]);
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(suppliersProvider.future);
      expect(container.read(suppliersProvider).value, hasLength(3));

      container.read(suppliersFilterProvider.notifier).setQuery('acme');
      await awaitUntil(
        container,
        () =>
            (container.read(suppliersProvider).value ?? const <Supplier>[])
                .length ==
            1,
      );
      expect(
        container.read(suppliersProvider).value!.single.name,
        'Acme Supplies',
      );

      container.read(suppliersFilterProvider.notifier).setQuery('900001');
      await awaitUntil(container, () {
        final list =
            container.read(suppliersProvider).value ?? const <Supplier>[];
        return list.length == 1 && list.single.name == 'Brew Traders';
      });
      expect(
        container.read(suppliersProvider).value!.single.name,
        'Brew Traders',
      );

      container.read(suppliersFilterProvider.notifier).setQuery('');
      container
          .read(suppliersFilterProvider.notifier)
          .setStatus(SupplierStatusFilter.inactive);
      await awaitUntil(container, () {
        final list =
            container.read(suppliersProvider).value ?? const <Supplier>[];
        return list.length == 1 && list.single.name == 'Old Mills';
      });
      expect(container.read(suppliersProvider).value!.single.name, 'Old Mills');

      container.read(suppliersFilterProvider.notifier).clear();
      await awaitUntil(
        container,
        () =>
            (container.read(suppliersProvider).value ?? const <Supplier>[])
                .length ==
            3,
      );
      expect(container.read(suppliersProvider).value, hasLength(3));
    });

    test('surfaces SuppliersFailure without wrapping it', () async {
      fake.loadError = const DuplicateSupplierPhoneFailure();
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(suppliersProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(suppliersProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<DuplicateSupplierPhoneFailure>());
    });

    test('maps unexpected errors to UnexpectedSuppliersFailure', () async {
      fake.loadError = StateError('boom');
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(suppliersProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(suppliersProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<UnexpectedSuppliersFailure>());
    });

    test('stays loading while the load gate is closed', () async {
      fake.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      final gate = Completer<void>();
      fake.loadGate = gate;
      final container = buildContainer();
      addTearDown(container.dispose);

      container.read(suppliersProvider);
      expect(container.read(suppliersProvider), isA<AsyncLoading>());

      gate.complete();
      await container.read(suppliersProvider.future);
      expect(container.read(suppliersProvider).value, hasLength(1));
    });
  });

  group('mutations', () {
    test('create adds the supplier and refreshes the list', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(suppliersProvider.future);
      expect(container.read(suppliersProvider).value, isEmpty);
      expect(fake.suppliersCalls, 1);

      await container
          .read(suppliersProvider.notifier)
          .create(name: 'Acme Supplies', phone: '9845012345');

      await awaitUntil(
        container,
        () => container.read(suppliersProvider).value?.length == 1,
      );
      expect(
        container.read(suppliersProvider).value!.single.name,
        'Acme Supplies',
      );
      // The mutation invalidated the provider and reloaded from the store.
      expect(fake.suppliersCalls, 2);
    });

    test('create propagates duplicate phone failures', () async {
      fake.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      await expectLater(
        container
            .read(suppliersProvider.notifier)
            .create(name: 'Brew Traders', phone: '9845012345'),
        throwsA(isA<DuplicateSupplierPhoneFailure>()),
      );
      expect(fake.storedSuppliers, hasLength(1));
    });

    test('update refreshes the list with new details', () async {
      fake.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', phone: '9845012345'),
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      await container
          .read(suppliersProvider.notifier)
          .updateSupplier(
            id: 's1',
            name: 'Acme Supplies Co',
            phone: '9000012345',
            isActive: true,
          );

      await awaitUntil(
        container,
        () =>
            container.read(suppliersProvider).value?.single.name ==
            'Acme Supplies Co',
      );
      final updated = container.read(suppliersProvider).value!.single;
      expect(updated.phone, '9000012345');
    });

    test('deactivate hides the supplier and refreshes the list', () async {
      fake.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(suppliersProvider.notifier).setActive('s1', false);

      await awaitUntil(
        container,
        () => container.read(suppliersProvider).value!.single.isActive == false,
      );
      expect(container.read(suppliersProvider).value!.single.isActive, isFalse);
    });

    test('activate restores the supplier and refreshes the list', () async {
      fake.storedSuppliers.add(
        supplier('s1', 'Acme Supplies', isActive: false),
      );
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(suppliersProvider.notifier).setActive('s1', true);

      await awaitUntil(
        container,
        () => container.read(suppliersProvider).value!.single.isActive,
      );
      expect(container.read(suppliersProvider).value!.single.isActive, isTrue);
    });

    test('unexpected mutation errors are wrapped', () async {
      final container = buildContainer();
      addTearDown(container.dispose);

      fake.loadError = const UnexpectedSuppliersFailure();
      await expectLater(
        container.read(suppliersProvider.notifier).create(name: 'Acme'),
        throwsA(isA<UnexpectedSuppliersFailure>()),
      );
    });
  });

  group('queries', () {
    test('supplierById returns the stored supplier', () async {
      fake.storedSuppliers.add(supplier('s1', 'Acme Supplies'));
      final container = buildContainer();
      addTearDown(container.dispose);

      expect(
        (await container.read(suppliersProvider.notifier).byId('s1'))!.name,
        'Acme Supplies',
      );
      expect(
        await container.read(suppliersProvider.notifier).byId('missing'),
        isNull,
      );
    });

    test('phoneExists reports duplicates and honours exceptId', () async {
      fake.storedSuppliers.add(supplier('s1', 'Acme', phone: '9845012345'));
      final container = buildContainer();
      addTearDown(container.dispose);

      final controller = container.read(suppliersProvider.notifier);
      expect(await controller.phoneExists('9845012345'), isTrue);
      expect(
        await controller.phoneExists('9845012345', exceptId: 's1'),
        isFalse,
      );
      expect(await controller.phoneExists('9000012345'), isFalse);
    });
  });
}
