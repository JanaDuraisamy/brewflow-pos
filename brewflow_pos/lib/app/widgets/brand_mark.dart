import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_gradients.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Brand
///
/// - [BrandMark]: the JiggarTea Bill logo tile, with light/dark variants and
///   the approved size ladder.
/// - [BrewFlowBrand]: logo + wordmark (+ optional edition and tagline)
///   used in headers, splash and the dark navigation areas.
///
/// Approved copy:
///   wordmark: JiggarTea Bill
///   edition:  Tea & Jigarthanda Edition
///   tagline:  Smart Business. Simple Billing.
/// ---------------------------------------------------------------------------

/// Where the logo sits: green tile on light surfaces, light tile on the
/// dark green navigation surfaces.
enum BrandMarkVariant { onLight, onDark }

/// JiggarTea Bill brand logo tile.
final class BrandMark extends StatelessWidget {
  const BrandMark({
    super.key,
    this.variant = BrandMarkVariant.onLight,
    this.size = regularSize,
  });

  /// Compact navigation size.
  static const double compactSize = 28;

  /// Small branding size (sidebars, headers).
  static const double smallSize = 36;

  /// Default branding size.
  static const double regularSize = 44;

  /// Hero branding size (splash, large surfaces).
  static const double largeSize = 64;

  static const String _assetPath = 'assets/images/brand_logo.png';

  final BrandMarkVariant variant;
  final double size;

  @override
  Widget build(BuildContext context) {
    final onDark = variant == BrandMarkVariant.onDark;
    final radius = BorderRadius.circular(size * 0.28);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: onDark ? null : AppGradients.brand,
        color: onDark ? Colors.white : null,
        boxShadow: onDark ? null : const [AppShadows.xs],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Image.asset(
          _assetPath,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

final class BrewFlowBrand extends StatelessWidget {
  const BrewFlowBrand({
    super.key,
    this.variant = BrandMarkVariant.onLight,
    this.monogramSize = BrandMark.regularSize,
    this.showEdition = false,
    this.showTagline = true,
  });

  final BrandMarkVariant variant;
  final double monogramSize;
  final bool showEdition;
  final bool showTagline;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final onDark = variant == BrandMarkVariant.onDark;
    final secondaryColor = onDark ? Colors.white70 : appColors.textSecondary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandMark(variant: variant, size: monogramSize),
        SizedBox(
          width: monogramSize < BrandMark.regularSize
              ? AppSpacing.sm
              : AppSpacing.md,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'JiggarTea Bill',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: onDark ? Colors.white : appColors.charcoal,
                height: 1.1,
              ),
            ),
            if (showEdition) ...[
              const SizedBox(height: 2),
              Text(
                'Tea & Jigarthanda Edition',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: AppColors.gold,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ],
            if (showTagline) ...[
              const SizedBox(height: 2),
              Text(
                'Smart Business. Simple Billing.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(color: secondaryColor),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
