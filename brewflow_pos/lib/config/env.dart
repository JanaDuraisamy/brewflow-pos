import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'flavor.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Environment Configuration
///
/// Strongly typed, fail-fast access to environment values loaded from the
/// `.env` asset file.
///
/// Usage:
///   await AppEnv.load();            // once, during app bootstrap
///   final url = AppEnv.supabaseUrl; // typed accessor
///
/// Rules:
/// - Supabase URL and keys are NEVER hardcoded in source.
/// - Missing or placeholder values fail with a clear error in production
///   builds, and are tolerated in development builds.
/// - Access before [AppEnv.load] fails with a clear error.
///
/// Future consumers (Supabase init, database, logging, sync, auth) reuse
/// [AppEnv.required] / [AppEnv.maybeGet] for additional variables without
/// modifying this file.
/// ---------------------------------------------------------------------------

final class AppEnv {
  AppEnv._();

  static final DotEnv _dotEnv = DotEnv();

  static bool _loaded = false;

  /// Name of the environment asset file declared in pubspec.yaml.
  static const String envFileName = '.env';

  /// Environment variable keys used by this app.
  static const String supabaseUrlEnvKey = 'SUPABASE_URL';
  static const String supabaseAnonKeyEnvKey = 'SUPABASE_ANON_KEY';

  /// Whether [load] has completed successfully.
  static bool get isLoaded => _loaded;

  /// Loads environment variables from the `.env` asset.
  ///
  /// - Production: the file is required; a missing file fails the app.
  /// - Development: the file is optional so the app can boot without it,
  ///   and missing values surface individually when accessed.
  static Future<void> load() async {
    if (_loaded) {
      return;
    }

    final isProduction = AppFlavor.current.isProduction;

    try {
      await _dotEnv.load(fileName: envFileName, isOptional: !isProduction);
    } catch (error) {
      throw StateError(
        'AppEnv: failed to load environment file "$envFileName". '
        '${isProduction ? 'Production builds require a valid .env file. ' : ''}'
        'See .env.example for the expected format. Cause: $error',
      );
    }

    _loaded = true;
  }

  // -------------------------------------------------------------------------
  // Typed accessors
  // -------------------------------------------------------------------------

  /// Supabase project URL (e.g. `https://abc123.supabase.co`).
  static String get supabaseUrl {
    final value = required(supabaseUrlEnvKey);
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.isAbsolute ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw StateError(
        'AppEnv: "$supabaseUrlEnvKey" is not a valid URL: "$value". '
        'Set a valid http(s) URL in $envFileName.',
      );
    }
    return value;
  }

  /// Supabase project URL parsed as a [Uri].
  static Uri get supabaseUri => Uri.parse(supabaseUrl);

  /// Supabase public `anon` key used for client-side authentication.
  static String get supabaseAnonKey => required(supabaseAnonKeyEnvKey);

  // -------------------------------------------------------------------------
  // Generic accessors
  // -------------------------------------------------------------------------

  /// Returns the raw value for [key], or `null` when unset.
  static String? maybeGet(String key) {
    _ensureLoaded();
    return _dotEnv.maybeGet(key)?.trim();
  }

  /// Returns the raw value for [key].
  ///
  /// Throws when [key] is unset or still contains a placeholder value.
  /// In development builds placeholder values are tolerated so the app can
  /// run before real credentials are configured.
  static String required(String key) {
    _ensureLoaded();

    final value = _dotEnv.maybeGet(key)?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError(
        'AppEnv: "$key" is not set. '
        'Add it to $envFileName (see .env.example).',
      );
    }

    if (_isPlaceholder(value)) {
      if (AppFlavor.current.isProduction) {
        throw StateError(
          'AppEnv: "$key" still contains a placeholder value. '
          'Set the real value in $envFileName for production builds.',
        );
      }
      // Development: tolerate placeholders until real credentials are set.
    }

    return value;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  static void _ensureLoaded() {
    if (!_loaded) {
      throw StateError(
        'AppEnv: load() must be called before reading environment values.',
      );
    }
  }

  static bool _isPlaceholder(String value) {
    final lower = value.toLowerCase();
    const markers = <String>[
      'your-',
      'your_',
      'change-me',
      'placeholder',
      'example.com',
      'xxx',
    ];
    return markers.any(lower.contains) || lower.startsWith('<');
  }
}
