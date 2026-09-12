import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/database/shop_resolver.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/preferences_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart'
    show AuthUser;
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_connectivity_service.dart';

/// ---------------------------------------------------------------------------
/// Shop-ID divergence regression tests.
///
/// On the failing device the local `shops` table's FIRST row was a stale
/// legacy shop (`4c794b74-...`, an auto-created orphan with no cloud
/// identity) while the OWNER profile's authoritative shop was
/// `85437772-...` ("My Shop"). Two resolution points selected `existing.first`
/// / `rows.first`:
///   - `BusinessSwitcherController.shopIdFor(cafe)`
///   - `resolveWritableShopId(database, null)` — billing, inventory, etc.
///
/// These tests prove writes never land on the orphan, and that Food Truck
/// stays fully isolated (reads never mint new shop ids).
/// ---------------------------------------------------------------------------

const String kOrphanShop = '4c794b74-1d7e-495b-a3da-f22585afd4fb';
const String kAuthoritativeShop = '85437772-a082-44b9-824e-69562356928e';
const String kAuthUserId = 'owner-1';
const String kEmail = 'owner@shop.co';

/// In-memory [PreferencesStorage]; shares the raw key the controller uses.
final class InMemoryPreferences implements PreferencesStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> readString(String key) async => values[key];

  @override
  Future<bool> writeString(String key, String value) async {
    values[key] = value;
    return true;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      defaultValue;

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async => defaultValue;

  @override
  Future<double> readDouble(String key, {double defaultValue = 0}) async =>
      defaultValue;

  @override
  Future<List<String>> readStringList(String key) async => const [];

  @override
  Future<bool> writeBool(String key, bool value) async => true;

  @override
  Future<bool> writeInt(String key, int value) async => true;

  @override
  Future<bool> writeDouble(String key, double value) async => true;

  @override
  Future<bool> writeStringList(String key, List<String> value) async => true;

  @override
  Future<bool> contains(String key) async => values.containsKey(key);

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;

  @override
  Future<void> clearAppData() async => values.clear();
}

/// In-memory [SecureStorage]; SecureStorage is never exercised here but
/// [AppStorage.init] stores the implementation, so a double is required to
/// keep platform channels out of unit tests.
final class InMemorySecure implements SecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      defaultValue;

  @override
  Future<void> writeBool(String key, bool value) async {}

  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async => defaultValue;

  @override
  Future<void> writeInt(String key, int value) async {}

  @override
  Future<bool> contains(String key) async => values.containsKey(key);

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<void> clear() async => values.clear();
}

