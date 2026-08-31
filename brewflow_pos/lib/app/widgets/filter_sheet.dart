import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Phone Filter Sheet
///
/// On phones (<600dp) the page-level filter bars are consolidated into a
/// single [FilterSheetButton] that opens [showFilterSheet]: one trigger, no
/// crowded horizontal chip rows. Tablets keep their inline filter bars, so
/// this widget only ever appears on compact layouts.
/// ---------------------------------------------------------------------------

/// Compact trigger that opens the filter sheet; shows the active filter count
/// so users can see at a glance that results are being narrowed.
final class FilterSheetButton extends StatelessWidget {
  const FilterSheetButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.filter_alt_outlined, size: 18),
      label: Text(activeCount > 0 ? 'Filters ($activeCount)' : 'Filters'),
    );
  }
}

/// Opens a bottom-sheet filter panel. [children] are the filter chips/widgets
/// built by the page; [onReset] (when provided) clears all active filters.
/// Chips update the underlying filter provider live while the sheet stays
/// open.
Future<void> showFilterSheet(
  BuildContext context, {
  required String title,
  required List<Widget> children,
  VoidCallback? onReset,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (sheetContext) {
      final textTheme = Theme.of(sheetContext).textTheme;
      final appColors = sheetContext.appColors;
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.xs,
            AppSpacing.screenPadding,
            AppSpacing.massive,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: textTheme.titleMedium?.copyWith(
                        color: appColors.charcoal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onReset != null)
                    TextButton(onPressed: onReset, child: const Text('Reset')),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
