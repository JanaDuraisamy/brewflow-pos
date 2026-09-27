import 'dart:convert';
import 'dart:typed_data';

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
import 'package:brewflow_pos/features/backup/data/backup_csv_export.dart';
import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/data/backup_package.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/inventory/data/product_image_store.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:brewflow_pos/features/reports/domain/management_report_models.dart';
import 'package:brewflow_pos/features/reports/presentation/management_report_loader.dart';
import 'package:brewflow_pos/features/reports/data/management_report_pdf.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Data & Backup Section
///
/// [BackupSectionCard] is the tablet/desktop card; [MobileBackupSection] is
/// the phone variant. Both expose:
///   • Create backup  → snapshot the shop data to a JSON envelope in the
///     on-device `backups/` folder and offer to share it.
///   • Restore backup → pick a stored backup (JSON or ZIP package), preview
///     it and replace the current data transactionally after confirmation.
///   • Export ZIP     → self-contained package (JSON + images + metadata).
///   • Export CSV     → human/Excel-readable sheets (export-only, never a
///     restorable backup).
///   • PDF report     → date-range management report (export-only).
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
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  label: 'Export ZIP',
                  icon: Icons.folder_zip_outlined,
                  minHeight: 44,
                  onPressed: () => _exportPackage(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SecondaryButton(
                  label: 'Export CSV',
                  icon: Icons.table_chart_outlined,
                  minHeight: 44,
                  onPressed: () => _exportCsv(context, ref),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: SecondaryButton(
                  label: 'PDF report',
                  icon: Icons.picture_as_pdf_outlined,
                  minHeight: 44,
                  onPressed: () => _exportPdf(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'ZIP is a restorable package. CSV is a readable export only. '
            'The PDF report is a business summary — it cannot be restored.',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
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
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Export ZIP',
                icon: Icons.folder_zip_outlined,
                expanded: true,
                minHeight: 44,
                onPressed: () => _exportPackage(context, ref),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Export CSV',
                icon: Icons.table_chart_outlined,
                expanded: true,
                minHeight: 44,
                onPressed: () => _exportCsv(context, ref),
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'PDF report',
                icon: Icons.picture_as_pdf_outlined,
                expanded: true,
                minHeight: 44,
                onPressed: () => _exportPdf(context, ref),
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
        .shareText(subject: 'JiggarTea Bill backup', text: contents);
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not share the backup right now.')),
      );
  }
}

/// Builds the self-contained ZIP package (JSON + images + metadata), saves
/// it to the on-device store and offers to share it.
Future<void> _exportPackage(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final repository = ref.read(backupRepositoryProvider);
    final envelope = await repository.buildBackup();
    final imageStore = await ref.read(productImageStoreProvider.future);
    final package = buildBackupPackage(
      envelope: envelope,
      productImagePaths: [
        for (final product in envelope.tables.products)
          if (product['imagePath'] is String) product['imagePath'] as String,
      ],
      readImageBytes: (imagePath) {
        try {
          return imageStore.resolve(imagePath)?.readAsBytesSync();
        } on Object {
          return null;
        }
      },
    );
    final store = await ref.read(backupFileStoreProvider.future);
    final info = await store.writeBytes(
      backupPackageFileName(DateTime.now()),
      package.bytes,
    );
    if (!context.mounted) return;
    final detail =
        '${package.includedImages.length} image${package.includedImages.length == 1 ? '' : 's'}'
        '${package.missingImages.isEmpty ? '' : ' (${package.missingImages.length} missing, skipped)'}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.folder_zip_outlined, color: AppColors.primary),
        title: const Text('Backup package exported'),
        content: Text(
          '${info.name}\n${backupSummaryLine(envelope.summary)}\n$detail.',
        ),
        actions: [
          SecondaryButton(
            label: 'Close',
            minHeight: 40,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          PrimaryButton(
            label: 'Share package',
            minHeight: 40,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareExportFile(context, ref, info.path);
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
        const SnackBar(
          content: Text('Could not export the package right now.'),
        ),
      );
  }
}

/// Builds the human-readable CSV sheets (export-only, never restorable),
/// saves them to the on-device store and offers to share them.
Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final repository = ref.read(backupRepositoryProvider);
    final envelope = await repository.buildBackup();
    final sheets = buildCsvExport(envelope);
    final store = await ref.read(backupFileStoreProvider.future);
    final written = <BackupFileInfo>[];
    for (final sheet in sheets) {
      written.add(
        await store.writeBytes(sheet.fileName, utf8.encode(sheet.content)),
      );
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.table_chart_outlined, color: AppColors.primary),
        title: const Text('CSV export ready'),
        content: Text(
          '${written.length} sheets saved on this device '
          '(products, customers, sales and more).\n'
          'Readable export only — CSV files cannot be restored.',
        ),
        actions: [
          SecondaryButton(
            label: 'Close',
            minHeight: 40,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          PrimaryButton(
            label: 'Share files',
            minHeight: 40,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareExportFiles(context, ref, [
                for (final info in written) info.path,
              ]);
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
        const SnackBar(content: Text('Could not export CSV right now.')),
      );
  }
}

/// Builds the date-range management report PDF (export-only): sales, expenses,
/// staff salary details and daily closings for the picked range. The owner
/// picks an inclusive range, the loader aggregates the current data under the
/// active business context, then the report is saved on-device and offered
/// for sharing.
Future<void> _exportPdf(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: DateTime(now.year, now.month, now.day - 6),
        end: DateTime(now.year, now.month, now.day),
      ),
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: 'Pick the date range for the report',
      saveText: 'Build report',
    );
    if (picked == null || !context.mounted) return;

    final data = await ManagementReportLoader.from(
      ref,
    ).load(fromLocal: picked.start, toLocal: picked.end);
    if (!context.mounted) return;
    final bytes = await buildManagementReportPdf(data);
    final store = await ref.read(backupFileStoreProvider.future);
    final info = await store.writeBytes(
      defaultManagementReportFileName(DateTime.now()),
      bytes,
    );
    if (!context.mounted) return;

    final rangeLabel =
        '${DateFormat('d MMM yyyy').format(picked.start)} – '
        '${DateFormat('d MMM yyyy').format(picked.end)}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(
          Icons.picture_as_pdf_outlined,
          color: AppColors.primary,
        ),
        title: const Text('Management report ready'),
        content: Text(
          '${info.name}\n$rangeLabel '
          '(${data.businessLabel}).\n'
          'Sales, expenses, staff salary details and daily closings for the '
          'selected range. Readable report only — it cannot be restored.',
        ),
        actions: [
          SecondaryButton(
            label: 'Close',
            minHeight: 40,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
          PrimaryButton(
            label: 'Share report',
            minHeight: 40,
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _shareExportFile(context, ref, info.path);
            },
          ),
        ],
      ),
    );
  } on ManagementReportFailure catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } on BackupFailure catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not build the report right now.')),
      );
  }
}

