import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:brewflow_pos/features/inventory/presentation/effective_stock.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock alerts provider (notification center source)
///
/// Single source for the bell badge, the in-app alert panel and the Android
/// notifier: the same scoped product list the inventory list uses (Cafe owns
/// its shelf, Food Truck sells from its projected overlay, All aggregates
/// both shops), judged by the same effective-threshold rules via
/// [buildStockAlerts]. No second stock engine.
///
/// Shop isolation comes from [businessSwitcherProvider.shopIdsForRead]: staff
/// only ever see their assigned shop; the owner All view aggregates both
/// shops with each alert carrying its shop.
/// ---------------------------------------------------------------------------

final stockAlertsProvider =
    AsyncNotifierProvider<StockAlertsController, List<StockAlert>>(
      StockAlertsController.new,
    );

final class StockAlertsController extends AsyncNotifier<List<StockAlert>> {
  @override
  Future<List<StockAlert>> build() async {
    final repository = ref.watch(inventoryRepositoryProvider);
    final business = ref.watch(businessSwitcherProvider);
    final switcher = ref.read(businessSwitcherProvider.notifier);

    var globalThreshold = ShopSettings.defaultLowStockThreshold;
    try {
      globalThreshold =
          (await ref.read(settingsRepositoryProvider).load()).lowStockThreshold;
    } on Object {
      // Fall back to the built-in default; alerts stay available offline.
    }

    if (business == BusinessContext.foodTruck) {
      final ftId = await switcher.existingFoodTruckShopId();
      if (ftId == null) return const [];
      final items = await repository.productsForBusiness(
        shopId: ftId,
        catalogOwnerShopId: await switcher.shopIdFor(BusinessContext.cafe),
        status: ProductStatusFilter.all,
      );
      final projected = await applyEffectiveStock(
        products: items,
        repository: ref.read(shopProductStockRepositoryProvider),
        shopId: ftId,
      );
      return buildStockAlerts(projected, globalThreshold, shopOverride: ftId);
    }

    final items = await repository.products(
      status: ProductStatusFilter.all,
      shopIds: await switcher.shopIdsForRead(business),
    );
    return buildStockAlerts(items, globalThreshold);
  }
}
