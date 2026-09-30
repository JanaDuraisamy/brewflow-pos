import 'package:brewflow_pos/config/env.dart';
import 'package:brewflow_pos/config/flavor.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/services/app_trace.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:flutter/services.dart';
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
///   System UI policy (edge-to-edge)
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
///   being logged without exposing credentials. The single exception is
///   [_initSystemUi], which is window policy rather than a dependency: see
///   that function for why it degrades instead of aborting.
/// - Nothing is initialized twice: [AppEnv.load] and [AppStorage.init] are
///   idempotent, and [Supabase.initialize] skips re-initialization itself.
///
/// Riverpod, routing, authentication, connectivity, sync and features are
/// intentionally NOT initialized here yet.
/// ---------------------------------------------------------------------------

const String _tag = 'Bootstrap';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final bootStopwatch = Stopwatch()..start();

  try {
    await _initSystemUi();
    await _initEnvironment();
    await _initLocalStorage();
    await _initSupabase();

    AppTrace.event('app.start', {
      'flavor': AppFlavor.current.name,
      'env': AppEnv.envFileName,
      'bootMs': bootStopwatch.elapsedMilliseconds,
    });
    runApp(const BrewFlowApp());
  } catch (error, stackTrace) {
    AppTrace.fail('app.bootstrap_fail', error, stackTrace, {
      'elapsedMs': bootStopwatch.elapsedMilliseconds,
    });
    AppLog.error(
      'Bootstrap failed. Application cannot start.',
      tag: _tag,
      error: error,
      stackTrace: stackTrace,
    );
    rethrow;
  }
}

/// Declares the window's system-UI policy once, before any UI is built.
///
/// This app targets API 36 (`flutter.targetSdkVersion`), which makes
/// edge-to-edge a platform requirement rather than a preference:
///
/// - **Android 14 (API 34)** — still opt-in. Without this call the window is
///   letterboxed and the system bars get opaque platform backgrounds.
/// - **Android 15 (API 35)** — enforced for any app targeting API 35+.
///   `windowOptOutEdgeToEdgeEnforcement` exists but is a temporary escape hatch.
/// - **Android 16 (API 36)** — the opt-out attribute is removed entirely.
///   There is no supported way back.
///
/// Asking for [SystemUiMode.edgeToEdge] explicitly is what makes all three
/// behave the same, and it is the only configuration that stays valid on 16.
/// Deliberately *not* used here, because each one either fights the framework
/// or is already dead:
///
/// - `windowOptOutEdgeToEdgeEnforcement` — gone in API 36.
/// - `SystemUiMode.leanBack` / manual overlays to hide the bars — hides system
///   UI the POS UI depends on, and the bars are non-optional on 15+ anyway.
/// - `SystemChrome.setSystemUIOverlayStyle` or bar colors — would override the
///   theme's own system-bar treatment.
///
/// The call only declares the window policy. It sets no bar colors and no
/// overlay style, so ownership of the bars stays where it belongs: the
/// Material [AppBar] derives its top system-UI presentation from the active
/// theme, `NavigationBar`/`SafeArea` handle the bottom, and scrollable pages
/// only pad for their own content. That is why the phone header and bottom bar
/// need no manual inset math of their own.
///
/// Awaited rather than fired and forgotten so the policy is in place before
/// [runApp] draws the first frame — otherwise Android 14 would letterbox for a
/// frame and then reflow under the user.
///
/// Non-fatal by design, unlike the other bootstrap steps: this is presentation
/// policy, not a dependency like the environment or the database. A platform
/// channel failure must not abort startup into a blank window, and the platform
/// default is still correct on 15/16 and merely letterboxes on 14.
Future<void> _initSystemUi() async {
  try {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    AppTrace.event('boot.step', {
      'step': 'systemUi',
      'mode': SystemUiMode.edgeToEdge.name,
    });
    AppLog.info(
      'System UI mode set to edgeToEdge (Android 14/15/16 parity)',
      tag: _tag,
    );
  } catch (error, stackTrace) {
    AppTrace.fail('boot.step.systemUi_fail', error, stackTrace);
    AppLog.warning(
      'Could not set edge-to-edge system UI mode; keeping the platform default',
      tag: _tag,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// Loads the environment before anything that depends on it.
Future<void> _initEnvironment() async {
  await AppEnv.load();
  AppTrace.event('boot.step', {
    'step': 'env',
    'flavor': AppFlavor.current.name,
    'env': AppEnv.envFileName,
  });
  AppLog.info(
    'Environment loaded (flavor: ${AppFlavor.current.name}, '
    'env file: ${AppEnv.envFileName})',
    tag: _tag,
  );
}

/// Initializes local storage (secure storage + shared preferences).
Future<void> _initLocalStorage() async {
  await AppStorage.init();
  AppTrace.event('boot.step', {'step': 'storage'});
  AppLog.info('Local storage initialized', tag: _tag);
}

/// Initializes the Supabase client from environment values.
///
/// Explicit auth options ensure session persistence and background refresh
/// behave identically on Phone and Tablet (some OEMs delay timers when the
/// app is backgrounded). This directly addresses the tablet sign-out report
/// where a stored refresh token was not being refreshed after the app was
/// closed for a long period.
Future<void> _initSupabase() async {
  await Supabase.initialize(
    url: AppEnv.supabaseUrl,
    publishableKey: AppEnv.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      autoRefreshToken: true,
    ),
    // Silence the SDK's own debug output in production builds.
    debug: AppFlavor.current.isDevelopment,
  );
  AppTrace.event('boot.step', {'step': 'supabase'});
  AppLog.info('Supabase client initialized', tag: _tag);
}
