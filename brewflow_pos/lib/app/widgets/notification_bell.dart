import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_typography.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Notification Bell
///
/// Header notification icon with a gold count badge. The badge is hidden when
/// [count] is zero so headers stay clean.
/// ---------------------------------------------------------------------------

final class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    this.count = 0,
    this.color,
    this.onPressed,
  });

  final int count;
  final Color? color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: 'Notifications',
      icon: Badge(
        isLabelVisible: count > 0,
        backgroundColor: AppColors.gold,
        textColor: context.appColors.charcoal,
        label: Text(
          count > 99 ? '99+' : '$count',
          style: AppTypography.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.appColors.charcoal,
          ),
        ),
        child: Icon(
          Icons.notifications_outlined,
          color: color ?? context.appColors.textPrimary,
        ),
      ),
    );
  }
}
