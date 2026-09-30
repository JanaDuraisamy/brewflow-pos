import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// Food Truck staff deletion — controller contract.
///
/// The server RPC is the authorization boundary, but the controller must also
/// refuse OWNER targets before any cloud call, pass the target auth identity
/// through exactly once, and leave the local mirror untouched whenever the
/// cloud refuses. These tests use Food Truck and Cafe shops together so a
/// Food Truck delete can never disturb the Cafe roster.
/// ---------------------------------------------------------------------------

const _owner = AuthUser(id: 'a-owner', email: 'owner@brewflow.example');
const _member = AuthUser(id: 'a-staff', email: 'staff@brewflow.example');
const _cafeShop = 'shop-cafe';
const _truckShop = 'shop-truck';

void main() {
  ProviderContainer containerWith({
    required AuthUser session,
    required FakeStaffRepository repository,
    required FakeCloudShopResolver resolver,
  }) {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(user: session),
        ),
        staffRepositoryProvider.overrideWithValue(repository),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(resolver),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<(FakeStaffRepository, FakeCloudShopResolver, UserProfile)>
  seedOwnerAndTruckStaff({bool cloudDeleteSucceeds = true}) async {
    final repository = FakeStaffRepository();
    await repository.claimOwnership(_owner);
    await repository.createStaffProfile(
      identity: const AuthUser(
        id: 'a-cafe-staff',
        email: 'cafe@brewflow.example',
      ),
      shopId: _cafeShop,
    );
    final member = await repository.createStaffProfile(
      identity: _member,
      shopId: _truckShop,
    );
    final resolver = FakeCloudShopResolver(
      deleteStaffResult: cloudDeleteSucceeds,
      staffProfileRoles: {_member.id: 'STAFF'},
    );
    return (repository, resolver, member);
  }

  test('a Food Truck delete archives only that member', () async {
    final (repository, resolver, member) = await seedOwnerAndTruckStaff();
    final container = containerWith(
      session: _owner,
      repository: repository,
      resolver: resolver,
    );
    await container.read(userProfileProvider.future);

    await container.read(staffDeletionProvider.notifier).delete(member);

    expect(resolver.deletedAuthUserIds, [_member.id]);
    expect(repository.archivedProfileIds, [member.id]);
    expect(
      await repository.staffMembers(shopId: _truckShop),
      isEmpty,
      reason: 'the Food Truck roster must lose the deleted member',
    );
    expect(
      await repository.staffMembers(shopId: _cafeShop),
      hasLength(1),
      reason: 'the Cafe roster must survive a Food Truck delete',
    );
  });

  test('a refused cloud delete leaves the local mirror untouched', () async {
    final (repository, resolver, member) = await seedOwnerAndTruckStaff(
      cloudDeleteSucceeds: false,
    );
    final container = containerWith(
      session: _owner,
      repository: repository,
      resolver: resolver,
    );
    await container.read(userProfileProvider.future);

    await expectLater(
      container.read(staffDeletionProvider.notifier).delete(member),
      throwsA(isA<StaffDeleteCloudFailure>()),
    );

    expect(resolver.deletedAuthUserIds, [_member.id]);
    expect(repository.archivedProfileIds, isEmpty);
    expect(await repository.staffMembers(shopId: _truckShop), hasLength(1));
  });

  test('a local OWNER target is refused before any cloud call', () async {
    final repository = FakeStaffRepository();
    final ownerProfile = await repository.claimOwnership(_owner);
    final resolver = FakeCloudShopResolver(
      staffProfileRoles: {_owner.id: 'OWNER'},
    );
    final container = containerWith(
      session: _owner,
      repository: repository,
      resolver: resolver,
    );
    await container.read(userProfileProvider.future);

    await expectLater(
      container.read(staffDeletionProvider.notifier).delete(ownerProfile),
      throwsA(
        isA<StaffDeleteCloudFailure>().having(
          (failure) => failure.message,
          'message',
          'Owners cannot be removed as staff members.',
        ),
      ),
    );

    expect(resolver.deletedAuthUserIds, isEmpty);
    expect(repository.archivedProfileIds, isEmpty);
  });

  test(
    'a cloud OWNER target is refused without touching local state',
    () async {
      final (repository, resolver, member) = await seedOwnerAndTruckStaff();
      resolver.staffProfileRoles[_member.id] = 'OWNER';
      final container = containerWith(
        session: _owner,
        repository: repository,
        resolver: resolver,
      );
      await container.read(userProfileProvider.future);

      await expectLater(
        container.read(staffDeletionProvider.notifier).delete(member),
        throwsA(isA<StaffDeleteCloudFailure>()),
      );

      expect(resolver.deletedAuthUserIds, [_member.id]);
      expect(repository.archivedProfileIds, isEmpty);
      expect(await repository.staffMembers(shopId: _truckShop), hasLength(1));
    },
  );

  test('a non-owner session never reaches the cloud', () async {
    final repository = FakeStaffRepository();
    await repository.claimOwnership(_owner);
    await repository.claimOwnershipForCloud(
      _member,
      shopId: _truckShop,
      role: UserRole.staff,
    );
    final member = (await repository.staffMembers(shopId: _truckShop)).single;
    final resolver = FakeCloudShopResolver(
      staffProfileRoles: {_member.id: 'STAFF'},
    );
    final container = containerWith(
      session: _member,
      repository: repository,
      resolver: resolver,
    );
    await container.read(userProfileProvider.future);

    await expectLater(
      container.read(staffDeletionProvider.notifier).delete(member),
      throwsA(isA<PermissionDeniedFailure>()),
    );

    expect(resolver.deletedAuthUserIds, isEmpty);
    expect(repository.archivedProfileIds, isEmpty);
  });
}
