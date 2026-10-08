import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/app/widgets/context_actions.dart';
import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/state_views.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/reports/data/management_report_pdf.dart';
import 'package:brewflow_pos/features/reports/presentation/management_report_loader.dart';
import 'package:brewflow_pos/features/reports/presentation/report_pdf_preview.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Formats a UTC timestamp as a short local date (e.g. 2026-09-30).
String _shortDate(DateTime t) {
  final local = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)}';
}

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
/// only ever built for owners. Its health card shows only what the scan really
/// measured — product image count, image storage, orphan count, reclaimable
/// size and the last cleanup — topped with a Healthy / Needs attention status
/// derived from the orphan count. Quotas, limits and usage percentages are
/// deliberately not shown: they would be Supabase project numbers, not shop
/// facts. A "Review Files" path leads into the owner-confirmed cleanup flow.
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
    // Mounted-guarded: a fast navigation away before the frame (or during
    // the awaits) must silently drop the scan, never touch a dead ref.
    // Metrics + month history load alongside; each is best-effort so one
    // failing source never blocks the others.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final controller = ref.read(storageCleanupControllerProvider.notifier);
      await controller.hydrate();
      if (!mounted) return;
      // The controller records the failure (scanStatus/lastError); the page
      // only needs to swallow the rethrow so an auto-scan failure is not an
      // unhandled exception.
      try {
        await controller.scan();
      } catch (_) {}
      if (!mounted) return;
      try {
        await controller.loadMetrics();
      } catch (_) {}
      if (!mounted) return;
      try {
        await controller.loadHistory();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(storageCleanupControllerProvider);
    final report = state.report;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppRoutes.settings);
            }
          },
        ),
        title: const Text('Storage & Cleanup'),
      ),
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
          if (state.scanStatus == StorageScanStatus.notScanned &&
              report == null)
            _NotScannedCard(onScan: () => _scan(ref))
          else if (state.isScanning && report == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: LoadingState(message: 'Scanning storage…'),
            )
          else if (report == null)
            _UnavailableCard(
              lastError: state.lastError,
              onScan: () => _scan(ref),
            )
          else ...[
            if (state.scanStatus == StorageScanStatus.failed)
              _StaleScanBanner(report: report),
            _StorageStatsCard(state: state, report: report),
          ],
          const SizedBox(height: AppSpacing.md),
          _DatabaseCard(state: state),
          const SizedBox(height: AppSpacing.md),
          _MonthlyUsageCard(state: state),
        ],
      ),
    );
  }

  Future<void> _scan(WidgetRef ref) async {
    try {
      await ref.read(storageCleanupControllerProvider.notifier).scan();
    } catch (_) {}
  }
}

/// Truthful "never scanned" state — no fabricated zero values, just an invite
/// to run the first scan.
final class _NotScannedCard extends StatelessWidget {
  const _NotScannedCard({required this.onScan});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const EmptyState(
            icon: Icons.cloud_upload_outlined,
            title: 'Not scanned yet',
            message:
                'Your shop\'s cloud storage has not been scanned. '
                'Tap below to measure used storage and find orphaned files.',
          ),
          const SizedBox(height: AppSpacing.md),
          PrimaryButton(
            label: 'Scan storage',
            icon: Icons.refresh,
            expanded: true,
            onPressed: onScan,
          ),
        ],
      ),
    );
  }
}

/// Truthful "unavailable" state — a scan was attempted and failed, and no
/// successful values exist. Never shows zero as a real measurement.
final class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({required this.lastError, required this.onScan});

  final String? lastError;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 40,
            color: AppColors.error,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Unavailable',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            lastError ??
                'Storage information is unavailable right now. Check your '
                    'connection and try again.',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Try again',
            icon: Icons.refresh,
            expanded: true,
            onPressed: onScan,
          ),
        ],
      ),
    );
  }
}

/// Banner shown above the stats card when the latest scan failed but a
/// previous successful report is still being displayed.
final class _StaleScanBanner extends StatelessWidget {
  const _StaleScanBanner({required this.report});

