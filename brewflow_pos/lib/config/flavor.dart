/// Compile-time application flavor selection.
///
/// Select the flavor when building or running:
///
///   flutter run  --dart-define=APP_FLAVOR=development
///   flutter run  --dart-define=APP_FLAVOR=production
///
/// When APP_FLAVOR is not provided, `AppFlavor.current` resolves to
/// [AppFlavor.development] so local development works out of the box.
/// An unknown value fails fast with a clear error instead of silently
/// falling back to the wrong environment.
library;

enum AppFlavor {
  development(
    name: 'development',
    label: 'Development',
    isProduction: false,
    showDebugBanner: true,
  ),
  production(
    name: 'production',
    label: 'Production',
    isProduction: true,
    showDebugBanner: false,
  );

  const AppFlavor({
    required this.name,
    required this.label,
    required this.isProduction,
    required this.showDebugBanner,
  });

  /// Compile-time define used to select the flavor.
  static const String defineKey = 'APP_FLAVOR';

  /// The flavor the app was built with.
  static AppFlavor get current {
    const raw = String.fromEnvironment(defineKey);
    return switch (raw.trim().toLowerCase()) {
      'production' || 'prod' => AppFlavor.production,
      'development' || 'dev' || '' => AppFlavor.development,
      final unknown => throw StateError(
        'AppFlavor: unknown APP_FLAVOR "$unknown". '
        'Use "development" or "production".',
      ),
    };
  }

  /// Canonical flavor name (e.g. `development`).
  final String name;

  /// Human-readable flavor label (e.g. `Development`).
  final String label;

  /// Whether this flavor is the production build.
  final bool isProduction;

  /// Whether the Material debug banner is shown in this flavor.
  final bool showDebugBanner;

  bool get isDevelopment => !isProduction;
}
