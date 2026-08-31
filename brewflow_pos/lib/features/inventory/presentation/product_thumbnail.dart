import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Thumbnail
///
/// Image-aware product picture used across inventory, POS and the product
/// form. Shows the stored image when available; falls back to the neutral
/// product placeholder whenever there is no image, the file is missing, or
/// the file fails to decode — a missing image must never crash the UI.
/// ---------------------------------------------------------------------------

final class ProductThumbnail extends ConsumerWidget {
  const ProductThumbnail({super.key, this.imagePath, this.size = 44});

  /// Relative [Product.imagePath]; null renders the placeholder.
  final String? imagePath;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(productImageStoreProvider).value;
    final file = imagePath == null ? null : store?.resolve(imagePath!);
    if (file == null) {
      return _placeholder(context, size: size);
    }
    return ClipRRect(
      borderRadius: AppBorderRadius.md,
      child: Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _placeholder(context, size: size),
      ),
    );
  }

  Widget _placeholder(BuildContext context, {required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.appColors.surfaceVariant,
        borderRadius: AppBorderRadius.md,
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: size * 0.5,
        color: context.appColors.textDisabled,
      ),
    );
  }
}
