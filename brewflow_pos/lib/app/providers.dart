import 'dart:async';

import 'package:brewflow_pos/core/database/app_database.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Central Provider Composition
///
/// Riverpod owns long-lived, instance-based application services:
/// - [appDatabaseProvider]        → single AppDatabase, closed on scope end
/// - [connectivityServiceProvider] → single ConnectivityService, disposed on
///                                    scope end
///
/// Static facades ([AppLog], [AppStorage]) are deliberately NOT re-exposed:
/// they are already initialized during bootstrap and are accessed directly,
/// so providers here would only duplicate their state.
///
/// Rules:
/// - No business, auth or sync providers yet.
/// - Bootstrap initialization (environment → storage → Supabase) is NOT
///   duplicated here; bootstrap runs first, Riverpod takes over ownership of
///   instance services afterwards.
/// ---------------------------------------------------------------------------

/// Owns the single [AppDatabase] instance for the application scope.
///
/// The connection is lazy (opened on first use) and closed exactly once when
/// the scope is disposed. Tests override this provider with an in-memory or
/// fake database.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase.open();
  ref.onDispose(() => database.close());
  return database;
});

/// Owns the single [ConnectivityService] instance for the application scope.
///
/// Monitoring starts eagerly via [ConnectivityService.init]; disposal happens
/// exactly once when the scope is disposed. Tests override this provider with
/// a service wired to in-memory fakes.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService.create();
  ref.onDispose(service.dispose);
  unawaited(
    service.init().catchError((Object e, StackTrace st) {
      AppLog.warning(
        'ConnectivityService: eager init failed (plugin unavailable)',
        tag: 'connectivity',
        error: e,
        stackTrace: st,
      );
    }),
  );
  return service;
});
