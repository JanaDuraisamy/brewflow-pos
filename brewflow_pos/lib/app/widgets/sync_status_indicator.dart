import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Status Indicator
///
/// Compact, non-intrusive visual indicator showing sync health.
/// Used in the app shell sidebar (desktop/tablet) and AppBar (mobile).
/// ---------------------------------------------------------------------------

/// Tiny colored dot showing simple online/offline status.
/// Phase 2 online-only: no pending count, no manual sync action.
class SyncStatusDot extends ConsumerWidget {
  const SyncStatusDot({super.key, this.onDark = false});

  /// When true the dot uses light colors suitable for the dark sidebar.
  final bool onDark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityServiceProvider);
    final status = connectivity.status;
    final isOnline = status == ConnectivityStatus.online;
    final isOffline = status == ConnectivityStatus.disconnected;
    final color = isOnline
        ? (onDark ? const Color(0xFF81C784) : AppColors.success)
        : isOffline
        ? (onDark ? Colors.white54 : AppColors.warning)
        : (onDark ? Colors.white38 : AppColors.textSecondary);
    final label = isOnline
        ? 'Online'
        : isOffline
        ? 'Offline — Internet required for all changes'
        : 'Checking connection…';

    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact text + dot for the mobile AppBar area — online/offline only.
class SyncStatusBadge extends ConsumerWidget {
  const SyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(connectivityServiceProvider);
    final status = connectivity.status;
    final isOnline = status == ConnectivityStatus.online;
    final isOffline = status == ConnectivityStatus.disconnected;
    if (status == ConnectivityStatus.unknown) {
      return const SizedBox.shrink();
    }
    final color = isOnline
        ? AppColors.success
        : isOffline
        ? AppColors.warning
        : AppColors.textSecondary;
    final label = isOnline ? 'Online' : 'Offline';

    return Container(
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
    );
  }
}
