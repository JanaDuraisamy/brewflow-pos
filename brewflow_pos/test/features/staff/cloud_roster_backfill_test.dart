import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_movement_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_shop_name_repository.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/fake_stock_movement_repository.dart';

const _owner = AuthUser(id: 'o-1', email: 'owner@brewflow.example');

void main() {
  (ProviderContainer, FakeStaffRepository, FakeCloudShopResolver) build({
    required AuthUser user,
    required List<CloudStaffMember> roster,
  }) {
    final inventory = FakeInventoryRepository();
    final authRepo = FakeAuthRepository(user: user);
    final staff = FakeStaffRepository();
    final resolver = FakeCloudShopResolver();
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(authRepo),
        staffRepositoryProvider.overrideWithValue(staff),
        cloudShopResolverProvider.overrideWithValue(resolver),
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
    return (container, staff, resolver);
  }

  group('cloud roster backfill', () {
    test(
      'the OWNER mirrors cloud staff onto a second device on login and keeps '
      'the owner row untouched',
      () async {
        // Device already bootstrapped as OWNER (fast path).
        final roster = [
          CloudStaffMember(
            authUserId: 'a-staff-1',
            email: 'ava@brewflow.example',
            role: 'STAFF',
            isActive: true,
            displayName: 'Ava Stone',
            permissions: {Permission.billing, Permission.reports},
          ),
          CloudStaffMember(
            authUserId: 'a-staff-2',
            email: 'leo@brewflow.example',
            role: 'STAFF',
            isActive: true,
            permissions: {Permission.viewInventory},
          ),
        ];
        final (container, staff, resolver) = build(
          user: _owner,
          roster: roster,
        );
        staff.ensureShop();
        await staff.claimOwnership(_owner);
        resolver.roster = roster;

        await container.read(userProfileProvider.future);

        final members = await staff.staffMembers();
        final byEmail = {for (final m in members) m.email: m};
        expect(byEmail, hasLength(2));
        final ava = byEmail['ava@brewflow.example']!;
        expect(ava.role, UserRole.staff);
        expect(ava.isActive, isTrue);
        expect(ava.shopId, 'shop-1');
        expect(ava.displayName, 'Ava Stone');
        expect(ava.permissions, {
          Permission.billing,
          Permission.reports,
        }, reason: 'cloud-authoritative grants are mirrored');
        expect(byEmail['leo@brewflow.example']!.permissions, {
          Permission.viewInventory,
        });
        // The owner row is untouched by the pull.
        final owners = staff.storedProfiles.where((p) => p.isOwner);
        expect(owners, hasLength(1));
        expect(owners.single.authUserId, 'o-1');
        expect(resolver.rosterQueries, ['shop-1']);
      },
    );

    test('an OWNER cloud row is never mirrored as local STAFF', () async {
      final (container, staff, resolver) = build(
        user: _owner,
        roster: const [],
      );
      staff.ensureShop();
      await staff.claimOwnership(_owner);
      // Cloud mistakenly carries an OWNER row for another auth user; the
      // pull must skip it instead of minting a local STAFF impersonation.
      resolver.roster = [
        CloudStaffMember(
          authUserId: 'a-owner-2',
          email: 'owner2@brewflow.example',
          role: 'OWNER',
          isActive: true,
        ),
        CloudStaffMember(
          authUserId: 'a-staff-1',
          email: 'ava@brewflow.example',
          role: 'STAFF',
          isActive: true,
          permissions: {Permission.billing},
        ),
      ];

      await container.read(userProfileProvider.future);

      final members = await staff.staffMembers();
      expect(members.map((m) => m.email), ['ava@brewflow.example']);
      expect(staff.storedProfiles.where((p) => p.isOwner), hasLength(1));
    });

    test('empty cloud permissions keep the existing local grant set (pre-push '
        'install keeps working)', () async {
      final staff = FakeStaffRepository();
      await staff.ensureShop();
      await staff.claimOwnership(_owner);
      await staff.createStaffProfile(
        identity: const AuthUser(id: 'a-1', email: 'ava@brewflow.example'),
        shopId: 'shop-1',
        permissions: {Permission.billing},
      );

      // Cloud has the profile but no grant set pushed yet.
      final updated = await staff.upsertStaffProfile(
        authUserId: 'a-1',
        email: 'ava@brewflow.example',
        shopId: 'shop-1',
        isActive: true,
        permissions: const {},
        displayName: 'Ava Stone',
      );

      expect(updated!.role, UserRole.staff);
      expect(
        updated.permissions,
        {Permission.billing},
        reason: 'an empty cloud grant set must not wipe local grants',
      );
      expect(updated.displayName, 'Ava Stone');
    });

    test(
      'a cloud push with grants overrides local grants for the member',
      () async {
        final staff = FakeStaffRepository();
        await staff.ensureShop();
        await staff.claimOwnership(_owner);
        await staff.createStaffProfile(
          identity: const AuthUser(id: 'a-1', email: 'ava@brewflow.example'),
          shopId: 'shop-1',
          permissions: {Permission.billing},
        );

        final updated = await staff.upsertStaffProfile(
          authUserId: 'a-1',
          email: 'ava@brewflow.example',
          shopId: 'shop-1',
          isActive: true,
          permissions: {Permission.reports, Permission.orders},
        );

        expect(updated!.permissions, {Permission.reports, Permission.orders});
      },
    );

    test(
      'a missing local profile is created as STAFF with cloud grants',
      () async {
        final staff = FakeStaffRepository();
        await staff.ensureShop();
        await staff.claimOwnership(_owner);

        final created = await staff.upsertStaffProfile(
          authUserId: 'a-new',
          email: 'new@brewflow.example',
          shopId: 'shop-1',
          isActive: true,
          permissions: {Permission.viewInventory},
          displayName: 'New Member',
        );

        expect(created!.role, UserRole.staff);
        expect(created.permissions, {Permission.viewInventory});
        expect(created.displayName, 'New Member');
        expect(await staff.staffMembers(), hasLength(1));
      },
    );

    test('a cloud roster outage never blocks authorization', () async {
      final (container, staff, resolver) = build(
        user: _owner,
        roster: const [],
      );
      staff.ensureShop();
      await staff.claimOwnership(_owner);
      resolver.rosterThrows = true;

      final profile = await container.read(userProfileProvider.future);

      expect(profile!.isOwner, isTrue);
      expect(staff.storedProfiles.length, 1);
    });
  });
}
