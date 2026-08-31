import 'package:brewflow_pos/config/env.dart';
import 'package:brewflow_pos/config/flavor.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Application Bootstrap
///
/// Centralized, ordered application initialization:
///
///   Flutter binding
///     ↓
///   Environment configuration (AppEnv)
///     ↓
///   Application logger (AppLog — used from here on)
///     ↓
///   Local storage (AppStorage — secure + preferences)
///     ↓
///   Supabase client (env-driven, never hardcoded)
///     ↓
///   Application UI
///
/// Rules:
/// - Initialization is explicit and sequential; each step is a small,
///   focused function so future Riverpod providers can take ownership of
///   long-lived services without rewriting this flow.
/// - Any failure aborts startup and is rethrown (never swallowed) after
///   being logged without exposing credentials.
/// - Nothing is initialized twice: [AppEnv.load] and [AppStorage.init] are
///   idempotent, and [Supabase.initialize] skips re-initialization itself.
///
/// Riverpod, routing, authentication, connectivity, sync and features are
/// intentionally NOT initialized here yet.
/// ---------------------------------------------------------------------------

const String _tag = 'Bootstrap';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await _initEnvironment();
    await _initLocalStorage();
    await _initSupabase();

    runApp(const BrewFlowApp());
  } catch (error, stackTrace) {
    AppLog.error(
      'Bootstrap failed. Application cannot start.',
      tag: _tag,
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

/// Loads the environment before anything that depends on it.
Future<void> _initEnvironment() async {
  await AppEnv.load();
  AppLog.info(
    'Environment loaded (flavor: ${AppFlavor.current.name}, '
    'env file: ${AppEnv.envFileName})',
    tag: _tag,
  );
}

/// Initializes local storage (secure storage + shared preferences).
Future<void> _initLocalStorage() async {
  await AppStorage.init();
  AppLog.info('Local storage initialized', tag: _tag);
}

/// Initializes the Supabase client from environment values.
Future<void> _initSupabase() async {
  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    publishableKey: AppEnv.supabaseAnonKey,
    // Silence the SDK's own debug output in production builds.
    debug: AppFlavor.current.isDevelopment,
  );
  AppLog.info('Supabase client initialized', tag: _tag);
}
