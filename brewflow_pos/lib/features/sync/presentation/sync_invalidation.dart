import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';

/// Invalidates every domain provider that caches shop data locally.
/// Called after a successful sync pull so that running screens refresh
/// without requiring an app restart. Mirrors the backup restore pattern
/// and keeps the sync engine as the single sync mechanism.
///
/// Best-effort: each invalidate is guarded so a not-yet-initialized
/// provider in a test scope never breaks the sync cycle.
void invalidateDomainProviders(Ref ref) {
  void safeInvalidate(dynamic provider) {
    try {
      ref.invalidate(provider);
    } catch (_) {}
  }

  safeInvalidate(categoriesProvider);
  safeInvalidate(productsProvider);
  safeInvalidate(customersProvider);
  safeInvalidate(suppliersProvider);
  safeInvalidate(purchasesProvider);
  safeInvalidate(expensesProvider);
  safeInvalidate(ordersListProvider);
  safeInvalidate(posProductsProvider);
  safeInvalidate(posCustomersProvider);
  safeInvalidate(dashboardControllerProvider);
  safeInvalidate(reportsControllerProvider);
  safeInvalidate(shopSettingsProvider);
  safeInvalidate(offersProvider);
  // Derived / secondary providers that also cache derived totals.
  safeInvalidate(shopPayableProvider);
}
