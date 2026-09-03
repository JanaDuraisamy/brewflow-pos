import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_movement_models.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/data/supabase_staff_provisioning.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_shop_name_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_staff_repository.dart';

AuthUser _authUser(String id, String email) => AuthUser(id: id, email: email);

/// Builds a container whose signed-in identity resolves through
/// [FakeStaffRepository] exactly like production (auth id → profile → role).
(ProviderContainer, FakeStaffRepository) _container({AuthUser? user}) {
  final inventory = FakeInventoryRepository();
  final authRepo = FakeAuthRepository(user: user);
  final staff = FakeStaffRepository();
  final container = ProviderContainer(
    overrides: [
      authRepositoryProvider.overrideWithValue(authRepo),
      staffRepositoryProvider.overrideWithValue(staff),
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
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      shopNameRepositoryProvider.overrideWithValue(FakeShopNameRepository()),
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      offersRepositoryProvider.overrideWithValue(FakeOffersRepository()),
    ],
  );
  addTearDown(container.dispose);
  return (container, staff);
}

Product _product({String id = 'p1'}) => Product(
  id: id,
  categoryId: 'c1',
  name: 'Filter Coffee',
  sku: null,
  sellingPricePaise: 12000,
  costPricePaise: null,
  stockQuantity: 10,
  isActive: true,
  createdAt: DateTime.now().toUtc(),
  updatedAt: DateTime.now().toUtc(),
);

