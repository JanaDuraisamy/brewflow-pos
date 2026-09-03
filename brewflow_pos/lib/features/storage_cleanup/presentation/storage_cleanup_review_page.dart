import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/state_views.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/storage_cleanup/domain/storage_cleanup_models.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/owner_storage_usage_page.dart';
import 'package:brewflow_pos/features/storage_cleanup/presentation/storage_cleanup_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owner-confirmed cleanup review.
///
/// Lists the orphan (unreferenced) candidates found by the last scan. The
/// owner must explicitly confirm — tapping the delete action opens a
/// confirmation dialog listing the exact count/size; only then are the
/// selected objects permanently deleted (server-side, re-verifying each path).
/// Nothing is deleted implicitly on this screen.
final class StorageCleanupReviewPage extends ConsumerStatefulWidget {
  const StorageCleanupReviewPage({super.key, this.report});

  final StorageUsageReport? report;

  @override
  ConsumerState<StorageCleanupReviewPage> createState() =>
      _StorageCleanupReviewPageState();
}

final class _StorageCleanupReviewPageState
    extends ConsumerState<StorageCleanupReviewPage> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final report =
        widget.report ?? ref.watch(storageCleanupControllerProvider).report;
    final state = ref.watch(storageCleanupControllerProvider);
    final textTheme = Theme.of(context).textTheme;

    final orphans = report?.orphanPaths ?? const <String>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Review files')),
      body: report == null
          ? const Center(child: LoadingState(message: 'Loading…'))
          : ListView(
              padding: AppInsets.screen,
              children: [
                PageHeader(
                  title: 'Orphaned product images',
                  subtitle: orphans.isEmpty
                      ? 'Nothing to clean up right now.'
                      : '${orphans.length} unreferenced image(s) '
                            '(${formatBytes(report.reclaimableBytes)}) were found. '
                            'Select and confirm to permanently delete them.',
                ),
                if (orphans.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: Theme.of(context).dividerColor,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: AppInsets.md,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final path in orphans)
                            CheckboxListTile(
                              value: _selected.contains(path),
                              dense: true,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: Text(
                                _shortName(path),
                                style: textTheme.bodyMedium,
                              ),
                              subtitle: Text(
                                path,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.bodySmall?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              onChanged: (on) {
                                setState(() {
                                  if (on == true) {
                                    _selected.add(path);
                                  } else {
                                    _selected.remove(path);
                                  }
                                });
                              },
                            ),
                          const SizedBox(height: AppSpacing.sm),
                          PrimaryButton(
                            label: _selected.isEmpty
                                ? 'Select files to delete'
                                : 'Delete ${_selected.length} file(s)',
                            icon: Icons.delete_outline,
                            expanded: true,
                            onPressed: _selected.isEmpty
                                ? null
                                : () => _confirmDelete(context),
                          ),
                          if (state.lastError != null) ...[
                            const SizedBox(height: AppSpacing.sm),
                            ErrorState(message: state.lastError!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final paths = _selected.toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: Text(
          'This will permanently delete ${paths.length} unreferenced '
          'product image(s) from cloud storage. This cannot be undone. '
          'Images still linked to a product are never deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(
      // ignore: use_build_context_synchronously
      context,
    );
    try {
      final controller = ref.read(storageCleanupControllerProvider.notifier);
      final result = await controller.deleteOrphans(paths);
      setState(() => _selected.clear());
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              result.deletedCount > 0
                  ? 'Deleted ${result.deletedCount} orphaned image(s).'
                  : 'Nothing was deleted (files were already in use or gone).',
            ),
          ),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Cleanup failed. Please try again.')),
        );
    }
  }

  String _shortName(String path) {
    final segments = path.split('/');
    return segments.isNotEmpty ? segments.last : path;
  }
}