void main() {
  final prefs = InMemoryPreferences();
  late AppDatabase db;

  setUpAll(() async {
    await AppStorage.init(secure: InMemorySecure(), preferences: prefs);
  });

  setUp(() async {
    prefs.values.clear();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// Seeds the failing-device precondition: a stale orphan shop row created
  /// before the real shop existed (so it is FIRST in the `shops` table),
  /// followed by the authoritative shop the OWNER profile is bound to.
  Future<void> seedDivergedShops() async {
    await db
        .into(db.shops)
        .insert(ShopsCompanion.insert(id: Value(kOrphanShop), name: 'Cafe'));
    await db
        .into(db.shops)
        .insert(
          ShopsCompanion.insert(id: Value(kAuthoritativeShop), name: 'My Shop'),
        );
  }

  Future<void> seedShop(String id, String name) => db
      .into(db.shops)
      .insert(ShopsCompanion.insert(id: Value(id), name: name));

  Future<void> seedOwner({String shopId = kAuthoritativeShop}) => db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          email: kEmail,
          authUserId: Value(kAuthUserId),
          shopId: Value(shopId),
          role: const Value('OWNER'),
        ),
      );

  Future<void> seedProduct({required String id, String? shopId}) async {
    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(id: Value('cat-$id'), name: 'Cat $id'),
        );
    await db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(
            id: Value(id),
            shopId: Value(shopId),
            categoryId: 'cat-$id',
            name: 'Product $id',
            sellingPricePaise: 12000,
            stockQuantity: const Value(10),
          ),
        );
  }

  FakeAuthRepository ownerAuth() => FakeAuthRepository(
    user: const AuthUser(id: kAuthUserId, email: kEmail),
  );

  ProviderContainer containerWith(FakeAuthRepository auth) {
    final resolver = FakeCloudShopResolver(
      profile: CloudUserProfile(
        shopId: kAuthoritativeShop,
        shopName: 'My Shop',
        email: kEmail,
        role: 'OWNER',
        isActive: true,
      ),
    );
    return ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        authRepositoryProvider.overrideWithValue(auth),
        connectivityServiceProvider.overrideWithValue(
          fakeConnectivityService(),
        ),
        cloudShopResolverProvider.overrideWithValue(resolver),
      ],
    );
  }

  group('resolveWritableShopId — authoritative Cafe shop', () {
    test('orphan first row never becomes the Cafe write shop', () async {
      await seedDivergedShops();
      await seedOwner();

      expect(await resolveWritableShopId(db), kAuthoritativeShop);
    });

    test(
      'unprovisioned database keeps legacy single-shop resolution',
      () async {
        await seedShop('shop-legacy', 'Cafe');

        expect(await resolveWritableShopId(db), 'shop-legacy');
      },
    );

    test('empty database still auto-creates the legacy Cafe shop', () async {
      final id = await resolveWritableShopId(db);

      final rows = await db.select(db.shops).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, id);
      expect(rows.single.name, 'Cafe');
    });
  });

  group('billing writes under the authoritative Cafe shop', () {
    test(
      'completeSale without a shop id lands on the authoritative shop',
      () async {
        await seedDivergedShops();
        await seedOwner();
        await seedProduct(id: 'prod-1', shopId: kAuthoritativeShop);
        final repository = DriftBillingRepository(db);

        final completed = await repository.completeSale(
          lines: [
            CartLine(
              productId: 'prod-1',
              productName: 'Coffee',
              unitPricePaise: 12000,
              quantity: 1,
              maxQuantity: 99,
            ),
          ],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
        );

        expect(completed.sale.id, isNotEmpty);
        final rows = await db.select(db.sales).get();
        expect(rows, hasLength(1));
        expect(rows.single.shopId, kAuthoritativeShop);
      },
    );
  });

  group('Cafe shop resolution via business switcher', () {
    test(
      'shopIdFor(cafe) resolves the profile-bound authoritative shop',
      () async {
        await seedDivergedShops();
        await seedOwner();
        final container = containerWith(ownerAuth());
        addTearDown(container.dispose);

        final profile = await container.read(userProfileProvider.future);
        expect(profile?.shopId, kAuthoritativeShop);

        final cafeId = await container
            .read(businessSwitcherProvider.notifier)
            .shopIdFor(BusinessContext.cafe);
        expect(cafeId, kAuthoritativeShop);
      },
    );

    test(
      'without a resolved profile the legacy first-row fallback applies',
      () async {
        await seedDivergedShops();
        final container = containerWith(FakeAuthRepository());
        addTearDown(container.dispose);

        expect(await container.read(userProfileProvider.future), isNull);

        final cafeId = await container
            .read(businessSwitcherProvider.notifier)
            .shopIdFor(BusinessContext.cafe);
        expect(cafeId, kOrphanShop);
      },
    );

    test(
      'staff provisioning receives the authoritative Cafe shop id',
      () async {
        await seedDivergedShops();
        await seedOwner();
        final container = containerWith(ownerAuth());
        addTearDown(container.dispose);

        await container.read(userProfileProvider.future);
        final repo = container.read(staffRepositoryProvider);
        final cafeId = await container
            .read(businessSwitcherProvider.notifier)
            .shopIdFor(BusinessContext.cafe);

        await repo.createStaffProfile(
          identity: const AuthUser(id: 'staff-1', email: 'staff@shop.co'),
          shopId: cafeId,
        );

        final staff = await repo.staffMembers();
        expect(staff, hasLength(1));
        expect(staff.single.shopId, kAuthoritativeShop);
      },
    );
  });

  group('Food Truck isolation', () {
    test('read paths never mint a Food Truck shop', () async {
      await seedDivergedShops();
      await seedOwner();
      final container = containerWith(ownerAuth());
      addTearDown(container.dispose);
      await container.read(userProfileProvider.future);

      final switcher = container.read(businessSwitcherProvider.notifier);
      expect(await switcher.existingFoodTruckShopId(), isNull);
      expect(await switcher.shopIdsForRead(BusinessContext.foodTruck), isEmpty);
      expect(await switcher.shopIdsForRead(BusinessContext.all), [
        kAuthoritativeShop,
      ]);

      final shops = await db.select(db.shops).get();
      expect(
        shops,
        hasLength(2),
        reason: 'reads must not insert a Food Truck row',
      );
    });

    test(
      'Food Truck id is created on the explicit write path, then reused',
      () async {
        await seedDivergedShops();
        await seedOwner();
        final container = containerWith(ownerAuth());
        addTearDown(container.dispose);
        await container.read(userProfileProvider.future);

        final switcher = container.read(businessSwitcherProvider.notifier);
        final ftId = await switcher.shopIdFor(BusinessContext.foodTruck);
        expect(ftId, isNotEmpty);

        expect(await switcher.existingFoodTruckShopId(), ftId);
        expect(
          await switcher.shopIdFor(BusinessContext.foodTruck),
          ftId,
          reason: 'repeated resolution reuses the persisted id, no new row',
        );
        expect(await switcher.shopIdsForRead(BusinessContext.foodTruck), [
          ftId,
        ]);
        expect(await switcher.shopIdsForRead(BusinessContext.all), [
          kAuthoritativeShop,
          ftId,
        ]);

        final shops = await db.select(db.shops).get();
        expect(shops, hasLength(3));
      },
    );

    test(
      'pre-existing Food Truck id is honored by reads without re-creation',
      () async {
        await seedDivergedShops();
        await seedOwner();
        await seedShop('ft-1', 'Food Truck');
        await prefs.writeString(
          BusinessSwitcherController.foodTruckShopIdKey,
          'ft-1',
        );
        final container = containerWith(ownerAuth());
        addTearDown(container.dispose);
        await container.read(userProfileProvider.future);

        final switcher = container.read(businessSwitcherProvider.notifier);
        expect(await switcher.shopIdsForRead(BusinessContext.foodTruck), [
          'ft-1',
        ]);
        expect(await switcher.shopIdsForRead(BusinessContext.all), [
          kAuthoritativeShop,
          'ft-1',
        ]);

        final shops = await db.select(db.shops).get();
        expect(shops, hasLength(3));
      },
    );
  });
}
