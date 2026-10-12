import 'dart:typed_data';

import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — In-app PDF preview for generated reports.
///
/// Opens the freshly generated report bytes in a full-screen viewer
/// immediately after generation (no intermediate dialog). The file is
/// already saved on-device by the caller; the viewer offers Share (existing
/// [ShareService]) and Save (re-writes the same bytes through the existing
/// backup file store) actions. Nothing here regenerates the PDF or changes
/// its content.
/// ---------------------------------------------------------------------------

/// Opens the generated report PDF in a full-screen in-app viewer.
///
/// [bytes] are the already-generated document, [fileName]/[filePath] the
/// already-saved file, [detailLine] the range/shop subtitle, and
/// [shareSubject] the subject used by the existing share flow.
Future<void> showReportPdfPreview(
  BuildContext context, {
  required Uint8List bytes,
  required String fileName,
  required String filePath,
  required String detailLine,
  required String shareSubject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (sheetContext) => _ReportPdfPreviewSheet(
      bytes: bytes,
      fileName: fileName,
      filePath: filePath,
      detailLine: detailLine,
      shareSubject: shareSubject,
    ),
  );
}

final class _ReportPdfPreviewSheet extends ConsumerStatefulWidget {
  const _ReportPdfPreviewSheet({
    required this.bytes,
    required this.fileName,
    required this.filePath,
    required this.detailLine,
    required this.shareSubject,
  });

  final Uint8List bytes;
  final String fileName;
  final String filePath;
  final String detailLine;
  final String shareSubject;

  @override
  ConsumerState<_ReportPdfPreviewSheet> createState() =>
      _ReportPdfPreviewSheetState();
}

final class _ReportPdfPreviewSheetState
    extends ConsumerState<_ReportPdfPreviewSheet> {
  static const String tag = 'ReportPreview';

  bool _busy = false;

  Future<Uint8List> _build(PdfPageFormat format) async => widget.bytes;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(shareServiceProvider)
          .shareFile(subject: widget.shareSubject, filePath: widget.filePath);
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not share the file right now.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final store = await ref.read(backupFileStoreProvider.future);
      final info = await store.writeBytes(widget.fileName, widget.bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Saved as ${info.name}')));
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not save the file right now.')),
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: AppSpacing.lg,
        title: Row(
          children: [
            const Icon(Icons.picture_as_pdf_outlined, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    widget.detailLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share report',
            icon: const Icon(Icons.share_outlined),
            onPressed: _busy ? null : _share,
          ),
          IconButton(
            tooltip: 'Save to device',
            icon: const Icon(Icons.download_outlined),
            onPressed: _busy ? null : _save,
          ),
          IconButton(
            tooltip: 'Close preview',
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: PdfPreview(
        build: _build,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: widget.fileName,
        loadingWidget: const LoadingState(message: 'Opening preview…'),
        onError: (context, error) {
          AppLog.error('Report PDF preview failed', tag: tag, error: error);
          return const ErrorState(
            message: 'Could not open the preview right now.',
          );
        },
      ),
    );
  }
}
