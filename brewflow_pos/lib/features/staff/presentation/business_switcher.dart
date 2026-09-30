import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/features/staff/domain/staff_repository.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Business Switcher (Owner multi-business)
///
/// One Owner controls two operating units: CAFE and FOOD TRUCK. Tablets are
/// single-business (their local `shops` row is authoritative), while the
/// Owner Phone can switch context. The active business determines which
/// `shop_id` new staff/offers/sales are created under. Existing data is
/// single-shop: that row is treated as CAFE for backward compatibility.
///
/// Persistence: selected business + lazily-created Food Truck shopId are
/// stored in SharedPreferences (namespaced `brewflow_`). No migration of
/// applied migrations; forward-only.
/// ---------------------------------------------------------------------------

enum BusinessContext { cafe, foodTruck, all }

extension BusinessContextLabel on BusinessContext {
  String get label => switch (this) {
    BusinessContext.cafe => 'Cafe',
    BusinessContext.foodTruck => 'Food Truck',
    BusinessContext.all => 'All Businesses',
  };
}

final businessSwitcherProvider =
    NotifierProvider<BusinessSwitcherController, BusinessContext>(
      BusinessSwitcherController.new,
    );

final class BusinessSwitcherController extends Notifier<BusinessContext> {
  static const String _prefsKey = 'business_switcher_context';

  /// SharedPreferences key holding the lazily-created Food Truck shop id.
  /// Also read by the sync session so a device that created the second
  /// business can push its cloud identity + OWNER membership.
  static const String foodTruckShopIdKey = 'business_food_truck_shop_id';

  /// The name this controller writes when it creates the second business, and
  /// the name [ _recoverFoodTruckShopId ] matches on to recognise a Food Truck
  /// that already exists in the cloud.
  static const String _foodTruckShopName = 'food truck';

  /// Whether the user has explicitly chosen a context in this session. Guards
  /// the async prefs hydration so a late prefs read can never revert an
  /// explicit Cafe ↔ Food Truck ↔ Combined selection (the QA "switch does
  /// nothing" race: build returns Cafe, hydration lands Food Truck after the
  /// tap, and the UI appears stuck).
  bool _userSelected = false;

  @override
  BusinessContext build() {
    // Default to Cafe for backward compatibility; hydrate from prefs async.
    unawaited(_hydrate());
    return BusinessContext.cafe;
  }

