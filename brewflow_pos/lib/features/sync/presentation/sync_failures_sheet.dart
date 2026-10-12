import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/features/sync/domain/sync_failures.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_status_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Failures Sheet
///
/// Detail panel behind the dashboard "N failed" badge. Lists every FAILED
/// outbox entry with a human-readable reason and a safe per-entry retry
/// (the change is requeued as PENDING and re-pushed idempotently). Raw
/// gateway errors and payloads are never shown.
/// ---------------------------------------------------------------------------

/// Opens [SyncFailuresSheet] as a bounded modal bottom sheet.
Future<void> showSyncFailuresSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => const SyncFailuresSheet(),
  );
}

final class SyncFailuresSheet extends ConsumerWidget {
  const SyncFailuresSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failures = ref.watch(syncFailuresProvider);
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final entries = failures.value ?? const <SyncFailureEntry>[];
    // Retry-all only acts on transient failures; when every visible entry
    // is blocked there is nothing a bulk retry could do, so the footer is
    // hidden and the blocked rows (with their reasons) stay on screen.
    final hasRetryable = entries.any(
      (entry) => entry.kind == SyncFailureKind.retryable,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppInsets.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Failed changes',
                      style: textTheme.titleMedium?.copyWith(
                        color: appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      entries.isEmpty
                          ? 'Changes that could not reach the cloud'
                          : '${entries.length} change${entries.length == 1 ? '' : 's'} could not reach the cloud',
                      style: textTheme.bodySmall?.copyWith(
                        color: appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(child: _body(context, ref, failures)),
              if (entries.isNotEmpty && hasRetryable)
                Padding(
                  padding: AppInsets.screen,
                  child: PrimaryButton(
                    label: 'Retry all',
                    icon: Icons.refresh,
                    expanded: true,
                    loading: failures.isLoading,
                    onPressed: failures.isLoading
                        ? null
                        : () => ref
                              .read(syncFailuresProvider.notifier)
                              .retryAll(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<SyncFailureEntry>> failures,
  ) {
    return failures.when(
      loading: () => const LoadingState(message: 'Loading failed changes…'),
      error: (_, _) => ErrorState(
        message: 'Could not load failed changes.',
        onRetry: () => ref.read(syncFailuresProvider.notifier).reload(),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return const EmptyState(
            icon: Icons.cloud_done_outlined,
            title: 'No failed changes',
            message: 'Everything synced to the cloud.',
          );
        }
        return ListView.separated(
          padding: AppInsets.screen,
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) => _FailureRow(
            entry: entries[index],
            busy: failures.isLoading,
            onRetry: () => ref
                .read(syncFailuresProvider.notifier)
                .retryOne(entries[index].id),
          ),
        );
      },
    );
  }
}

/// One failed entry: what change it was, why it failed (friendly), when it
/// last attempted, and a retry when the failure is transient.
final class _FailureRow extends StatelessWidget {
  const _FailureRow({
    required this.entry,
    required this.busy,
    required this.onRetry,
  });

  final SyncFailureEntry entry;

  /// True while a retry/reload is in flight (buttons disabled).
  final bool busy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final blocked = entry.kind == SyncFailureKind.blocked;
    final accent = blocked ? AppColors.warning : AppColors.error;

    final lastLine = entry.lastAttemptAt == null
        ? (blocked ? 'Blocked by the server' : 'Waiting to retry')
        : 'Last attempt ${formatDateTime(entry.lastAttemptAt!)}';

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: AppBorderRadius.sm,
              ),
              child: Icon(
                blocked ? Icons.block_outlined : Icons.cloud_off_outlined,
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.bodyMedium?.copyWith(
                      color: appColors.charcoal,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    entry.reason,
                    style: textTheme.bodySmall?.copyWith(
                      color: appColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lastLine,
                    style: textTheme.labelSmall?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (!blocked)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm),
                child: SecondaryButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  minHeight: 36,
                  onPressed: busy ? null : onRetry,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
