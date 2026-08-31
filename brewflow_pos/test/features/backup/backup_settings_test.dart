import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_page.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_backup_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// Captures shared content instead of opening the platform share sheet.
final class FakeShareService implements ShareService {
  final List<({String subject, String text})> calls = [];

  @override
  Future<void> shareText({
    required String subject,
    required String text,
  }) async {
    calls.add((subject: subject, text: text));
  }
}

/// In-memory [BackupFileStore] so widget tests never touch real disk I/O
/// (real `dart:io` futures do not resolve under the test's fake-async zone).
final class _MemoryBackupFileStore implements BackupFileStore {
  final Map<String, String> files = {};

  static final DateTime _epoch = DateTime(2026, 8, 31, 10, 15);

  @override
  Future<List<BackupFileInfo>> listFiles() async {
    final infos = <BackupFileInfo>[
      for (final entry in files.entries)
        BackupFileInfo(
          name: entry.key,
          path: entry.key,
          sizeBytes: entry.value.length,
          modifiedAt: _epoch,
        ),
    ];
    infos.sort(compareBackupFileInfo);
    return infos;
  }

  @override
  Future<BackupFileInfo> write(String fileName, String contents) async {
    files[fileName] = contents;
    return BackupFileInfo(
      name: fileName,
      path: fileName,
      sizeBytes: contents.length,
      modifiedAt: _epoch,
    );
  }

  @override
  Future<String> readFile(String fileName) async {
    final contents = files[fileName];
    if (contents == null) throw const UnexpectedBackupFailure();
    return contents;
  }

  @override
  Future<void> deleteFile(String fileName) async {
    files.remove(fileName);
  }
}

const _owner = AuthUser(id: 'o-1', email: 'owner@brewflow.example');

Set<Permission> _permissionsFromDbValues(Set<String> dbValues) {
  final byKey = {for (final p in Permission.values) p.dbValue: p};
  return {
    for (final value in dbValues)
      if (byKey[value] != null) byKey[value]!,
  };
}

