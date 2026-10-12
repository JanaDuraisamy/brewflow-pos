import 'dart:typed_data';

import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/reports/presentation/report_pdf_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Report PDF preview sheet tests.
///
/// The viewer opens with the generated file's identity, offers Share (via
/// the existing [ShareService]) and Save (via the existing backup file
/// store), and closes cleanly. PDF rasterization has no platform channel in
/// widget tests, so these tests assert the chrome, actions and error
/// handling — never pixel output.
/// ---------------------------------------------------------------------------

final class _FakeShareService implements ShareService {
  String? sharedPath;
  String? sharedSubject;

  @override
  Future<void> shareFile({
    required String subject,
    required String filePath,
  }) async {
    sharedSubject = subject;
    sharedPath = filePath;
  }

  @override
  Future<void> shareText({required String subject, required String text}) =>
      throw UnimplementedError();

  @override
  Future<void> shareFiles({
    required String subject,
    required List<String> filePaths,
  }) => throw UnimplementedError();
}

final class _FakeFileStore implements BackupFileStore {
  String? savedName;
  List<int>? savedBytes;

  BackupFileInfo _info(String fileName, List<int> bytes) => BackupFileInfo(
    name: fileName,
    path: '/tmp/$fileName',
    sizeBytes: bytes.length,
    modifiedAt: DateTime.utc(2026, 10, 9),
  );

  @override
  Future<BackupFileInfo> writeBytes(String fileName, List<int> bytes) async {
    savedName = fileName;
    savedBytes = bytes;
    return _info(fileName, bytes);
  }

  @override
  Future<List<BackupFileInfo>> listFiles() => throw UnimplementedError();

  @override
  Future<List<BackupFileInfo>> listPackages() => throw UnimplementedError();

  @override
  Future<BackupFileInfo> write(String fileName, String contents) =>
      throw UnimplementedError();

  @override
  Future<String> readFile(String fileName) => throw UnimplementedError();

  @override
  Future<List<int>> readBytes(String fileName) => throw UnimplementedError();

  @override
  Future<void> deleteFile(String fileName) => throw UnimplementedError();
}

void main() {
  const fileName = 'jiggartea_bill_management_report_test.pdf';
  const filePath = '/tmp/$fileName';
  final bytes = Uint8List.fromList(const [37, 80, 68, 70]);

  late _FakeShareService share;
  late _FakeFileStore store;

  Widget harness() => ProviderScope(
    overrides: [
      shareServiceProvider.overrideWithValue(share),
      backupFileStoreProvider.overrideWith((ref) async => store),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showReportPdfPreview(
              context,
              bytes: bytes,
              fileName: fileName,
              filePath: filePath,
              detailLine: '1 Oct 2026 – 9 Oct 2026 (Cafe)',
              shareSubject: 'Monthly report',
            ),
            child: const Text('Open preview'),
          ),
        ),
      ),
    ),
  );

  Future<void> openSheet(WidgetTester tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('Open preview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  setUp(() {
    share = _FakeShareService();
    store = _FakeFileStore();
  });

  testWidgets('preview opens with file identity and viewer actions', (
    tester,
  ) async {
    await openSheet(tester);

    expect(find.text(fileName), findsOneWidget);
    expect(find.text('1 Oct 2026 – 9 Oct 2026 (Cafe)'), findsOneWidget);
    expect(find.byTooltip('Share report'), findsOneWidget);
    expect(find.byTooltip('Save to device'), findsOneWidget);
    expect(find.byTooltip('Close preview'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('share uses the existing share service with the saved path', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.tap(find.byTooltip('Share report'));
    await tester.pump();

    expect(share.sharedPath, filePath);
    expect(share.sharedSubject, 'Monthly report');
    expect(tester.takeException(), isNull);
  });

  testWidgets('save rewrites the bytes and confirms the file name', (
    tester,
  ) async {
    await openSheet(tester);

    await tester.tap(find.byTooltip('Save to device'));
    await tester.pump();

    expect(store.savedName, fileName);
    expect(store.savedBytes, bytes);
    expect(find.text('Saved as $fileName'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('close dismisses the preview', (tester) async {
    await openSheet(tester);

    await tester.tap(find.byTooltip('Close preview'));
    await tester.pumpAndSettle();

    expect(find.text(fileName), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
