import 'package:flutter/widgets.dart';

import 'app_colors.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Gradients
///
/// Used only where the approved reference actually requires a gradient
/// (brand monogram, hero/soft surfaces). Plain surfaces stay flat.
/// ---------------------------------------------------------------------------

final class AppGradients {
  AppGradients._();

  /// Brand gradient: Brew Green → Dark Green.
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.primaryDark],
  );

  /// Soft hero surface: Soft Green → White.
  static const LinearGradient soft = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.softGreen, AppColors.surface],
  );
}
