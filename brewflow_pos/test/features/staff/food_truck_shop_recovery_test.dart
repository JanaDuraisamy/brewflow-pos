import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/staff/data/cloud_shop_resolver.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_cloud_shop_resolver.dart';
import '../../helpers/fake_preferences_storage.dart';
import '../../helpers/fake_staff_repository.dart';
import '../../helpers/test_providers.dart';

/// Regression for the clear-data Food Truck identity loss.
///
/// The Food Truck's shop id was only ever persisted in SharedPreferences, so
/// "Clear app data" (or any second device) left the app with no way to find
/// the real business: it minted a brand-new uuid and created an empty phantom
/// "Food Truck", permanently orphaning the genuine shop and everything in it.
///
/// The contract these tests lock in:
///   * a persisted id still wins (no needless cloud round-trip),
///   * with no persisted id, the cloud membership is authoritative and is
///     adopted rather than replaced,
///   * the Cafe membership is never mistaken for the second business,
///   * the read path recovers too (Combined/Food Truck views are not empty),
///   * a read never creates a local row or mints an id,
///   * a cloud outage falls back to creating a genuinely new business.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const cafeId = 'cafe-uuid-0001';
  const truckId = 'truck-uuid-0002';

  // `AppStorage.init` early-returns once initialized, so a per-test instance
  // would be ignored after the first test and leak ids between tests. One
  // instance for the file, cleared per test.
  late FakePreferencesStorage prefs;
  late FakeStaffRepository repo;
  late FakeCloudShopResolver resolver;

  CloudManagedShop membership(
    String id,
    String name, {
    String role = 'OWNER',
    bool isActive = true,
  }) => CloudManagedShop(
    shopId: id,
    shopName: name,
    role: role,
    isActive: isActive,
  );

  /// Container with the switcher's dependencies faked.
  ///
  /// The signed-in owner is pinned to [cafeId], which is what makes the Cafe
  /// identity locally determinable: `shopIdsForRead` fails closed to an empty
  /// scope when it cannot resolve a Cafe, so a read-scoping test has to stand up
  /// the session those reads are scoped by. The Cafe shop row is pre-seeded in
  /// the fake repository for the write paths that materialise it.
  ProviderContainer buildContainer() {
    final container = ProviderContainer(
      overrides: [
        ...businessScopeOverrides(
          staff: repo,
          profile: testOwnerProfile(shopId: cafeId),
        ),
        cloudShopResolverProvider.overrideWithValue(resolver),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUpAll(() async {
    prefs = FakePreferencesStorage();
    await AppStorage.init(secure: _FakeSecure(), preferences: prefs);
  });

  setUp(() async {
    await prefs.clearAppData();
    repo = FakeStaffRepository()..shop = Shop(id: cafeId, name: 'Cafe');
    resolver = FakeCloudShopResolver();
  });

  BusinessSwitcherController switcher(ProviderContainer container) =>
      container.read(businessSwitcherProvider.notifier);

  test('a persisted Food Truck id is used without asking the cloud', () async {
    await prefs.writeString('business_food_truck_shop_id', truckId);
    final container = buildContainer();

    expect(
      await switcher(container).shopIdFor(BusinessContext.foodTruck),
      truckId,
    );
    expect(
      resolver.managedShopQueries,
      0,
      reason: 'a known id must not cost a cloud round-trip',
    );
  });

  test(
    'after clear-data the real Food Truck is adopted, not replaced',
    () async {
      // Prefs are empty — the post-clear-data state.
      resolver.managedShops = [
        membership(cafeId, 'Cafe'),
        membership(truckId, 'Food Truck'),
      ];
      final container = buildContainer();

      // Resolve Cafe first: the switcher's fallback reuses whatever shop row the
      // fake currently holds, and materialising the truck replaces it.
      final cafe = await switcher(container).shopIdFor(BusinessContext.cafe);
      expect(cafe, cafeId);

      final id = await switcher(container).shopIdFor(BusinessContext.foodTruck);

      expect(id, truckId, reason: 'the genuine cloud shop must be adopted');
      expect(id, isNot(cafe));
      expect(
        repo.ensureShopCalls.map((call) => call.id),
        contains(truckId),
        reason: 'a local row must exist under the recovered id',
      );
      expect(
        await prefs.readString('business_food_truck_shop_id'),
        truckId,
        reason:
            'the recovered id must be persisted so later reads skip the cloud',
      );
    },
  );

  test(
    'a second switch reuses the recovered id with no further cloud call',
    () async {
      resolver.managedShops = [
        membership(cafeId, 'Cafe'),
        membership(truckId, 'Food Truck'),
      ];
      final container = buildContainer();
      final notifier = switcher(container);

      expect(await notifier.shopIdFor(BusinessContext.foodTruck), truckId);
      final queriesAfterFirst = resolver.managedShopQueries;

      expect(await notifier.shopIdFor(BusinessContext.foodTruck), truckId);
      expect(
        resolver.managedShopQueries,
        queriesAfterFirst,
        reason: 'the recovered id is persisted, so no second lookup is needed',
      );
    },
  );

  test('the Cafe membership is never adopted as the second business', () async {
    // Owner only has the Cafe: there is nothing to recover, so a new business
    // is created — but it must not be the Cafe's own id.
    resolver.managedShops = [membership(cafeId, 'Cafe')];
    final container = buildContainer();

    final id = await switcher(container).shopIdFor(BusinessContext.foodTruck);

    expect(id, isNot(cafeId));
  });

  test('an inactive membership is ignored', () async {
    resolver.managedShops = [
      membership(cafeId, 'Cafe'),
      membership(truckId, 'Food Truck', isActive: false),
    ];
    final container = buildContainer();

    final id = await switcher(container).shopIdFor(BusinessContext.foodTruck);

    expect(
      id,
      isNot(truckId),
      reason: 'a deactivated business is not recovered',
    );
  });

  test(
    'a business named Food Truck wins over other second businesses',
    () async {
      resolver.managedShops = [
        membership(cafeId, 'Cafe'),
        membership('other-uuid', 'Popup Bar'),
        membership(truckId, 'Food Truck'),
      ];
      final container = buildContainer();

      expect(
        await switcher(container).shopIdFor(BusinessContext.foodTruck),
        truckId,
      );
    },
  );

  group('read scoping', () {
    test(
      'recovers the id so Food Truck reads are not empty after clear-data',
      () async {
        resolver.managedShops = [
          membership(cafeId, 'Cafe'),
          membership(truckId, 'Food Truck'),
        ];
        final container = buildContainer();
        final notifier = switcher(container);

        expect(await notifier.existingFoodTruckShopId(), truckId);
        expect(await notifier.shopIdsForRead(BusinessContext.foodTruck), [
          truckId,
        ]);
        expect(
          await notifier.shopIdsForRead(BusinessContext.all),
          [cafeId, truckId],
          reason: 'Combined must span both real businesses',
        );
      },
    );

    test('never creates a local row or mints an id', () async {
      resolver.managedShops = [
        membership(cafeId, 'Cafe'),
        membership(truckId, 'Food Truck'),
      ];
      final container = buildContainer();
      final notifier = switcher(container);

      await notifier.existingFoodTruckShopId();

      expect(
        repo.ensureShopCalls.where((call) => call.id == truckId),
        isEmpty,
        reason: 'a read must not insert as a side effect',
      );
    });

    test('returns null when there is no second business at all', () async {
      resolver.managedShops = [membership(cafeId, 'Cafe')];
      final container = buildContainer();
      final notifier = switcher(container);

      expect(await notifier.existingFoodTruckShopId(), isNull);
      expect(await notifier.shopIdsForRead(BusinessContext.all), [cafeId]);
    });
  });

  test('a cloud outage falls back to creating a new business', () async {
    resolver.managedShopsThrows = true;
    final container = buildContainer();

    final id = await switcher(container).shopIdFor(BusinessContext.foodTruck);

    expect(id, isNotEmpty);
    expect(id, isNot(cafeId));
    expect(
      await prefs.readString('business_food_truck_shop_id'),
      id,
      reason: 'the newly created business must be persisted for later reads',
    );
  });
}

final class _FakeSecure implements SecureStorage {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
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
  Future<bool> contains(String key) async => _values.containsKey(key);
  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async => _values.clear();
}
