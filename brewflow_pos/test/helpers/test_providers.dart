import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_connectivity_service.dart';
import 'fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Test Provider Overrides
///
/// Centralises the provider overrides that every widget test needs to avoid
/// hitting real platform plugins.
/// ---------------------------------------------------------------------------

/// Returns a list with the standard connectivity fake override.
///
/// Use when building a [ProviderContainer] for tests that render [AppShell]
/// or any widget reading `syncStatusProvider`.
///
/// ```dart
/// ProviderContainer(overrides: [...connectivityOverrides()]);
/// ```
List<dynamic> connectivityOverrides() => [
  connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
];

/// Overrides that let business-scoped controllers resolve a shop id without
/// touching the real database or SharedPreferences.
///
/// Controllers such as [ProductsController] ask [BusinessSwitcherController]
/// which shop they are reading/writing. That resolution ends in
/// `StaffRepository.ensureShop`, so any test whose container only fakes the
/// feature repository would otherwise open the real Drift database and fail
/// with an async teardown race.
///
/// Add this to every container that exercises a shop-scoped controller:
///
/// ```dart
/// ProviderContainer(overrides: [
///   inventoryRepositoryProvider.overrideWithValue(fake),
///   ...businessScopeOverrides(),
/// ]);
/// ```
List<dynamic> businessScopeOverrides([FakeStaffRepository? staff]) => [
  staffRepositoryProvider.overrideWithValue(staff ?? FakeStaffRepository()),
];
