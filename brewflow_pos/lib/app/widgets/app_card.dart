import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Cards
///
/// - [AppCard]: the standard white surface with subtle shadow, divider border
///   and BrewFlow radius. Every content surface uses it; never raw Cards.
/// - [SectionCard]: [AppCard] with a title header row (optional subtitle and
///   trailing action) — the standard section wrapper.
/// ---------------------------------------------------------------------------

final class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = AppInsets.card,
    this.onTap,
    this.onLongPress,
    this.color,
    this.borderRadius = AppBorderRadius.lg,
    this.border,
    this.shadows = const [AppShadows.sm],
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Optional long-press action (e.g. opening a context action sheet).
  /// When both [onTap] and [onLongPress] are provided, the card supports both.
  final VoidCallback? onLongPress;

  /// Overrides the theme surface color (scheme surface by default).
  final Color? color;
  final BorderRadius borderRadius;
  final BoxBorder? border;
  final List<BoxShadow> shadows;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: Ink(
          decoration: BoxDecoration(
            color: color ?? appColors.surface,
            borderRadius: borderRadius,
            border: border ?? Border.all(color: appColors.divider),
            boxShadow: shadows,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Standard titled section surface.
final class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.child,
    this.padding = AppInsets.card,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return AppCard(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: appColors.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitle!,
                        style: textTheme.bodySmall?.copyWith(
                          color: appColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          if (child != null) ...[const SizedBox(height: AppSpacing.md), child!],
        ],
      ),
    );
  }
}
