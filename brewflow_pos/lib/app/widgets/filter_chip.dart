import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Filter Chip
///
/// Pill filter with BrewFlow selected state: tappable fill turned green with
/// a strong filled green background when active, light gray otherwise. The
/// selected colors come from theme tokens so the fill stays legible in light
/// and dark mode.
/// ---------------------------------------------------------------------------

final class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected
        ? appColors.selectedControlForeground
        : appColors.textSecondary;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: AppBorderRadius.pill,
        onTap: () => onSelected(!selected),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? appColors.selectedControlBackground
                : appColors.lightGray,
            borderRadius: AppBorderRadius.pill,
            border: Border.all(
              color: selected ? scheme.primary : appColors.divider,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: foreground),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                label,
                style: textTheme.labelLarge?.copyWith(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
