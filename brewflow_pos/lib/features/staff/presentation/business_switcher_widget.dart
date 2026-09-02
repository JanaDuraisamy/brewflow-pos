import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Business Switcher (Owner)
///
/// Compact segmented selector letting the Owner Phone switch between CAFE,
/// FOOD TRUCK and COMBINED (All Businesses). It is Owner-only: staff tablets
/// are fixed to one assigned business and must never offer this switcher.
/// Consumers guard visibility by role; this widget itself renders only the
/// three contexts that make sense for a multi-business owner.
///
/// The COMBINED selection is a read-only view — write paths reject it via
/// [BusinessSwitcherController.requireWritableShopId], and this widget never
/// pretends otherwise (no write affordances are gated on it here).
/// ---------------------------------------------------------------------------
final class BusinessSwitcher extends ConsumerWidget {
  const BusinessSwitcher({super.key, this.compact = false});

  /// When true, renders tighter (side bar / header use). Labels stay stable.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final business = ref.watch(businessSwitcherProvider);
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
