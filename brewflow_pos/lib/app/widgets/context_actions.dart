import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Context Actions & Destructive Confirmations
///
/// Shared primitives for long-press context actions and destructive-action
/// confirmations, so every entity card offers the same safe, consistent
/// surface (identity + consequence + Cancel + a clearly destructive confirm)
/// and never deletes silently.
///
/// The action menu is a compact, iOS-inspired panel — tight rows with leading
/// glyphs, a single destructive (red) action, and a dismiss-bar "Cancel" row —
/// instead of a large full-width sheet. Action code is run only after the
/// menu has closed, so follow-up dialogs open on top safely.
/// ---------------------------------------------------------------------------

/// One selectable action inside a context action menu.
final class ContextMenuItem {
  const ContextMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.enabled = true,
  });

  final IconData icon;
  final String label;

  /// Invoked after the menu closes; the menu is popped before this runs so
  /// action code can open dialogs/inputs on top of the closing sheet.
  final VoidCallback onTap;
  final bool destructive;
  final bool enabled;
}

/// Renders a compact, rounded context-action menu with a [title] and a stack
/// of [ContextMenuItem]s. The destructive item is shown in red; a Cancel row
/// dismisses. Each action is popped before its callback runs, so follow-up
/// dialogs (e.g. confirmation or edit inputs) open on top safely.
Future<void> showContextActionSheet(
  BuildContext context, {
  required String title,
  required List<ContextMenuItem> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      final textTheme = Theme.of(sheetContext).textTheme;
      final appColors = sheetContext.appColors;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            0,
            AppSpacing.sm,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: appColors.surface,
                borderRadius: AppBorderRadius.xl,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: appColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const _MenuSeparator(),
                    for (final item in items)
                      _CompactAction(item: item, card: appColors.surface),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Material(
                color: appColors.surface,
                borderRadius: AppBorderRadius.xl,
                child: InkWell(
                  onTap: () => Navigator.of(sheetContext).pop(),
                  borderRadius: AppBorderRadius.xl,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    child: Text(
                      'Cancel',
                      textAlign: TextAlign.center,
                      style: textTheme.titleSmall?.copyWith(
                        color: appColors.charcoal,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
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

final class _MenuSeparator extends StatelessWidget {
  const _MenuSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      color: Theme.of(context).dividerColor.withValues(alpha: 0.4),
    );
  }
}

final class _CompactAction extends StatelessWidget {
  const _CompactAction({required this.item, required this.card});

  final ContextMenuItem item;
  final Color card;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final color = item.destructive
        ? AppColors.error
        : item.enabled
        ? appColors.charcoal
        : appColors.textDisabled;
    return InkWell(
      onTap: item.enabled
          ? () {
              Navigator.of(context).pop();
              item.onTap();
            }
          : null,
      child: Container(
        color: card,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        child: Row(
          children: [
            SizedBox(width: 28, child: Icon(item.icon, size: 20, color: color)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                item.label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows a destructive confirmation dialog naming the [subject] and stating
/// the [consequence], with Cancel + a destructive confirm labelled
/// [confirmLabel]. Returns true only when the user confirms the destructive
/// action.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String subject,
  required String consequence,
  String confirmLabel = 'Delete',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final textTheme = Theme.of(dialogContext).textTheme;
      final appColors = dialogContext.appColors;
      return AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: AppColors.error),
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subject,
              style: textTheme.titleSmall?.copyWith(
                color: appColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              consequence,
              style: textTheme.bodySmall?.copyWith(
                color: appColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return confirmed == true;
}
