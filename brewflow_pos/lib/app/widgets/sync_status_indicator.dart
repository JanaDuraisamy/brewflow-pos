import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Status Indicator
///
/// Compact, non-intrusive visual indicator showing sync health.
/// Used in the app shell sidebar (desktop/tablet) and AppBar (mobile).
/// ---------------------------------------------------------------------------

/// Tiny colored dot used in the sidebar and AppBar — tap to sync now.
class SyncStatusDot extends ConsumerWidget {
  const SyncStatusDot({super.key, this.onDark = false});

  /// When true the dot uses light colors suitable for the dark sidebar.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final color = _colorForStatus(status, onDark: onDark);

    return Tooltip(
      message: _labelForStatus(status),
      child: InkWell(
        onTap: status.isSyncing
            ? null
            : () => ref.read(syncStatusProvider.notifier).syncNow(),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: status.isSyncing
              ? SizedBox(
                  width: 8,
                  height: 8,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                  ),
                )
              : Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Compact text + dot for the mobile AppBar area — tap to sync now.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    if (status.level == SyncStatusLevel.idle) {
      return const SizedBox.shrink();
    }

    final color = _colorForStatus(status, onDark: false);
    final label = _compactLabel(status);

    return InkWell(
      onTap: status.isSyncing
          ? null
          : () => ref.read(syncStatusProvider.notifier).syncNow(),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (status.isSyncing)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              )
            else
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _compactLabel(SyncStatusSnapshot status) {
  if (status.isSyncing) return 'Syncing…';
  switch (status.level) {
    case SyncStatusLevel.idle:
      return '';
    case SyncStatusLevel.synced:
      if (status.lastSyncAt != null) return 'Synced';
      return 'Synced';
    case SyncStatusLevel.pending:
      return '${status.pendingCount} pending';
    case SyncStatusLevel.offline:
      return 'Offline';
    case SyncStatusLevel.unconfirmed:
      return 'Connecting…';
    case SyncStatusLevel.syncing:
      return 'Syncing…';
    case SyncStatusLevel.error:
      return 'Sync failed';
  }
}

String _labelForStatus(SyncStatusSnapshot status) {
  if (status.isSyncing) return 'Syncing… — tap to wait';
  switch (status.level) {
    case SyncStatusLevel.idle:
      return 'Not signed in';
    case SyncStatusLevel.synced:
      if (status.lastSyncAt != null) return 'Synced just now';
      return 'All data synced';
    case SyncStatusLevel.pending:
      final parts = <String>['${status.pendingCount} item(s) pending sync'];
      if (status.failedCount > 0) {
        parts.add('${status.failedCount} failed');
      }
      return parts.join(' · ');
    case SyncStatusLevel.offline:
      return 'Offline · Changes saved locally — tap to retry when online';
    case SyncStatusLevel.unconfirmed:
      return 'Cloud connecting…';
    case SyncStatusLevel.syncing:
      return 'Syncing…';
    case SyncStatusLevel.error:
      return 'Sync failed · Tap to retry';
  }
}

Color _colorForStatus(SyncStatusSnapshot status, {required bool onDark}) {
  if (status.isSyncing) {
    return onDark ? Colors.white70 : AppColors.info;
  }
  return switch (status.level) {
    SyncStatusLevel.idle => onDark ? Colors.white38 : AppColors.textSecondary,
    SyncStatusLevel.synced =>
      onDark ? const Color(0xFF81C784) : AppColors.success,
    SyncStatusLevel.pending => onDark ? AppColors.gold : AppColors.warning,
    SyncStatusLevel.offline => onDark ? Colors.white54 : AppColors.warning,
    SyncStatusLevel.unconfirmed => onDark ? Colors.white38 : AppColors.info,
    SyncStatusLevel.syncing => onDark ? Colors.white70 : AppColors.info,
    SyncStatusLevel.error => onDark ? const Color(0xFFEF9A9A) : AppColors.error,
  };
}
