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
import 'package:brewflow_pos/features/staff/presentation/payroll_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';

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
  // Form lookups (purchase receiving) — refresh on sync so newly added or
  // pulled products/suppliers appear without an app restart.
  safeInvalidate(purchaseProductsProvider);
  safeInvalidate(activeSuppliersProvider);
  // Derived / secondary providers that also cache derived totals.
  safeInvalidate(shopPayableProvider);
  // Staff payroll + roster. Attendance, advances and salary are pulled cloud-
  // first, but the payroll page caches the assembled summary, so without this
  // a second device kept rendering whatever its first build returned and
  // never showed a change made on another device. Invalidating the family
  // drops every member's cached summary, and the roster refreshes so a member
  // hired on another device becomes selectable.
  safeInvalidate(payrollSummaryProvider);
  safeInvalidate(staffRosterProvider);
}
