import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Business Switcher (Owner)
///
/// Compact selector letting the Owner Phone switch between CAFE, FOOD TRUCK
/// and COMBINED (All Businesses). It is Owner-only: staff tablets are fixed to
/// one assigned business and must never offer this switcher. Consumers guard
/// visibility by role; this widget itself renders only the three contexts that
/// make sense for a multi-business owner.
///
/// Two renderings:
///  - [dropdown] (Owner phone header): a compact, full-width [DropdownButton]
///    that is never clipped on narrow phone widths while keeping all three
///    options clearly readable and tappable.
///  - otherwise: the three-segment [SegmentedButton] used on wider layouts
///    (e.g. the extended sidebar) — unchanged.
///
/// The COMBINED selection is a read-only view — write paths reject it via
/// [BusinessSwitcherController.requireWritableShopId], and this widget never
/// pretends otherwise (no write affordances are gated on it here).
/// ---------------------------------------------------------------------------
final class BusinessSwitcher extends ConsumerWidget {
  const BusinessSwitcher({
    super.key,
    this.compact = false,
    this.dropdown = false,
  });

  /// When true, renders tighter (side bar / header use). Labels stay stable.
  final bool compact;

  /// Phone-header friendly compact dropdown that fits any phone width without
  /// clipping. Wider contexts (sidebar) keep the segmented control.
  final bool dropdown;

  /// Menu entries in display order. Labels are stable user-visible text.
  static const List<(BusinessContext, String)> _entries = [
    (BusinessContext.cafe, 'Cafe'),
    (BusinessContext.foodTruck, 'Food Truck'),
    (BusinessContext.all, 'Combined'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessSwitcherProvider);
    if (dropdown) {
      return _BusinessDropdown(
        business: business,
        onChanged: (next) =>
            ref.read(businessSwitcherProvider.notifier).select(next),
      );
    }
    return SegmentedButton<BusinessContext>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(
        visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
        tapTargetSize: compact
            ? MaterialTapTargetSize.shrinkWrap
            : MaterialTapTargetSize.padded,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: AppSpacing.xs)
            : const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      segments: const [
        ButtonSegment(value: BusinessContext.cafe, label: Text('Cafe')),
        ButtonSegment(
          value: BusinessContext.foodTruck,
          label: Text('Food Truck'),
        ),
        ButtonSegment(value: BusinessContext.all, label: Text('Combined')),
      ],
      selected: {business},
      onSelectionChanged: (selection) =>
          ref.read(businessSwitcherProvider.notifier).select(selection.first),
    );
  }
}

/// Compact phone-header dropdown. Expands to the available width so the three
/// business contexts can never be clipped, and keeps the black/gold brand
/// look (gold border + arrow, charcoal/theme text, gold check on selection).
final class _BusinessDropdown extends StatelessWidget {
  const _BusinessDropdown({required this.business, required this.onChanged});

  final BusinessContext business;

  final ValueChanged<BusinessContext> onChanged;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: appColors.surface,
        borderRadius: AppBorderRadius.sm,
        border: Border.all(color: AppColors.gold, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: DropdownButton<BusinessContext>(
          value: business,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: AppBorderRadius.sm,
          icon: const Icon(Icons.arrow_drop_down, color: AppColors.gold),
          style: textTheme.labelMedium?.copyWith(
            color: appColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          items: [
            for (final (value, label) in BusinessSwitcher._entries)
              DropdownMenuItem(
                value: value,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value == business) ...[
                      const Icon(Icons.check, size: 16, color: AppColors.gold),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                    Text(label),
                  ],
                ),
              ),
          ],
          onChanged: (next) {
            if (next != null && next != business) onChanged(next);
          },
        ),
      ),
    );
  }
}
