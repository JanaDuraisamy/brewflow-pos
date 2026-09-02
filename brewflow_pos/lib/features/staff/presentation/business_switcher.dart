import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:brewflow_pos/core/storage/app_storage.dart';
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
  static const String _foodTruckShopIdKey = 'business_food_truck_shop_id';

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
      if (next != null && next != state) state = next;
    } catch (_) {}
  }

  Future<void> select(BusinessContext next) async {
    state = next;
    await AppStorage.preferences.writeString(_prefsKey, next.name);
  }

  /// Resolves the `shopId` for [context]. CAFE reuses the existing single
  /// shop row; FOOD TRUCK lazily creates a second shop row (second business)
  /// and persists its id. ALL is read-only and must never be used as a write
  /// target — use [requireWritableShopId] for writes.
  Future<String> shopIdFor(BusinessContext context) async {
    if (context == BusinessContext.all) {
      throw StateError('BusinessContext.all is not a writable target');
    }
    final repo = ref.read(staffRepositoryProvider);
    final cafeShop = await repo.ensureShop();
    if (context == BusinessContext.cafe) {
      return cafeShop.id;
    }
    final stored = await AppStorage.preferences.readString(_foodTruckShopIdKey);
    if (stored != null && stored.isNotEmpty) {
      final existing = await repo.ensureShopWithId(stored);
      return existing.id;
    }
    final created = await repo.ensureShopWithId(_newId(), name: 'Food Truck');
    await AppStorage.preferences.writeString(_foodTruckShopIdKey, created.id);
    return created.id;
  }

  /// Shop ids for reads. All returns both (Cafe + Food Truck if it exists).
  Future<List<String>> shopIdsForRead(BusinessContext context) async {
    final cafeId = await shopIdFor(BusinessContext.cafe);
    if (context == BusinessContext.cafe) return [cafeId];
    if (context == BusinessContext.foodTruck) {
      final ftId = await shopIdFor(BusinessContext.foodTruck);
      return [ftId];
    }
    // All
    try {
      final ftId = await shopIdFor(BusinessContext.foodTruck);
      // Food Truck shop was lazily created above; if it was just created it
      // will be empty. Include it for completeness.
      if (ftId != cafeId) return [cafeId, ftId];
    } catch (_) {}
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
