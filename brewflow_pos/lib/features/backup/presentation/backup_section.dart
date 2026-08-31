import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/app/widgets/context_actions.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Data & Backup Section
///
/// [BackupSectionCard] is the tablet/desktop card; [MobileBackupSection] is
/// the phone variant. Both expose two actions:
///   • Create backup  → snapshot the shop data to a JSON envelope in the
///     on-device `backups/` folder and offer to share it.
///   • Restore backup → pick a stored backup, preview it and replace the
///     current data transactionally after confirmation.
///
/// Provider reads are deliberately lazy (inside button handlers, via
/// `ref.read`): opening the database or the documents/backups directory must
/// never happen during a widget build.
/// ---------------------------------------------------------------------------

/// Tablet / desktop "Data & Backup" section card.
final class BackupSectionCard extends ConsumerWidget {
  const BackupSectionCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBackup = ref.watch(canProvider(Permission.settings));
    if (!canBackup) return const SizedBox.shrink();
    return const _BackupCard();
  }
}

/// Phone "Data & Backup" section, matching the compact settings layout.
final class MobileBackupSection extends ConsumerWidget {
  const MobileBackupSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBackup = ref.watch(canProvider(Permission.settings));
    if (!canBackup) return const SizedBox.shrink();
    return const _MobileBackupSection();
  }
}

/// Shared expanded-layout card body.
final class _BackupCard extends ConsumerWidget {
  const _BackupCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return SectionCard(
      title: 'Data & Backup',
      subtitle: 'Snapshot your shop data or restore it from a saved backup.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Backups are saved as a file on this device. Restoring replaces '
            'all current products, sales, customers and other data — store '
            'backup files somewhere safe.',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  label: 'Create backup',
                  icon: Icons.cloud_upload_outlined,
                  minHeight: 44,
                  onPressed: () => _createBackup(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SecondaryButton(
                  label: 'Restore backup',
                  icon: Icons.settings_backup_restore_outlined,
                  minHeight: 44,
                  onPressed: () => _restoreBackup(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shared phone-layout section body.
final class _MobileBackupSection extends ConsumerWidget {
  const _MobileBackupSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            'Data & Backup'.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        AppCard(
          padding: AppInsets.sm,
          borderRadius: AppBorderRadius.md,
          shadows: const [AppShadows.xs],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Backups are saved as a file on this device. Restoring '
                'replaces all current products, sales, customers and other '
                'data — store backup files somewhere safe.',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                label: 'Create backup',
                icon: Icons.cloud_upload_outlined,
                expanded: true,
                minHeight: 44,
                onPressed: () => _createBackup(context, ref),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Restore backup',
                icon: Icons.settings_backup_restore_outlined,
                expanded: true,
                minHeight: 44,
                onPressed: () => _restoreBackup(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Builds a backup export, saves it to the on-device store and shows a
/// confirmation dialog with an optional share action.
Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final repository = ref.read(backupRepositoryProvider);
    final envelope = await repository.buildBackup();
    final store = await ref.read(backupFileStoreProvider.future);
    final info = await store.write(
      backupFileName(DateTime.now()),
      envelope.encodeJson(),
    );
    if (!context.mounted) return;
    final textTheme = Theme.of(context).textTheme;

    final summary = backupSummaryLine(envelope.summary);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.cloud_done_outlined, color: AppColors.primary),
        title: const Text('Backup created'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              info.name,
              style: textTheme.titleSmall?.copyWith(
                color: context.appColors.charcoal,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              summary,
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Saved on this device. Share it to keep a copy elsewhere.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          SecondaryButton(
            label: 'Close',
            minHeight: 40,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          PrimaryButton(
            label: 'Share backup',
            minHeight: 40,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareBackup(context, ref, store, info.name);
            },
          ),
        ],
      ),
    );
  } on BackupFailure catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not create the backup right now.')),
      );
  }
}

/// Shares an already-written backup file through the system share sheet.
Future<void> _shareBackup(
  BuildContext context,
  WidgetRef ref,
  BackupFileStore store,
  String fileName,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final contents = await store.readFile(fileName);
    await ref
        .read(shareServiceProvider)
        .shareText(subject: 'BrewFlow backup', text: contents);
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not share the backup right now.')),
      );
  }
}