  Future<void> _hydrate() async {
    try {
      final raw = await AppStorage.preferences.readString(_prefsKey);
      final next = BusinessContext.values.asNameMap()[raw ?? ''];
      if (next == null || next == state || _userSelected) return;
      state = next;
      AppTrace.event('shop.hydrate', {
        'to': next.name,
        'from': BusinessContext.cafe.name,
      });
      AppLog.info('Business context hydrated: ${next.name}', tag: 'Shop');
    } catch (error, stackTrace) {
      AppTrace.warn('shop.hydrate_fail', {'kept': BusinessContext.cafe.name});
      AppLog.warning(
        'Business context hydration failed (keeping Cafe)',
        tag: 'Shop',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> select(BusinessContext next) async {
    _userSelected = true;
    if (next == state) {
      // Still persist + log so a tap on the active entry is observable in
      // logcat (QA reported "no Flutter log") instead of a silent no-op.
      try {
        await AppStorage.preferences.writeString(_prefsKey, next.name);
      } catch (error, stackTrace) {
        AppLog.warning(
          'Business context persist failed',
          tag: 'Shop',
          error: error,
          stackTrace: stackTrace,
        );
      }
      AppTrace.event('shop.select', {
        'to': next.name,
        'from': state.name,
        'changed': false,
      });
      AppLog.info(
        'Business context selected (unchanged): ${next.name}',
        tag: 'Shop',
      );
      return;
    }
    final previous = state;
    state = next;
    AppTrace.event('shop.select', {
      'to': next.name,
      'from': previous.name,
      'changed': true,
      'readOnly': next == BusinessContext.all,
    });
    try {
      await AppStorage.preferences.writeString(_prefsKey, next.name);
    } catch (error, stackTrace) {
      AppTrace.warn('shop.persist_fail', {'to': next.name});
      AppLog.warning(
        'Business context persist failed',
        tag: 'Shop',
        error: error,
        stackTrace: stackTrace,
      );
    }
    AppLog.info('Business context selected: ${next.name}', tag: 'Shop');
    // Watchers (dashboard, reports, POS shelf/offers) rebuild via the
    // provider subscription; no manual invalidation here so Combined
    // read-only semantics stay untouched.
  }

  /// Resolves the `shopId` for [context].
  ///
  /// CAFE resolves to the shop bound to the locally provisioned profile
  /// (the authoritative shop the sync identity pushes and mints memberships
  /// for), falling back to the existing single shop row when no profile is
  /// resolved yet. This prevents a stale legacy `shops` row — an auto-created
  /// orphan left over from an earlier single-shop boot — from becoming the
  /// Cafe write target.
  ///
  /// FOOD TRUCK resolves the persisted id, then RECOVERS the real id from the
  /// cloud, and only mints a new business as a last resort — see
  /// [_recoverFoodTruckShop] for why the recovery step must come first.
  /// ALL is read-only and must never be used as a write target — use
  /// [requireWritableShopId] for writes.
  Future<String> shopIdFor(BusinessContext context) async {
    if (context == BusinessContext.all) {
      throw StateError('BusinessContext.all is not a writable target');
    }
    final repo = ref.read(staffRepositoryProvider);
    if (context == BusinessContext.cafe) {
      return _cafeShopId(repo);
    }
    final stored = await AppStorage.preferences.readString(foodTruckShopIdKey);
    if (stored != null && stored.isNotEmpty) {
      final existing = await repo.ensureShopWithId(stored);
      AppTrace.event('shop.resolve', {
        'context': context.name,
        'source': 'persisted',
        'shopRef': AppTrace.userRef(existing.id),
      });
      return existing.id;
    }
    // No persisted id: the app data was cleared (or this is a second device
    // that has never seen the second business). Ask the cloud for the real one
    // BEFORE creating anything, or a second, empty "Food Truck" is minted and
    // the genuine business becomes unreachable.
    final recovered = await _recoverFoodTruckShop();
    if (recovered != null) {
      try {
        await AppStorage.preferences.writeString(
          foodTruckShopIdKey,
          recovered.id,
        );
      } catch (error, stackTrace) {
        AppLog.warning(
          'Food Truck shop id recovered but not persisted (will re-recover)',
          tag: 'Shop',
          error: error,
          stackTrace: stackTrace,
        );
      }
      AppLog.info(
        'Food Truck shop id recovered from cloud: ${recovered.id}',
        tag: 'Shop',
      );
      AppTrace.event('shop.resolve', {
        'context': context.name,
        'source': 'recovered',
        'shopRef': AppTrace.userRef(recovered.id),
      });
      // Materialise the local row under the recovered id so writes, staff and
      // products attach to the real business.
      final shop = await repo.ensureShopWithId(
        recovered.id,
        name: recovered.name,
      );
      return shop.id;
    }
    final created = await repo.ensureShopWithId(_newId(), name: 'Food Truck');
    await AppStorage.preferences.writeString(foodTruckShopIdKey, created.id);
    AppTrace.warn('shop.resolve', {
      'context': context.name,
      'source': 'created',
      'shopRef': AppTrace.userRef(created.id),
    });
    return created.id;
  }

  /// Resolves the real Food Truck shop identity from the caller's cloud
  /// memberships, without touching the local database.
  ///
  /// Returns null when there is nothing to recover — no cloud client, an empty
  /// membership list, or the only membership is the Cafe — leaving the caller
  /// to create a genuinely new second business.
  ///
  /// The Cafe is excluded by id rather than by name so a business literally
  /// named "Cafe" cannot be mistaken for the truck, and vice versa. When
  /// several non-Cafe memberships exist, the one named "Food Truck" wins,
  /// because that is the name this controller itself writes on creation; the
  /// remaining case (an owner running more than two units) falls back to the
  /// first, which matches the single-truck assumption the rest of the app makes.
  ///
  /// Deliberately does not create a local `shops` row: the read path
  /// ([existingFoodTruckShopId]) needs the id to scope queries, and a read must
  /// never insert as a side effect.
  Future<({String id, String name})?> _recoverFoodTruckShop() async {
    try {
      final managed = await ref
          .read(cloudShopResolverProvider)
          .listManagedShops();
      if (managed.isEmpty) return null;

      final cafeId = await _cafeShopId(ref.read(staffRepositoryProvider));
      final candidates = managed
          .where((shop) => shop.isActive && shop.shopId != cafeId)
          .toList();
      if (candidates.isEmpty) return null;

      final named = candidates.where(
        (shop) => shop.shopName.toLowerCase() == _foodTruckShopName,
      );
      final chosen = named.isNotEmpty ? named.first : candidates.first;
      return (id: chosen.shopId, name: chosen.shopName);
    } catch (error, stackTrace) {
      AppTrace.warn('shop.recover_fail', {'context': 'foodTruck'});
      AppLog.warning(
        'Food Truck shop recovery failed (falling back to create)',
        tag: 'Shop',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<String> _cafeShopId(StaffRepository repo) async {
    // Authoritative shop: the one the signed-in profile is bound to. Reading
    // `.value` is safe — null while loading/error, so fresh single-shop
    // installs and tests without a resolved profile keep the legacy path.
    final profileShopId = ref.read(userProfileProvider).value?.shopId;
    if (profileShopId != null && profileShopId.isNotEmpty) {
      final shop = await repo.ensureShopWithId(profileShopId);
      return shop.id;
    }
    return (await repo.ensureShop()).id;
  }

  /// Food Truck shop id for READ scoping, if there is a real second business.
  ///
  /// Order matters: the persisted id wins, then a cloud recovery, and only
  /// then null. Without the cloud fallback a cleared device reports an empty
  /// Food Truck / All-Businesses view even though the business and all of its
  /// data are intact in the cloud — the reads would be silently wrong rather
  /// than obviously broken.
  ///
  /// Never creates a local row and never mints a new id: a read must not have
  /// write side effects, and a fresh id here would make reads silently miss
  /// every real Food Truck record. Returns null when Storage is unavailable, so
  /// reads fail closed.
  Future<String?> existingFoodTruckShopId() async {
    try {
      final stored = await AppStorage.preferences.readString(
        foodTruckShopIdKey,
      );
      if (stored != null && stored.isNotEmpty) return stored;
    } catch (_) {
      // Storage unavailable: fall through to the cloud, which is a strictly
      // better source than failing closed here.
    }
    return (await _recoverFoodTruckShop())?.id;
  }

  /// Shop ids for reads. All returns both (Cafe + Food Truck if one exists).
  /// Reads must never create Food Truck rows — only a persisted id is used.
  Future<List<String>> shopIdsForRead(BusinessContext context) async {
    final cafeId = await shopIdFor(BusinessContext.cafe);
    if (context == BusinessContext.cafe) return [cafeId];
    if (context == BusinessContext.foodTruck) {
      final ftId = await existingFoodTruckShopId();
      // An empty Food Truck view is indistinguishable from "no data" in the
      // UI, so the reason the scope came back empty is traced explicitly.
      if (ftId == null) {
        AppTrace.warn('shop.read_scope', {
          'context': context.name,
          'shops': 0,
          'reason': 'no_food_truck_identity',
        });
        return <String>[];
      }
      return [ftId];
    }
    // All
    final ftId = await existingFoodTruckShopId();
    if (ftId != null && ftId != cafeId) return [cafeId, ftId];
    return [cafeId];
  }

  /// Active shopId for writes under the current selection.
  /// Throws if current selection is All.
  Future<String> get activeShopId => shopIdFor(state);

  /// Like [activeShopId] but throws StateError when All is selected.
  Future<String> requireWritableShopId() async {
    if (state == BusinessContext.all) {
      throw StateError('All businesses view is read-only');
    }
    return shopIdFor(state);
  }

  String _newId() => const Uuid().v4();
}
