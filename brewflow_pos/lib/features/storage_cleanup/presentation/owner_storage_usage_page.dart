import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/state_views.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Formats a byte count as a compact human-readable string (e.g. 1.5 MB).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Owner-only storage monitoring + monthly cleanup screen.
///
/// Access is enforced by the route guard and by the controller; the screen is
/// only ever built for owners. It shows used storage, the configured limit
/// (and usage %), product image count, orphan count, reclaimable size and the
/// last cleanup — then offers a "Review Files" path into the owner-confirmed
/// cleanup flow.
final class OwnerStorageUsagePage extends ConsumerStatefulWidget {
  const OwnerStorageUsagePage({super.key});

  @override
  ConsumerState<OwnerStorageUsagePage> createState() =>
      _OwnerStorageUsagePageState();
}

final class _OwnerStorageUsagePageState
    extends ConsumerState<OwnerStorageUsagePage> {
  @override
  void initState() {
    super.initState();
    // Hydrate local notification + last-cleanup, then run a fresh scan once.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final controller = ref.read(storageCleanupControllerProvider.notifier);
      await controller.hydrate();
      await controller.scan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storageCleanupControllerProvider);
    final report = state.report;

    return Scaffold(
      appBar: AppBar(title: const Text('Storage & Cleanup')),
      body: ListView(
        padding: AppInsets.screen,
        children: [
          const PageHeader(
            title: 'Cloud Storage',
            subtitle:
                'Monitor your shop\'s product images and reclaim space from '
                'orphaned (unreferenced) files.',
          ),
          const SizedBox(height: AppSpacing.md),
          if (state.notification != null)
            _CleanupAvailableBanner(
              notification: state.notification!,
              onReview: () => context.go(
                AppRoutes.storageCleanupReview,
                extra: state.report,
              ),
            ),
          if (state.lastError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ErrorState(message: state.lastError!),
          ],
          const SizedBox(height: AppSpacing.md),
          if (state.isScanning && report == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: LoadingState(message: 'Scanning storage…'),
            )
          else if (report == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const EmptyState(
                    icon: Icons.cloud_upload_outlined,
                    title: 'No storage scan yet.',
                    message: 'Tap below to scan your shop\'s cloud storage.',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    label: state.isScanning ? 'Scanning…' : 'Scan storage',
                    icon: Icons.refresh,
                    loading: state.isScanning,
                    expanded: true,
                    onPressed: () async {
                      try {
                        await ref
                            .read(storageCleanupControllerProvider.notifier)
                            .scan();
                      } catch (_) {}
                    },
                  ),
                ],
              ),
            )
          else
            _StorageStatsCard(state: state, report: report),
        ],
      ),
    );
  }
}

/// Collapsed stats view when a report is available.
final class _StorageStatsCard extends ConsumerWidget {
  const _StorageStatsCard({required this.state, required this.report});

  final StorageCleanupState state;
  final StorageUsageReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limit = report.storageLimitBytes;
    final fraction = report.usageFraction;
    final rows = <_StatRow>[
      _StatRow(
        label: 'Used storage',
        value: formatBytes(report.usedBytes),
        icon: Icons.storage_outlined,
      ),
      _StatRow(
        label: 'Configured limit',
        value: limit == null ? 'Unlimited' : formatBytes(limit),
        icon: Icons.speed_outlined,
      ),
      if (fraction != null)
        _StatRow(
          label: 'Usage',
          value: '${(fraction * 100).round()}%',
          icon: Icons.percent,
        ),
      _StatRow(
        label: 'Product images',
        value: '${report.imageCount}',
        icon: Icons.image_outlined,
      ),
      _StatRow(
        label: 'Orphan images',
        value: '${report.orphanCount}',
        icon: Icons.broken_image_outlined,
      ),
      _StatRow(
        label: 'Reclaimable size',
        value: formatBytes(report.reclaimableBytes),
        icon: Icons.cleaning_services_outlined,
      ),
      _StatRow(
        label: 'Last cleanup',
        value: state.lastCleanupAt == null
            ? 'Never'
            : _formatDate(state.lastCleanupAt!),
        icon: Icons.event_available_outlined,
      ),
    ];

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: Padding(
        padding: AppInsets.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows) ...[
              row,
              const SizedBox(height: AppSpacing.sm),
            ],
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: SecondaryButton(
                    label: 'Scan again',
                    icon: Icons.refresh,
                    onPressed: () async {
                      try {
                        await ref
                            .read(storageCleanupControllerProvider.notifier)
                            .scan();
                      } catch (_) {}
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: report.orphanCount > 0
                        ? 'Review files'
                        : 'Nothing to review',
                    icon: report.orphanCount > 0
                        ? Icons.cleaning_services_outlined
                        : Icons.check_circle_outline,
                    onPressed: report.orphanCount > 0
                        ? () => context.go(
                            AppRoutes.storageCleanupReview,
                            extra: report,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime t) {
    final local = t.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

/// Banner linking to [OwnerStorageUsagePage]'s notification details via the
/// review flow.
final class _CleanupAvailableBanner extends ConsumerWidget {
  const _CleanupAvailableBanner({
    required this.notification,
    required this.onReview,
  });

  final StorageCleanupNotificationRecord notification;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: AppInsets.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.cleaning_services_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Cleanup available',
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${notification.orphanCount} unreferenced image(s) '
              '(${formatBytes(notification.reclaimableBytes)}) can be '
              'reclaimed. Review and confirm before anything is deleted.',
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                SecondaryButton(
                  label: 'Dismiss',
                  icon: Icons.close,
                  onPressed: () async {
                    await ref
                        .read(storageCleanupControllerProvider.notifier)
                        .dismissNotification();
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                PrimaryButton(
                  label: 'Review Files',
                  icon: Icons.cleaning_services_outlined,
                  onPressed: onReview,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

final class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
