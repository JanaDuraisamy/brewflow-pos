import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme_colors.dart';
import 'app_typography.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Theme
///
/// Central Theme Configuration. Both themes derive every surface/text color
/// from their [ColorScheme] plus the [AppThemeColors] extension; brand/status
/// colors come from the static [AppColors] palette and never change.
/// ---------------------------------------------------------------------------

final class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
    brightness: Brightness.light,
    scheme: AppColors.lightScheme,
    appColors: AppThemeColors.light,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    scheme: AppColors.darkScheme,
    appColors: AppThemeColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppThemeColors appColors,
  }) {
    final isDark = brightness == Brightness.dark;
    final scaffold = isDark ? scheme.surface : appColors.background;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,

      colorScheme: scheme,
      textTheme: AppTypography.textTheme,
      scaffoldBackgroundColor: scaffold,

      splashFactory: InkRipple.splashFactory,

      extensions: [appColors],

      dividerColor: appColors.divider,

      // ---------------------------------------------------------------------
      // Surfaces
      // ---------------------------------------------------------------------
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: scheme.surface,
        modalBarrierColor: scheme.scrim,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),

      // ---------------------------------------------------------------------
      // App bar / navigation
      // ---------------------------------------------------------------------
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: appColors.softGreen,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : appColors.textSecondary,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : appColors.textSecondary,
          ),
        ),
      ),

      // ---------------------------------------------------------------------
      // Inputs
      // ---------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: appColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHighest : appColors.surface,
        labelStyle: TextStyle(color: appColors.textSecondary),
        hintStyle: TextStyle(color: appColors.textDisabled),
        suffixIconColor: appColors.textSecondary,
        prefixIconColor: appColors.textSecondary,
      ),

      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: TextStyle(color: appColors.textPrimary),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: isDark
              ? scheme.surfaceContainerHighest
              : appColors.surface,
          border: OutlineInputBorder(
            borderSide: BorderSide(color: appColors.outline),
          ),
        ),
      ),

      textSelectionTheme: TextSelectionThemeData(
        cursorColor: scheme.primary,
        selectionColor: scheme.primary.withValues(alpha: 0.4),
        selectionHandleColor: scheme.primary,
      ),

      // ---------------------------------------------------------------------
      // Buttons / chips / controls
      // ---------------------------------------------------------------------
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          disabledBackgroundColor: appColors.surfaceVariant,
          disabledForegroundColor: appColors.textDisabled,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: appColors.surfaceVariant,
        selectedColor: appColors.softGreen,
        labelStyle: TextStyle(color: appColors.textPrimary),
        secondaryLabelStyle: TextStyle(color: appColors.textSecondary),
        side: BorderSide(color: appColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary.withValues(alpha: 0.5)
              : scheme.surfaceContainerHighest,
        ),
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : appColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primaryContainer
                : appColors.surfaceVariant,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: appColors.divider)),
        ),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : Colors.transparent,
        ),
        side: BorderSide(color: scheme.outline),
      ),

      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.outline,
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),

      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: scheme.onInverseSurface, fontSize: 12),
      ),

      // ---------------------------------------------------------------------
      // Lists / tables / misc
      // ---------------------------------------------------------------------
      listTileTheme: ListTileThemeData(
        iconColor: appColors.textSecondary,
        textColor: appColors.textPrimary,
      ),

      iconTheme: IconThemeData(color: appColors.textPrimary),

      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(appColors.surfaceVariant),
        dataRowColor: WidgetStatePropertyAll(appColors.surface),
        dividerThickness: 1,
        headingTextStyle: AppTypography.textTheme.labelLarge?.copyWith(
          color: appColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: AppTypography.textTheme.bodyMedium?.copyWith(
          color: appColors.textPrimary,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: appColors.divider,
        thickness: 1,
        space: 1,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.fixed,
      ),
    );
  }
}
