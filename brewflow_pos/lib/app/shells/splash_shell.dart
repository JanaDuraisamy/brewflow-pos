import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Splash Shell
///
/// Brand presentation only: the first route shown at startup. Deliberately
/// contains no loading logic, no artificial delay and no auth logic — route
/// decisions are owned by the router in later steps.
/// ---------------------------------------------------------------------------

final class SplashShell extends StatelessWidget {
  const SplashShell({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_cafe,
                size: AppSpacing.ultra,
                color: AppColors.primary,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                'BrewFlow',
                style: textTheme.displaySmall?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Point of Sale',
                style: textTheme.bodyLarge?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