/// Walks the user through picking, previewing and confirming a restore.
Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final store = await ref.read(backupFileStoreProvider.future);
    final files = await store.listFiles();
    if (!context.mounted) return;
    if (files.isEmpty) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No backups found on this device.')),
        );
      return;
    }

    final selected = await showDialog<BackupFileInfo>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore_outlined, color: AppColors.primary),
        title: const Text('Restore backup'),
        content: SizedBox(
          width: 420,
          height: 320,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: files.length,
            separatorBuilder: (separatorContext, index) =>
                Divider(height: 1, color: context.appColors.divider),
            itemBuilder: (_, index) {
              final file = files[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(file.name),
                subtitle: Text(
                  '${_formatSize(file.sizeBytes)} · '
                  '${_formatTimestamp(file.modifiedAt)}',
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => Navigator.of(dialogContext).pop(file),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (selected == null || !context.mounted) return;

    final contents = await store.readFile(selected.name);
    final envelope = BackupEnvelope.fromJsonString(contents);
    if (!context.mounted) return;

    final confirmed = await confirmDestructive(
      context,
      title: 'Restore anything on this device?',
      subject: '${selected.name} · ${_formatTimestamp(envelope.createdAt)}',
      consequence:
          'This will replace all current products, sales, customers, '
          'purchases and other data on this device with the backup '
          '(${backupSummaryLine(envelope.summary)}). This cannot be undone.',
      confirmLabel: 'Restore',
    );
    if (!confirmed || !context.mounted) return;

    await ref.read(backupRepositoryProvider).restoreBackup(envelope);
    if (!context.mounted) return;
    _invalidateAfterRestore(ref);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Backup restored.')));
  } on BackupFailure catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Could not restore the backup right now.'),
        ),
      );
  }
}

/// Refreshes every screen that caches shop data after a successful restore.
void _invalidateAfterRestore(WidgetRef ref) {
  ref.invalidate(categoriesProvider);
  ref.invalidate(productsProvider);
  ref.invalidate(customersProvider);
  ref.invalidate(suppliersProvider);
  ref.invalidate(purchasesProvider);
  ref.invalidate(expensesProvider);
  ref.invalidate(ordersListProvider);
  ref.invalidate(posProductsProvider);
  ref.invalidate(posCustomersProvider);
  ref.invalidate(dashboardControllerProvider);
  ref.invalidate(reportsControllerProvider);
}

/// Compact human-readable row counts, e.g. '4 products, 3 customers'.
String backupSummaryLine(BackupSummary summary) {
  final parts = <String?>[
    _count(summary.categories, 'category', 'categories'),
    _count(summary.products, 'product', 'products'),
    _count(summary.productVariants, 'variant', 'variants'),
    _count(summary.customers, 'customer', 'customers'),
    _count(summary.suppliers, 'supplier', 'suppliers'),
    _count(summary.sales, 'sale', 'sales'),
    _count(summary.purchases, 'purchase', 'purchases'),
    _count(summary.expenses, 'expense', 'expenses'),
    _count(summary.stockMovements, 'stock movement', 'stock movements'),
  ].whereType<String>().join(', ');
  return parts.isEmpty ? 'No data' : parts;
}

/// Widget-layer permission gate mirroring [requirePermission]: reachable UI
/// regardless, the action still refuses when holding no SETTINGS capability.
void _guardBackupAccess(WidgetRef ref) {
  if (!ref.read(canProvider(Permission.settings))) {
    throw const PermissionDeniedFailure();
  }
}

String? _count(int count, String singular, String plural) {
  if (count <= 0) return null;
  return '$count ${count == 1 ? singular : plural}';
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

String _formatTimestamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
