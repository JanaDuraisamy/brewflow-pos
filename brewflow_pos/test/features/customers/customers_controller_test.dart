import 'dart:async';

import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/customers_repository.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_preferences_storage.dart';
import '../../helpers/test_providers.dart';

/// Binding `AppStorage` keeps the business switcher's read-only identity
/// resolution off its throwing path. Without it every scoped read pays a
/// caught `StateError` round-trip through `_persistedFoodTruckId`, which
/// widens the `invalidate -> AsyncLoading` window enough for the polling
/// helpers below to observe a half-built provider.
class _FakeSecure implements SecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await AppStorage.init(
      secure: _FakeSecure(),
      preferences: FakePreferencesStorage(),
    );
  });

  late FakeCustomersRepository fake;

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      customersRepositoryProvider.overrideWithValue(fake),
      // Customer lists/profiles are shop-scoped, so the fixture has to declare
      // the signed-in owner session. Without it the switcher fails closed and
      // the controller correctly reads zero customers.
      ...businessScopeOverrides(),
    ],
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
  ///
  /// Conditions must tolerate a transient `AsyncLoading` (null `.value`) —
  /// the mutation legitimately invalidates and reloads the provider, and the
  /// shop-scoped read adds an extra async hop to that rebuild.
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

    // Regression: the list used to be read through a writable-shop fallback,
    // which minted/selected a business instead of honouring the session. The
    // controller must pass the scope the switcher resolved.
    test('reads through the owner session scope', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = buildContainer();
      addTearDown(container.dispose);

      await container.read(customersProvider.future);

      expect(fake.lastCustomersShopIds, [kTestCafeShopId]);
    });

    test('a staff session is pinned to their own shop', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = ProviderContainer(
        overrides: [
          customersRepositoryProvider.overrideWithValue(fake),
          ...businessScopeOverrides(
            profile: testStaffProfile(shopId: kTestFoodTruckShopId),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(customersProvider.future);

      // Staff are single-shop by contract: never the Cafe, never Combined.
      expect(fake.lastCustomersShopIds, [kTestFoodTruckShopId]);
    });

    test(
      'fails closed to no customers when no shop identity resolves',
      () async {
        fake.storedCustomers.add(customer('c1', 'Priya'));
        final container = ProviderContainer(
          overrides: [
            customersRepositoryProvider.overrideWithValue(fake),
            // A profile carrying no shop id leaves the Cafe identity
            // unresolvable, which is exactly the fail-closed case.
            ...businessScopeOverrides(
              profile: const UserProfile(
                id: 'test-owner',
                email: 'owner@brewflow.test',
                role: UserRole.owner,
                isActive: true,
                permissions: {},
              ),
            ),
          ],
        );
        addTearDown(container.dispose);

        await container.read(customersProvider.future);

        // Empty scope, never null: a null scope would read as "every shop".
        expect(fake.lastCustomersShopIds, isNotNull);
        expect(fake.lastCustomersShopIds, isEmpty);
        expect(container.read(customersProvider).value, isEmpty);
      },
    );

    test('reloads when the business scope changes', () async {
      // Seed the persisted Food Truck so Combined has a second business to
      // widen into; otherwise it collapses back to the Cafe alone.
      await AppStorage.preferences.writeString(
        BusinessSwitcherController.foodTruckShopIdKey,
        kTestFoodTruckShopId,
      );
      // The switcher's selection is persisted globally, so undo both writes
      // rather than leaking a Combined/Food Truck session into later tests.
      addTearDown(() async {
        await AppStorage.preferences.remove(
          BusinessSwitcherController.foodTruckShopIdKey,
        );
      });

      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = buildContainer();
      addTearDown(container.dispose);
      // Hold a listener: the page is what keeps this provider subscribed, and
      // without one an external context change never reaches `build()`.
      final subscription = container.listen(customersProvider, (_, __) {});
      addTearDown(subscription.close);

      await container.read(customersProvider.future);
      expect(fake.lastCustomersShopIds, [kTestCafeShopId]);

      // Switching to Combined widens the scope, which must re-read rather than
      // keep serving the Cafe-only list.
      await container
          .read(businessSwitcherProvider.notifier)
          .select(BusinessContext.all);
      addTearDown(() async {
        await AppStorage.preferences.remove('business_switcher_context');
      });

      await awaitUntil(container, () => fake.lastCustomersShopIds?.length == 2);
      expect(
        fake.lastCustomersShopIds,
        containsAll([kTestCafeShopId, kTestFoodTruckShopId]),
      );
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
        () =>
            container.read(customersProvider).value?.singleOrNull?.isActive ==
            false,
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
          () =>
              container.read(customersProvider).value?.singleOrNull?.isActive ==
              true,
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

  group('delete authorization', () {
    /// Builds a container signed in as a non-owner staff member, so
    /// [requireOwner] actually has a profile to reject.
    Future<ProviderContainer> staffContainer() async {
      const member = AuthUser(id: 'u2', email: 'staff@brewflow.example');
      final staffRepo = FakeStaffRepository();
      final shop = await staffRepo.ensureShop();
      await staffRepo.claimOwnershipForCloud(
        member,
        shopId: shop.id,
        role: UserRole.staff,
        permissions: {Permission.billing},
      );
      final container = ProviderContainer(
        overrides: [
          customersRepositoryProvider.overrideWithValue(fake),
          staffRepositoryProvider.overrideWithValue(staffRepo),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: member),
          ),
        ],
      );
      addTearDown(container.dispose);
      // Wait for the profile to resolve so the gate is not skipped by a null
      // (still-loading) profile.
      final profile = await container.read(userProfileProvider.future);
      expect(profile!.isOwner, isFalse);
      return container;
    }

    test('a staff member cannot delete a customer', () async {
      // True deletion is a destructive, irreversible capability, so it stays
      // owner-only. Billing permission is NOT enough.
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = await staffContainer();

      await expectLater(
        container.read(customersProvider.notifier).delete('c1'),
        throwsA(isA<PermissionDeniedFailure>()),
      );
      expect(fake.storedCustomers.map((c) => c.id), contains('c1'));
    });

    test('the owner can delete a customer', () async {
      fake.storedCustomers.add(customer('c1', 'Priya'));
      final container = buildContainer();
      addTearDown(container.dispose);

      final result = await container
          .read(customersProvider.notifier)
          .delete('c1');

      expect(result, CustomerDeleteResult.deleted);
      expect(fake.storedCustomers, isEmpty);
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
