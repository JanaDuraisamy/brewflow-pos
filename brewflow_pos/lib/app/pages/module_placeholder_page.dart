import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Module Placeholder Page
///
/// Intentional shell state for destinations whose business modules arrive in
/// later implementation phases. Identifies the destination clearly without
/// any business UI or fake data.
/// ---------------------------------------------------------------------------

final class ModulePlaceholderPage extends StatelessWidget {
  const ModulePlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
    required this.description,
  });

  final String title;
  final IconData icon;
  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      padding: AppInsets.screen,
      children: [
        PageHeader(title: title),
        const SizedBox(height: AppSpacing.massive),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Icon(icon, size: AppSpacing.ultra, color: AppColors.primary),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '$title module',
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    color: context.appColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'This module is coming in the next implementation phase.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