void main() {
  BackupEnvelope backupEnvelope() => BackupEnvelope(
    shopId: 'shop-1',
    sourceDeviceId: 'device-1',
    settingsJson: const {'shopName': 'Cafe Marina'},
    tables: const BackupTables(
      products: [
        {'id': 'prod-1', 'name': 'Filter Coffee'},
      ],
    ),
  );

  late FakeSettingsRepository settings;
  late FakeBackupRepository backup;
  late FakeShareService share;
  late _MemoryBackupFileStore store;

  setUp(() {
    settings = FakeSettingsRepository();
    backup = FakeBackupRepository()..envelope = backupEnvelope();
    share = FakeShareService();
    store = _MemoryBackupFileStore();
  });

  /// Pumps the desktop Settings page wired with fakes for every provider the
  /// backup section uses.
  Future<void> pumpDesktop(
    WidgetTester tester, {
    AuthUser user = _owner,
    Set<String> staffPermissions = const {},
    bool seedNoBackups = true,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1200, 1400);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final staffRepo = FakeStaffRepository();
    await staffRepo.claimOwnership(_owner);
    if (user != _owner) {
      final member = await staffRepo.createStaffProfile(
        identity: user,
        shopId: 'shop-1',
        permissions: _permissionsFromDbValues(staffPermissions),
      );
      await staffRepo.updateStaff(StaffUpdateInput(id: member.id));
    }

    if (!seedNoBackups) {
      await store.write(
        'backup_20260831_101500.json',
        backupEnvelope().encodeJson(),
      );
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(user: user),
          ),
          staffRepositoryProvider.overrideWithValue(staffRepo),
          backupRepositoryProvider.overrideWithValue(backup),
          backupFileStoreProvider.overrideWithValue(AsyncData(store)),
          shareServiceProvider.overrideWithValue(share),
        ],
        child: const MaterialApp(home: Scaffold(body: SettingsPage())),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('rendering', () {
    testWidgets('an owner sees the Data & Backup card with both actions', (
      tester,
    ) async {
      await pumpDesktop(tester);

      expect(find.text('Data & Backup'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create backup'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Restore backup'),
        findsOneWidget,
      );
    });

    testWidgets('staff without settings permission see no backup section', (
      tester,
    ) async {
      await pumpDesktop(
        tester,
        user: const AuthUser(id: 'st-1', email: 'staff@brewflow.example'),
        staffPermissions: const {'CUSTOMERS'},
      );

      expect(find.text('Data & Backup'), findsNothing);
      expect(find.text('Create backup'), findsNothing);
    });

    testWidgets('the phone layout renders the Data & Backup section', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final staffRepo = FakeStaffRepository();
      await staffRepo.claimOwnership(_owner);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(settings),
            authRepositoryProvider.overrideWithValue(
              FakeAuthRepository(user: _owner),
            ),
            staffRepositoryProvider.overrideWithValue(staffRepo),
            backupRepositoryProvider.overrideWithValue(backup),
            backupFileStoreProvider.overrideWithValue(AsyncData(store)),
            shareServiceProvider.overrideWithValue(share),
          ],
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DATA & BACKUP'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Create backup'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(OutlinedButton, 'Restore backup'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('create backup', () {
    testWidgets('writes an envelope file and offers to share it', (
      tester,
    ) async {
      await pumpDesktop(tester);

      await tester.ensureVisible(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(find.text('Backup created'), findsOneWidget);
      expect(find.text('1 product'), findsOneWidget);

      final files = await store.listFiles();
      expect(files, hasLength(1));
      expect(files.single.name, endsWith('.json'));

      final contents = await store.readFile(files.single.name);
      final written = BackupEnvelope.fromJsonString(contents);
      expect(written.shopId, 'shop-1');
      expect(written.tables.summary.products, 1);

      await tester.tap(find.text('Share backup'));
      await tester.pumpAndSettle();

      expect(share.calls, hasLength(1));
      expect(share.calls.single.subject, 'BrewFlow backup');
      expect(share.calls.single.text, contents);
    });

    testWidgets('a export failure surfaces the safe message', (tester) async {
      backup.buildError = const UnexpectedBackupFailure();
      await pumpDesktop(tester);

      await tester.ensureVisible(find.text('Create backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create backup'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not complete the backup right now. Please try again.'),
        findsOneWidget,
      );
      expect(await store.listFiles(), isEmpty);
    });
  });

  group('restore backup', () {
    testWidgets('lists, previews and confirms a restore', (tester) async {
      await pumpDesktop(tester, seedNoBackups: false);

      await tester.ensureVisible(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      expect(find.text('backup_20260831_101500.json'), findsOneWidget);

      await tester.tap(find.text('backup_20260831_101500.json'));
      await tester.pumpAndSettle();

      expect(find.text('Restore anything on this device?'), findsOneWidget);
      expect(find.textContaining('cannot be undone'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(backup.restoreCalled, isTrue);
      expect(backup.restored?.shopId, 'shop-1');
      expect(find.text('Backup restored.'), findsOneWidget);
    });

    testWidgets('cancelling the confirmation leaves data untouched', (
      tester,
    ) async {
      await pumpDesktop(tester, seedNoBackups: false);

      await tester.ensureVisible(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('backup_20260831_101500.json'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(backup.restoreCalled, isFalse);
    });

    testWidgets('shows an info toast when no backups exist', (tester) async {
      await pumpDesktop(tester);

      await tester.ensureVisible(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();

      expect(find.text('No backups found on this device.'), findsOneWidget);
    });

    testWidgets('a damaged backup file surfaces a safe error', (tester) async {
      await store.write('bad.json', '{"not":');
      await pumpDesktop(tester);

      await tester.ensureVisible(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bad.json'));
      await tester.pumpAndSettle();

      expect(
        find.text('This backup file is damaged or unreadable.'),
        findsOneWidget,
      );
      expect(backup.restoreCalled, isFalse);
    });

    testWidgets('a restore failure surfaces the safe message', (tester) async {
      backup.restoreError = const CrossShopBackupFailure();
      await pumpDesktop(tester, seedNoBackups: false);

      await tester.ensureVisible(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('backup_20260831_101500.json'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This backup belongs to a different shop and cannot be restored here.',
        ),
        findsOneWidget,
      );
    });
  });
}
