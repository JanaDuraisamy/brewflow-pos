import 'package:brewflow_pos/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'fake_connectivity_service.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shared Test Provider Overrides
///
/// Centralises the provider overrides that every widget test needs to avoid
/// hitting real platform plugins.
/// ---------------------------------------------------------------------------

/// Returns a list with the standard connectivity fake override.
///
/// Use when building a [ProviderContainer] for tests that render [AppShell]
/// or any widget reading [syncStatusProvider].
///
/// ```dart
/// ProviderContainer(overrides: [...connectivityOverrides()]);
/// ```
List<dynamic> connectivityOverrides() => [
  connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
];