  final StorageUsageReport report;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: AppColors.warning.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: AppInsets.md,
        child: Row(
          children: [
            const Icon(Icons.warning_amber_outlined, color: AppColors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Latest scan failed — showing the last successful scan from '
                '${_shortDate(report.lastScanAt)}.',
                style: textTheme.bodySmall,
              ),
            ),
          ],
        ),
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
    final textTheme = Theme.of(context).textTheme;
    // Real scan data only: no quotas or usage percentages, because the cloud
    // quota belongs to the Supabase project, not to this shop.
    final healthy = report.orphanCount == 0;
    final rows = <_StatRow>[
      _StatRow(
        label: 'Product images',
        value: '${report.imageCount}',
        icon: Icons.image_outlined,
      ),
      _StatRow(
        label: 'Image storage',
        value: formatBytes(report.usedBytes),
        icon: Icons.storage_outlined,
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cloud Storage Health',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                _StatusChip(
                  icon: healthy
                      ? Icons.check_circle_outline
                      : Icons.warning_amber_outlined,
                  label: healthy ? 'Healthy' : 'Needs attention',
                  ok: healthy,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
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
                Expanded(
                  child: SecondaryButton(
                    label: 'Dismiss',
                    icon: Icons.close,
                    onPressed: () async {
                      await ref
                          .read(storageCleanupControllerProvider.notifier)
                          .dismissNotification();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: PrimaryButton(
                    label: 'Review Files',
                    icon: Icons.cleaning_services_outlined,
                    onPressed: onReview,
                  ),
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

/// ---------------------------------------------------------------------------
/// Cloud database card: physical size, quota, per-table breakdown.
/// ---------------------------------------------------------------------------

final class _DatabaseCard extends ConsumerWidget {
  const _DatabaseCard({required this.state});

  final StorageCleanupState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final metrics = state.metrics;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: metrics == null ? null : () => _openDetail(context),
        child: Padding(
          padding: AppInsets.md,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cloud database',
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (metrics != null) const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Physical sizes are database-wide: shared tables cannot '
                'attribute bytes to one shop.',
                style: textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.isLoadingMetrics)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: LoadingState(message: 'Measuring database…'),
                )
              else if (metrics == null) ...[
                const EmptyState(
                  icon: Icons.storage_outlined,
                  title: 'Not measured yet',
                  message: 'Measure the cloud database to see sizes.',
                ),
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: 'Measure database',
                  icon: Icons.refresh,
                  expanded: true,
                  onPressed: () async {
                    try {
                      await ref
                          .read(storageCleanupControllerProvider.notifier)
                          .loadMetrics();
                    } catch (_) {}
                  },
                ),
              ] else ...[
                _StatRow(
                  label: 'Database size',
                  value: formatBytes(metrics.dbBytesTotal),
                  icon: Icons.storage_outlined,
                ),
                const SizedBox(height: AppSpacing.sm),
                _StatRow(
                  label: 'Configured limit',
                  value: metrics.storageLimitBytes == null
                      ? 'Unlimited'
                      : formatBytes(metrics.storageLimitBytes!),
                  icon: Icons.speed_outlined,
                ),
                if (metrics.usageFraction != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _StatRow(
                    label: 'Used',
                    value:
                        '${(metrics.usageFraction! * 100).toStringAsFixed(1)}%',
                    icon: Icons.percent,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: 'View tables & details',
                  icon: Icons.table_chart_outlined,
                  expanded: true,
                  onPressed: () => _openDetail(context),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => const _DatabaseDetailSheet(),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Cloud database detail: total size, database-wide explanation and a
/// table-by-table breakdown with owner-friendly names, exact row counts,
/// measured physical sizes and per-table detail.
/// ---------------------------------------------------------------------------

final class _DatabaseDetailSheet extends ConsumerWidget {
  const _DatabaseDetailSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(storageCleanupControllerProvider);
    final metrics = state.metrics;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => metrics == null
              ? const Padding(
                  padding: AppInsets.screen,
                  child: EmptyState(
                    icon: Icons.storage_outlined,
                    title: 'Not measured yet',
                    message: 'Measure the cloud database to see table details.',
                  ),
                )
              : SingleChildScrollView(
                  controller: scrollController,
                  padding: AppInsets.screen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Cloud database',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      _StatRow(
                        label: 'Total database size',
                        value: formatBytes(metrics.dbBytesTotal),
                        icon: Icons.storage_outlined,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'This is the size of the ENTIRE shared database, not '
                        'just your shop. Many shops share one database, so '
                        'physical sizes below are database-wide figures — '
                        'they cannot be attributed to a single shop or month.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Tables',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Physical size and exact row count per table '
                        '(database-wide). Tap a table for details.',
                        style: textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      for (final table in metrics.tables) ...[
                        _DatabaseTableRow(table: table),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      SecondaryButton(
                        label: 'Measure again',
                        icon: Icons.refresh,
                        expanded: true,
                        onPressed: () async {
                          try {
                            await ref
                                .read(storageCleanupControllerProvider.notifier)
                                .loadMetrics();
                          } catch (_) {}
                        },
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// One table row in the database detail sheet. Tapping opens the table detail.
final class _DatabaseTableRow extends StatelessWidget {
  const _DatabaseTableRow({required this.table});

  final DatabaseTableMetrics table;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final info = kDatabaseTableInfo[table.table];
    final friendly = info?.friendlyName ?? table.table;
    final eligible = info?.cleanupEligible ?? false;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openTable(context),
        child: Padding(
          padding: AppInsets.md,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friendly,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${table.table} · ${table.rows} rows',
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                formatBytes(table.bytes),
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _CleanupBadge(eligible: eligible),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openTable(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _TableDetailSheet(table: table),
    );
  }
}

/// Small badge showing whether monthly cleanup can remove a table's records.
final class _CleanupBadge extends StatelessWidget {
  const _CleanupBadge({required this.eligible});

  final bool eligible;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: (eligible ? AppColors.info : AppColors.error).withValues(
          alpha: 0.12,
        ),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Text(
        eligible ? 'Cleanup' : 'Kept',
        style: textTheme.bodySmall?.copyWith(
          color: eligible ? AppColors.info : AppColors.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Single table detail: what it is, what it holds, where it is used, its
/// cleanup behaviour and any safety note.
/// ---------------------------------------------------------------------------

final class _TableDetailSheet extends ConsumerStatefulWidget {
  const _TableDetailSheet({required this.table});

  final DatabaseTableMetrics table;

  @override
  ConsumerState<_TableDetailSheet> createState() => _TableDetailSheetState();
}

final class _TableDetailSheetState extends ConsumerState<_TableDetailSheet> {
  bool _busy = false;
  bool _loading = false;
  late DateTime _month;
  MonthlyUsageStats? _stats;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _month = DateTime.utc(now.year, now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  StorageCleanupController _controller() =>
      ref.read(storageCleanupControllerProvider.notifier);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final stats = await _controller().loadMonthStats(_month);
      await _controller().previewMonth(_month);
      if (mounted) setState(() => _stats = stats);
    } catch (_) {
      // Best-effort: the delete section stays hidden until stats + preview load.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectMonth(DateTime month) {
    if (month == _month) return;
    setState(() {
      _month = month;
      _stats = null;
    });
    _load();
  }

  Future<void> _delete() async {
    final info = kDatabaseTableInfo[widget.table.table];
    final category = info?.categoryKey;
    final meta = cleanupCategoryForTable(widget.table.table);
    if (category == null || meta == null) return;
    final countKey = tableCountKey(widget.table.table);
    final count = _stats?.counts[countKey] ?? 0;
    final estimated = _stats?.estimatedBytesFor(countKey) ?? 0;
    final confirmed = await confirmDestructive(
      context,
      title:
          'Delete ${_MonthlyUsageCard.monthLabel(_month)} '
          '${info!.friendlyName} records',
      subject: '$count records (est. ${formatBytes(estimated)})',
      consequence:
          'This PERMANENTLY deletes this month\u2019s ${info.friendlyName} '
          'records and the related rows (${meta.deletes.join(', ')}) from '
          'the cloud database on every device. All other months are kept. '
          'This cannot be undone.',
      confirmLabel: 'Delete forever',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      // Reuses the existing month_cleanup_atomic flow with every gate
      // intact (report confirmation, open bills, outbox, shop isolation).
      await _controller().cleanupMonth(_month, categories: [category]);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Month records deleted.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(storageCleanupControllerProvider);
    final info = kDatabaseTableInfo[widget.table.table];
    final friendly = info?.friendlyName ?? widget.table.table;
    final eligible = info?.cleanupEligible ?? false;
    final meta = cleanupCategoryForTable(widget.table.table);
    final countKey = tableCountKey(widget.table.table);
    final count = _stats?.counts[countKey] ?? 0;
    final estimated = _stats?.estimatedBytesFor(countKey) ?? 0;
    final preview = state.previewMonth == _month ? state.preview : null;
    final canDelete =
        eligible &&
        meta != null &&
        !_loading &&
        preview != null &&
        preview.reportConfirmed &&
        !preview.alreadyCleaned &&
        !(preview.openBillCount > 0 && meta.key == 'sales');
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: AppInsets.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  friendly,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  widget.table.table,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                _DetailBlock(
                  icon: Icons.info_outline,
                  title: 'What is this?',
                  body: info?.description ?? 'No description available.',
                ),
                _DetailBlock(
                  icon: Icons.list_alt,
                  title: 'What does it contain?',
                  body: switch (info?.deletes) {
                    null => 'This table is not deleted by monthly cleanup.',
                    final deletes =>
                      'Monthly cleanup deletes: '
                          '${deletes.join(', ')}.',
                  },
                ),
                _DetailBlock(
                  icon: Icons.apps_outlined,
                  title: 'Where is it used?',
                  body: info?.feature ?? 'Across the app.',
                ),
                _DetailBlock(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Cleanup behavior',
                  body: (info?.cleanupEligible ?? false)
                      ? 'Monthly cleanup can remove its in-month records.'
                      : 'Never removed by monthly cleanup — kept for safety.',
                ),
                if (info?.safetyNote != null)
                  _DetailBlock(
                    icon: Icons.shield_outlined,
                    title: 'Safety note',
                    body: info!.safetyNote!,
                    accent: AppColors.warning,
                  ),
                const SizedBox(height: AppSpacing.lg),
                _StatRow(
                  label: 'Physical size (database-wide)',
                  value: formatBytes(widget.table.bytes),
                  icon: Icons.storage_outlined,
                ),
                const SizedBox(height: AppSpacing.xs),
                _StatRow(
                  label: 'Rows (database-wide)',
                  value: '${widget.table.rows}',
                  icon: Icons.table_chart_outlined,
                ),
                if (eligible && meta != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'Delete this month\u2019s records',
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _MonthSelector(
                    selected: _month,
                    months: [
                      DateTime.utc(
                        DateTime.now().toUtc().year,
                        DateTime.now().toUtc().month,
                      ),
                      ...state.activeMonths,
                      for (final s in state.snapshots) s.month,
                    ],
                    onChanged: _selectMonth,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                      child: LoadingState(message: 'Loading month…'),
                    )
                  else if (preview == null)
                    const EmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'Month unavailable',
                      message:
                          'Could not load this month. Check your connection '
                          'and try again.',
                    )
                  else ...[
                    _StatRow(
                      label: 'Selected month',
                      value: _MonthlyUsageCard.monthLabel(_month),
                      icon: Icons.calendar_month_outlined,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _StatRow(
                      label: 'Record count',
                      value: '$count',
                      icon: Icons.inventory_2_outlined,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _StatRow(
                      label: 'Estimated logical size',
                      value: formatBytes(estimated),
                      icon: Icons.storage_outlined,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Also deletes: ${meta.deletes.join(', ')}',
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (preview.openBillCount > 0 && meta.key == 'sales') ...[
                      const SizedBox(height: AppSpacing.sm),
                      _OpenBillWarning(count: preview.openBillCount),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      preview.reportConfirmed
                          ? (preview.alreadyCleaned
                                ? 'This month was already cleaned.'
                                : 'Deletion is permanent and month-scoped. '
                                      'Other months are kept.')
                          : 'Cleanup is locked: confirm the monthly report '
                                'first.',
                      style: textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    PrimaryButton(
                      label: 'Delete this month\u2019s records',
                      icon: Icons.delete_forever_outlined,
                      loading: _busy,
                      expanded: true,
                      onPressed: canDelete ? _delete : null,
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Month picker for the per-table delete action.
final class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.selected,
    required this.months,
    required this.onChanged,
  });

  final DateTime selected;
  final List<DateTime> months;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final unique = <DateTime>{
      for (final month in months) DateTime.utc(month.year, month.month),
    }.toList()..sort();
    final ordered = unique.reversed.toList();
    return DropdownButton<DateTime>(
      value: selected,
      isExpanded: true,
      items: [
        for (final month in ordered)
          DropdownMenuItem<DateTime>(
            value: month,
            child: Text(_MonthlyUsageCard.monthLabel(month)),
          ),
      ],
      onChanged: (month) {
        if (month != null) onChanged(month);
      },
    );
  }
}

/// A titled detail block used by the table detail sheet.
final class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.icon,
    required this.title,
    required this.body,
    this.accent,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = accent ?? AppColors.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Monthly usage card: ledger history with per-month detail.
/// ---------------------------------------------------------------------------

final class _MonthlyUsageCard extends ConsumerWidget {
  const _MonthlyUsageCard({required this.state});

  final StorageCleanupState state;

  static const List<String> _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String monthLabel(DateTime month) =>
      '${_monthName(month.month)} ${month.year}';

  static String _monthName(int month) => _monthNames[month - 1];

  /// Months to offer: ledger history, locally active months and the current
  /// month on top (a month without a snapshot yet can still be refreshed on
  /// demand).
  static List<DateTime> _offeredMonths(
    List<MonthlySnapshot> snapshots,
    List<DateTime> activeMonths,
  ) {
    final now = DateTime.now().toUtc();
    final current = DateTime.utc(now.year, now.month);
    final months = <DateTime>{current};
    for (final snapshot in snapshots) {
      months.add(DateTime.utc(snapshot.month.year, snapshot.month.month));
    }
    for (final month in activeMonths) {
      months.add(DateTime.utc(month.year, month.month));
    }
    final ordered = months.toList()..sort();
    return ordered.reversed.take(12).toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final months = _offeredMonths(state.snapshots, state.activeMonths);
    final byMonth = {
      for (final snapshot in state.snapshots)
        DateTime.utc(snapshot.month.year, snapshot.month.month): snapshot,
    };
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
            Text(
              'Monthly database usage',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Row counts are exact. Sizes are logical estimates, never '
              'exact physical attribution.',
              style: textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final month in months) ...[
              _MonthRow(
                month: month,
                snapshot: byMonth[month],
                onTap: () => _openMonth(context, month),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openMonth(BuildContext context, DateTime month) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _MonthDetailSheet(month: month),
    );
  }
}

final class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.month,
    required this.snapshot,
    required this.onTap,
  });

  final DateTime month;
  final MonthlySnapshot? snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final total = snapshot?.counts.values.fold(0, (a, b) => a + b);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _MonthlyUsageCard.monthLabel(month),
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    snapshot == null
                        ? 'No snapshot yet — open to refresh.'
                        : '$total records · est. ${formatBytes(snapshot!.logicalBytesEst)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Month detail sheet: stats, monthly report, preview and month cleanup.
/// ---------------------------------------------------------------------------

final class _MonthDetailSheet extends ConsumerStatefulWidget {
  const _MonthDetailSheet({required this.month});

  /// First-of-month UTC cookie.
  final DateTime month;

  @override
  ConsumerState<_MonthDetailSheet> createState() => _MonthDetailSheetState();
}

final class _MonthDetailSheetState extends ConsumerState<_MonthDetailSheet> {
  bool _busy = false;
  MonthlyUsageStats? _stats;
  bool _confirmingReport = false;
  ({bool snapshotSaved, bool reportConfirmed, bool alreadyCleaned})? _status;

  static const Map<String, String> _categoryLabels = {
    'sales': 'Sales',
    'saleItems': 'Sale items',
    'salePayments': 'Sale payments',
    'customerPayments': 'Customer payments',
    'purchases': 'Purchases',
    'purchaseItems': 'Purchase items',
    'expenses': 'Expenses',
    'stockMovements': 'Stock movements',
    'dailyClosings': 'Daily closings',
    'staffAttendance': 'Attendance',
    'staffAdvances': 'Staff advances',
    'staffDailySalaries': 'Daily salaries',
    'staffMonthlySalaries': 'Monthly salaries',
    'orphanImages': 'Orphan images',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshStats();
      _loadPreview();
      _loadStatus();
    });
  }

  StorageCleanupController _controller() =>
      ref.read(storageCleanupControllerProvider.notifier);

  void _fail(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(error.toString())));
  }

  Future<void> _refreshStats() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final stats = await _controller().refreshMonth(widget.month);
      if (mounted) setState(() => _stats = stats);
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadPreview() async {
    try {
      await _controller().previewMonth(widget.month);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _loadStatus() async {
    try {
      final status = await _controller().loadMonthStatus(widget.month);
      if (mounted) setState(() => _status = status);
    } catch (_) {
      // Status is best-effort; the preview flags cover report/cleaned.
    }
  }

  /// Builds the management-report PDF for exactly this month, saves it
  /// on-device and offers sharing — reusing the month-end report workflow.
  Future<void> _generateReport() async {
    setState(() => _busy = true);
    try {
      final month = widget.month;
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 0);
      final data = await ManagementReportLoader.from(
        ref,
      ).load(fromLocal: start, toLocal: end);
      if (!mounted) return;
      final bytes = await buildManagementReportPdf(data);
      final store = await ref.read(backupFileStoreProvider.future);
      final info = await store.writeBytes(
        defaultManagementReportFileName(DateTime.now()),
        bytes,
      );
      if (!mounted) return;
      await showReportPdfPreview(
        context,
        bytes: bytes,
        fileName: info.name,
        filePath: info.path,
        detailLine: _MonthlyUsageCard.monthLabel(month),
        shareSubject: 'Monthly report',
      );
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmReport() async {
    setState(() => _confirmingReport = true);
    try {
      await _controller().confirmReport(widget.month);
    } catch (error) {
      _fail(error);
    } finally {
      if (mounted) setState(() => _confirmingReport = false);
    }
  }

  Future<void> _openCleanupPreview(MonthCleanupPreview preview) async {
    final state = ref.read(storageCleanupControllerProvider);
    final selected = state.cleanupCategories
        .where((c) => state.selectedCategories.contains(c.key))
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _CleanupPreviewSheet(
        month: widget.month,
        preview: preview,
        categories: selected,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final state = ref.watch(storageCleanupControllerProvider);
    final preview = state.previewMonth == widget.month ? state.preview : null;
    final stats = _stats;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: AppInsets.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _MonthlyUsageCard.monthLabel(widget.month),
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Record counts are exact. Sizes are logical estimates, '
                  'never exact physical attribution.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _MonthStatusChips(status: _status, preview: preview),
                const SizedBox(height: AppSpacing.md),
                if (_busy && stats == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: LoadingState(message: 'Loading month…'),
                  )
                else if (stats != null) ...[
                  _StatRow(
                    label: 'Records generated',
                    value: '${stats.totalRecords}',
                    icon: Icons.inventory_2_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _StatRow(
                    label: 'Estimated logical size',
                    value: formatBytes(stats.logicalBytesEst),
                    icon: Icons.storage_outlined,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Divider(height: AppSpacing.md),
                  for (final entry in stats.counts.entries) ...[
                    _StatRow(
                      label: _categoryLabels[entry.key] ?? entry.key,
                      value: '${entry.value}',
                      icon: Icons.table_chart_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Refresh stats',
                        icon: Icons.refresh,
                        onPressed: _busy ? null : _refreshStats,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Monthly report',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  preview?.reportConfirmed == true
                      ? 'Report confirmed for this month — cleanup is unlocked.'
                      : 'Generate the month\u2019s PDF report first, then '
                            'confirm it is saved. Cleanup stays locked until then.',
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Generate report',
                        icon: Icons.picture_as_pdf_outlined,
                        onPressed: _busy ? null : _generateReport,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Confirm saved',
                        icon: Icons.verified_outlined,
                        loading: _confirmingReport,
                        onPressed:
                            (_busy ||
                                _confirmingReport ||
                                preview?.reportConfirmed == true)
                            ? null
                            : _confirmReport,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Month cleanup (permanent)',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (state.isLoadingPreview)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: LoadingState(message: 'Loading preview…'),
                  )
                else if (preview == null) ...[
                  SecondaryButton(
                    label: 'Preview deletion',
                    icon: Icons.preview_outlined,
                    expanded: true,
                    onPressed: _busy ? null : _loadPreview,
                  ),
                ] else ...[
                  if (preview.openBillCount > 0) ...[
                    _OpenBillWarning(count: preview.openBillCount),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  _CleanupCategoryList(
                    categories: state.cleanupCategories,
                    selected: state.selectedCategories,
                    onToggle: _controller().toggleCleanupCategory,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _CleanupSelectedSummary(
                    categories: state.cleanupCategories,
                    selected: state.selectedCategories,
                    onSelectAll: _controller().selectAllCleanupCategories,
                    onClear: _controller().clearCleanupSelection,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    preview.alreadyCleaned
                        ? 'This month was already cleaned.'
                        : preview.reportConfirmed
                        ? 'Deletion is permanent and month-scoped. Master '
                              'data, payee-keyed expense payments, the sync '
                              'queue and bookkeeping are never touched.'
                        : 'Cleanup is locked: confirm the monthly report first.',
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  PrimaryButton(
                    label: preview.alreadyCleaned
                        ? 'Already cleaned'
                        : 'Preview deletion',
                    icon: Icons.preview_outlined,
                    loading: _busy || state.isDeleting,
                    expanded: true,
                    onPressed:
                        (_busy ||
                            state.isDeleting ||
                            preview.alreadyCleaned ||
                            !preview.reportConfirmed ||
                            state.selectedCategories.isEmpty ||
                            (preview.openBillCount > 0 &&
                                state.selectedCategories.contains('sales')))
                        ? null
                        : () => _openCleanupPreview(preview),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SecondaryButton(
                    label: 'Refresh preview',
                    icon: Icons.refresh,
                    expanded: true,
                    onPressed: _busy ? null : _loadPreview,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Month status chips: snapshot saved, report confirmed, already cleaned.
/// ---------------------------------------------------------------------------

final class _MonthStatusChips extends StatelessWidget {
  const _MonthStatusChips({required this.status, required this.preview});

  final ({bool snapshotSaved, bool reportConfirmed, bool alreadyCleaned})?
  status;
  final MonthCleanupPreview? preview;

  @override
  Widget build(BuildContext context) {
    final reportConfirmed =
        preview?.reportConfirmed ?? status?.reportConfirmed ?? false;
    final alreadyCleaned =
        preview?.alreadyCleaned ?? status?.alreadyCleaned ?? false;
    final snapshotSaved = status?.snapshotSaved ?? false;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _StatusChip(
          icon: snapshotSaved ? Icons.check_circle_outline : Icons.help_outline,
          label: snapshotSaved ? 'Snapshot saved' : 'No snapshot',
          ok: snapshotSaved,
        ),
        _StatusChip(
          icon: reportConfirmed
              ? Icons.verified_outlined
              : Icons.pending_outlined,
          label: reportConfirmed ? 'Report confirmed' : 'Report not confirmed',
          ok: reportConfirmed,
        ),
        _StatusChip(
          icon: alreadyCleaned
              ? Icons.delete_sweep_outlined
              : Icons.calendar_today_outlined,
          label: alreadyCleaned ? 'Already cleaned' : 'Not cleaned',
          ok: !alreadyCleaned,
        ),
      ],
    );
  }
}

final class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = ok ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Open-bill warning: cleanup must not delete unpaid/partially-paid bills.
/// ---------------------------------------------------------------------------

final class _OpenBillWarning extends StatelessWidget {
  const _OpenBillWarning({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: AppInsets.md,
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_outlined, color: AppColors.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'This month has $count unpaid or partially-paid customer '
              'bill${count == 1 ? '' : 's'}. Bills/Sales cannot be cleaned '
              'while they carry outstanding — settle or collect them first to '
              'protect customer dues.',
              style: textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Cleanup category checkbox list.
/// ---------------------------------------------------------------------------

final class _CleanupCategoryList extends StatelessWidget {
  const _CleanupCategoryList({
    required this.categories,
    required this.selected,
    required this.onToggle,
  });

  final List<CleanupCategory> categories;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final category in categories)
          _CleanupCategoryTile(
            category: category,
            selected: selected.contains(category.key),
            onToggle: () => onToggle(category.key),
          ),
      ],
    );
  }
}

final class _CleanupCategoryTile extends StatelessWidget {
  const _CleanupCategoryTile({
    required this.category,
    required this.selected,
    required this.onToggle,
  });

  final CleanupCategory category;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: (_) => onToggle()),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    category.description,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${category.count} records · est. '
                    '${formatBytes(category.estimatedBytes)}',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Deletes: ${category.deletes.join(', ')}',
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Live selected summary: categories, total records, estimated logical size.
/// ---------------------------------------------------------------------------

final class _CleanupSelectedSummary extends StatelessWidget {
  const _CleanupSelectedSummary({
    required this.categories,
    required this.selected,
    required this.onSelectAll,
    required this.onClear,
  });

  final List<CleanupCategory> categories;
  final Set<String> selected;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final chosen = categories.where((c) => selected.contains(c.key)).toList();
    final totalRecords = chosen.fold(0, (sum, c) => sum + c.count);
    final totalBytes = chosen.fold(0, (sum, c) => sum + c.estimatedBytes);
    return Container(
      padding: AppInsets.md,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${chosen.length} of ${categories.length} categories selected',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$totalRecords records · est. ${formatBytes(totalBytes)} logical',
            style: textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Select all',
                  icon: Icons.select_all,
                  onPressed: onSelectAll,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Clear',
                  icon: Icons.clear_all,
                  onPressed: onClear,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Cleanup preview sheet: exactly what the selected categories delete, the
/// totals, and the explicit list of what will NOT be deleted.
/// ---------------------------------------------------------------------------

final class _CleanupPreviewSheet extends ConsumerStatefulWidget {
  const _CleanupPreviewSheet({
    required this.month,
    required this.preview,
    required this.categories,
  });

  final DateTime month;
  final MonthCleanupPreview preview;
  final List<CleanupCategory> categories;

  @override
  ConsumerState<_CleanupPreviewSheet> createState() =>
      _CleanupPreviewSheetState();
}

final class _CleanupPreviewSheetState
    extends ConsumerState<_CleanupPreviewSheet> {
  bool _busy = false;

  static const List<String> _notDeleted = [
    'Master data: products, variants, categories, customers, suppliers, '
        'staff accounts, offers, recipes',
    'Payee-keyed expense payments',
    'Sync queue (durable outbox)',
    'Bookkeeping: monthly snapshots, report confirmations, cleanup markers',
    'Unpaid or partially-paid customer bills',
    'Orphan files created in other months',
  ];

  Future<void> _confirmDelete() async {
    final totalRecords = widget.categories.fold(0, (sum, c) => sum + c.count);
    final totalBytes = widget.categories.fold(
      0,
      (sum, c) => sum + c.estimatedBytes,
    );
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete ${_MonthlyUsageCard.monthLabel(widget.month)} data',
      subject:
          '$totalRecords records across ${widget.categories.length} categories '
          '(est. ${formatBytes(totalBytes)})',
      consequence:
          'This PERMANENTLY deletes the selected month\u2019s records from '
          'the cloud database on every device. Master data, expense payments, '
          'the sync queue and bookkeeping are kept. Physical disk space may '
          'not shrink immediately (vacuum). This cannot be undone.',
      confirmLabel: 'Delete forever',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(storageCleanupControllerProvider.notifier)
          .cleanupMonth(widget.month);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Month cleaned up.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final totalRecords = widget.categories.fold(0, (sum, c) => sum + c.count);
    final totalBytes = widget.categories.fold(
      0,
      (sum, c) => sum + c.estimatedBytes,
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: AppInsets.screen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Preview deletion',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  _MonthlyUsageCard.monthLabel(widget.month),
                  style: textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Selected categories',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final category in widget.categories) ...[
                  _StatRow(
                    label: category.label,
                    value:
                        '${category.count} records · est. ${formatBytes(category.estimatedBytes)}',
                    icon: Icons.delete_outline,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const Divider(height: AppSpacing.md),
                _StatRow(
                  label: 'Total records',
                  value: '$totalRecords',
                  icon: Icons.inventory_2_outlined,
                ),
                const SizedBox(height: AppSpacing.xs),
                _StatRow(
                  label: 'Total estimated logical size',
                  value: formatBytes(totalBytes),
                  icon: Icons.storage_outlined,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Will NOT be deleted',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                for (final item in _notDeleted) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        size: 18,
                        color: AppColors.success,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          item,
                          style: textTheme.bodySmall?.copyWith(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
                const SizedBox(height: AppSpacing.lg),
                PrimaryButton(
                  label: 'Delete $totalRecords records',
                  icon: Icons.delete_forever_outlined,
                  loading: _busy,
                  expanded: true,
                  onPressed: _busy ? null : _confirmDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