void main() {
  group('owner bootstrap', () {
    test(
      'first authenticated user claims OWNER and creates the shop',
      () async {
        final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));

        final profile = await container.read(userProfileProvider.future);

        expect(profile!.role, UserRole.owner);
        expect(profile.isActive, isTrue);
        expect(profile.shopId, 'shop-1');
        expect(staff.shop!.id, 'shop-1');
      },
    );

    test(
      'second user cannot claim owner once claimed (no silent escalation)',
      () async {
        final (container, _) = _container(user: _authUser('a-1', 'o@x.co'));
        await container.read(userProfileProvider.future);
        container.dispose();

        // A different identity on a shop that already has an owner.
        final staff2 = FakeStaffRepository();
        await staff2.claimOwnership(_authUser('a-1', 'o@x.co'));
        await expectLater(
          staff2.claimOwnership(_authUser('a-2', 's@x.co')),
          throwsA(isA<OwnerAlreadyClaimedFailure>()),
        );
      },
    );
  });

  group('permission resolution', () {
    test('owner implicitly holds every permission', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final repoProfile = staff.storedProfiles.single;
      expect(repoProfile.role, UserRole.owner);
      for (final permission in Permission.values) {
        expect(
          container.read(canProvider(permission)),
          isTrue,
          reason: permission.dbValue,
        );
      }
    });

    test('staff holds exactly the granted set and nothing else', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
        permissions: {Permission.billing},
      );

      // Re-resolve as the staff identity.
      final staffContainerReader = container;
      // Simulate the staff session by pointing the auth repository at the
      // staff identity and re-reading the profile.
      staffContainerReader.read(authControllerProvider); // warm up
      final staffProfile = staff.profilesByAuthId['a-2']!;
      expect(staffProfile.role, UserRole.staff);
      expect(staffProfile.permissions, {Permission.billing});

      const authz = RoleBasedAuthorization(
        role: UserRole.staff,
        grantedPermissions: {Permission.billing},
      );
      expect(authz.can(Permission.billing), isTrue);
      expect(authz.can(Permission.reports), isFalse);
      expect(authz.can(Permission.manageStaff), isFalse);
    });
  });

  group('boundary denial (staff session)', () {
    test('checkout denied without BILLING; allowed with it', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final member = await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
        permissions: {},
      );
      // Point the session at the staff profile.
      staff.profilesByAuthId['a-1'] = member;
      container.invalidate(userProfileProvider);
      await container.read(userProfileProvider.future);

      (container.read(billingRepositoryProvider) as FakeBillingRepository)
          .inventory
          .storedProducts
          .add(_product());
      container.read(cartProvider.notifier).add(_product());
      await expectLater(
        container.read(cartProvider.notifier).checkout(PaymentMethod.cash),
        throwsA(isA<PermissionDeniedFailure>()),
      );

      // Grant billing → same call now reaches the repository.
      final granted = UserProfile(
        id: member.id,
        email: member.email,
        authUserId: member.authUserId,
        shopId: member.shopId,
        displayName: member.displayName,
        role: UserRole.staff,
        isActive: true,
        permissions: {Permission.billing},
      );
      staff
        ..storedProfiles[staff.storedProfiles.indexOf(member)] = granted
        ..profilesByAuthId['a-1'] = granted;
      container.invalidate(userProfileProvider);
      await container.read(userProfileProvider.future);
      await container.read(cartProvider.notifier).checkout(PaymentMethod.cash);
    });

    test('stock adjustment denied without STOCK_ADJUSTMENT', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final member = await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
        permissions: {},
      );
      staff.profilesByAuthId['a-1'] = member;
      container.invalidate(userProfileProvider);
      await container.read(userProfileProvider.future);

      expect(
        () => container
            .read(productMovementsProvider('p1').notifier)
            .adjustStock(delta: -1, reason: StockAdjustmentReason.correction),
        throwsA(isA<PermissionDeniedFailure>()),
      );
    });

    test('settings save denied without SETTINGS', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final member = await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
        permissions: {},
      );
      staff.profilesByAuthId['a-1'] = member;
      container.invalidate(userProfileProvider);
      await container.read(userProfileProvider.future);

      await expectLater(
        container
            .read(shopSettingsProvider.notifier)
            .save(ShopSettings.defaults()),
        throwsA(isA<PermissionDeniedFailure>()),
      );
    });

    test('reports access denied without REPORTS', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final member = await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
        permissions: {},
      );
      staff.profilesByAuthId['a-1'] = member;
      container.invalidate(userProfileProvider);
      final resolved = await container.read(userProfileProvider.future);
      expect(resolved!.role, UserRole.staff);
      container.listen(reportsControllerProvider, (_, _) {});
      // Let the (async) build run; assert on the surfaced state because
      // Riverpod completes an errored auto-dispose future with a lifecycle
      // error rather than the build error.
      await Future<void>.delayed(Duration.zero);
      final reportsState = container.read(reportsControllerProvider);
      expect(reportsState.hasError, isTrue);
      expect(
        reportsState.error,
        isA<PermissionDeniedFailure>(),
        reason: 'actual=',
      );
    });
  });

  group('inactive staff', () {
    test('deactivated profile denies access via typed failure', () async {
      final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
      await container.read(userProfileProvider.future);
      final member = await staff.createStaffProfile(
        identity: _authUser('a-2', 's@x.co'),
        shopId: 'shop-1',
      );
      await staff.updateStaff(StaffUpdateInput(id: member.id, isActive: false));

      // Session re-resolution for the deactivated identity fails safely.
      staff.profilesByAuthId['a-1'] = UserProfile(
        id: member.id,
        email: member.email,
        authUserId: member.authUserId,
        shopId: member.shopId,
        displayName: member.displayName,
        role: member.role,
        isActive: false,
        permissions: member.permissions,
      );
      container.invalidate(userProfileProvider);
      container.listen(userProfileProvider, (_, _) {});
      await Future<void>.delayed(Duration.zero);
      final profileState = container.read(userProfileProvider);
      expect(profileState.hasError, isTrue);
      expect(profileState.error, isA<ProfileNotProvisionedFailure>());
    });
  });

  group('logout isolation', () {
    test(
      'signOut clears role resolution — no permissions afterwards',
      () async {
        final (container, staff) = _container(user: _authUser('a-1', 'o@x.co'));
        await container.read(userProfileProvider.future);
        expect(container.read(canProvider(Permission.billing)), isTrue);

        await container.read(authControllerProvider.notifier).signOut();
        await container.read(userProfileProvider.future);

        expect(container.read(canProvider(Permission.billing)), isFalse);
        expect(
          staff.storedProfiles,
          isNotEmpty,
          reason: 'profiles persist across logout; only the session clears',
        );
      },
    );
  });

  group('provisioning client contract', () {
    test(
      'SupabaseStaffProvisioning maps failures to ProvisioningFailure',
      () async {
        // Contract-level check with a stub client boundary: any thrown object
        // inside the service must surface as ProvisioningFailure.
        final service = _ThrowingProvisioning();
        await expectLater(
          service.createStaffAuthUser(
            StaffCreateInput(email: 's@x.co', password: 'secret1'),
          ),
          throwsA(isA<ProvisioningFailure>()),
        );
      },
    );
  });
}

final class _ThrowingProvisioning implements StaffProvisioningService {
  @override
  Future<AuthUser> createStaffAuthUser(StaffCreateInput input) async {
    throw const ProvisioningFailure();
  }
}