/// Shares one already-written export file through the system share sheet.
Future<void> _shareExportFile(
  BuildContext context,
  WidgetRef ref,
  String filePath,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(shareServiceProvider)
        .shareFile(subject: 'JiggarTea Bill export', filePath: filePath);
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not share the file right now.')),
      );
  }
}

/// Shares several already-written export files (the CSV sheets) at once.
Future<void> _shareExportFiles(
  BuildContext context,
  WidgetRef ref,
  List<String> filePaths,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(shareServiceProvider)
        .shareFiles(subject: 'JiggarTea Bill export', filePaths: filePaths);
  } on Object {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Could not share the files right now.')),
      );
  }
}

/// A parsed restore candidate: the envelope plus any packaged images.
/// JSON backups carry no images; ZIP packages may carry `images/<file>` blobs
/// that are written back to the product image store after the data commit.
typedef _RestoreCandidate = ({
  BackupEnvelope envelope,
  Map<String, Uint8List> images,
});

/// Reads and parses one restore candidate. `.zip` packages are unpacked and
/// their metadata cross-checked against the embedded envelope; anything else
/// is parsed as a raw JSON envelope. Throws [BackupFailure] subtypes.
Future<_RestoreCandidate> _loadRestoreCandidate(
  BackupFileStore store,
  String fileName,
) async {
  if (fileName.toLowerCase().endsWith('.zip')) {
    final bytes = await store.readBytes(fileName);
    final unpacked = unpackBackupPackage(bytes);
    final envelope = BackupEnvelope.fromJsonString(unpacked.backupJson);
    final metadata = unpacked.metadata;
    if (metadata != null && metadata.shopId != envelope.shopId) {
      throw const CorruptBackupFailure();
    }
    return (envelope: envelope, images: unpacked.images);
  }
  final contents = await store.readFile(fileName);
  return (
    envelope: BackupEnvelope.fromJsonString(contents),
    images: const <String, Uint8List>{},
  );
}

/// Walks the user through picking, previewing and confirming a restore.
Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  _guardBackupAccess(ref);
  try {
    final store = await ref.read(backupFileStoreProvider.future);
    final files = await store.listFiles();
    final packages = await store.listPackages();
    final candidates = [...files, ...packages]..sort(compareBackupFileInfo);
    if (!context.mounted) return;
    if (candidates.isEmpty) {
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
            itemCount: candidates.length,
            separatorBuilder: (separatorContext, index) =>
                Divider(height: 1, color: context.appColors.divider),
            itemBuilder: (_, index) {
              final file = candidates[index];
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

    final loaded = await _loadRestoreCandidate(store, selected.name);
    final envelope = loaded.envelope;
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
    // Package images are restored best-effort after the data commit: the UI
    // already falls back to a placeholder for missing images, so one
    // unreadable file can never fail an otherwise complete restore.
    if (loaded.images.isNotEmpty) {
      final imageStore = await ref.read(productImageStoreProvider.future);
      for (final entry in loaded.images.entries) {
        try {
          await imageStore.restoreBytes(entry.key, entry.value);
        } on Object {
          continue;
        }
      }
    }
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
