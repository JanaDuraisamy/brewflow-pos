import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — App Avatar
///
/// Circular identity tile with the name's initial. Used for the owner/profile
/// area in headers. [name] is the display identity; the initial is derived.
/// ---------------------------------------------------------------------------

final class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.backgroundColor = AppColors.primary,
    this.foregroundColor = Colors.white,
    this.onTap,
  });

  final String name;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isEmpty ? '?' : trimmed[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Text(
        _initial,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontSize: size * 0.42,
          height: 1,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
    if (onTap == null) {
      return content;
    }
    return GestureDetector(onTap: onTap, child: content);
  }
}
