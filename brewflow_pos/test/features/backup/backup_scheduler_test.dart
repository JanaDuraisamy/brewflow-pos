import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';
import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_backup_repository.dart';

/// In-memory [BackupFileStore] so scheduler tests run without real disk I/O.
final class _MemoryBackupFileStore implements BackupFileStore {
  final Map<String, String> files = {};

  @override
  Future<List<BackupFileInfo>> listFiles() async {
    final infos = <BackupFileInfo>[
      for (final entry in files.entries)
        BackupFileInfo(
          name: entry.key,
          path: entry.key,
          sizeBytes: entry.value.length,
          modifiedAt: DateTime.utc(2026, 8, 31),
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
      modifiedAt: DateTime.utc(2026, 8, 31),
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

/// In-memory [BackupScheduleStore] seeded with an optional last-run date.
final class _MemoryBackupScheduleStore implements BackupScheduleStore {
  DateTime? last;

  @override
  Future<DateTime?> lastAutoBackup() async => last;

  @override
  Future<void> markAutoBackup(DateTime at) async {
    last = at;
  }
}

BackupEnvelope _envelope() => BackupEnvelope(
  shopId: 'shop-1',
  tables: const BackupTables(
    products: [
      {'id': 'prod-1', 'name': 'Filter Coffee'},
    ],
  ),
);

void main() {
  late FakeBackupRepository repository;
  late _MemoryBackupFileStore store;
  late _MemoryBackupScheduleStore schedule;
  late DateTime now;
  late DailyBackupScheduler scheduler;

  DailyBackupScheduler buildScheduler({int retentionCount = 10}) =>
      DailyBackupScheduler(
        backupRepository: repository,
        fileStore: store,
        scheduleStore: schedule,
        clock: () => now,
        retentionCount: retentionCount,
      );

  setUp(() {
    repository = FakeBackupRepository()..envelope = _envelope();
    store = _MemoryBackupFileStore();
    schedule = _MemoryBackupScheduleStore();
    now = DateTime(2026, 8, 31, 10, 15);
    scheduler = buildScheduler();
  });

  group('DailyBackupScheduler', () {
    test(
      'creates a backup and records the run when none exists today',
      () async {
        final result = await scheduler.run();

        expect(result, isA<AutoBackupCreated>());
        expect(store.files, hasLength(1));
        expect(store.files.keys.single, startsWith('brewflow_backup_'));
        expect(store.files.keys.single, endsWith('.json'));
        expect(schedule.last, now);
      },
    );

    test('the written file is a valid, checksummed envelope', () async {
      await scheduler.run();

      final raw = store.files.values.single;
      final envelope = BackupEnvelope.fromJsonString(raw);
      expect(envelope.shopId, 'shop-1');
      expect(envelope.tables.summary.products, 1);
      expect(envelope.checksum, isNotNull);
      // parse succeeded => embedded checksum verified against the data.
      envelope.verifyChecksum();
    });

    test(
      'skips when a backup was already created today (same-day dedup)',
      () async {
        schedule.last = DateTime(2026, 8, 31, 6, 0);
        now = DateTime(2026, 8, 31, 20, 0);

        final result = await scheduler.run();

        expect(result, isA<AutoBackupSkippedToday>());
        expect(store.files, isEmpty);
      },
    );

    test('creates again on a later day', () async {
      schedule.last = DateTime(2026, 8, 30, 22, 0);
      now = DateTime(2026, 8, 31, 9, 0);

      final result = await scheduler.run();

      expect(result, isA<AutoBackupCreated>());
      expect(store.files, hasLength(1));
      expect(schedule.last, now);
    });

    test('enforces retention, keeping the newest backups only', () async {
      repository = FakeBackupRepository()..envelope = _envelope();
      store
        ..files['oldest.json'] = '{}'
        ..files['old.json'] = '{}'
        ..files['new.json'] = '{}';
      scheduler = buildScheduler(retentionCount: 2);

      final result = await scheduler.run();

      expect(result, isA<AutoBackupCreated>());
      // Keeps the 2 newest: the just-written new backup + 'new.json'.
      expect(store.files, hasLength(2));
      expect(store.files.containsKey('oldest.json'), isFalse);
      expect(store.files.containsKey('old.json'), isFalse);
      expect(store.files.containsKey('new.json'), isTrue);
    });

    test('returns failed without writing when the snapshot fails', () async {
      repository.buildError = const UnexpectedBackupFailure();

      final result = await scheduler.run();

      expect(result, isA<AutoBackupFailed>());
      expect(store.files, isEmpty);
      expect(schedule.last, isNull);
    });

    test(
      'returns failed without marking the run when the write fails',
      () async {
        final failingStore = _FailingStore();
        scheduler = DailyBackupScheduler(
          backupRepository: repository,
          fileStore: failingStore,
          scheduleStore: schedule,
          clock: () => now,
        );

        final result = await scheduler.run();

        expect(result, isA<AutoBackupFailed>());
        expect(schedule.last, isNull);
      },
    );

    test('never throws out to the caller', () async {
      repository.buildError = StateError('boom');

      expect(await scheduler.run(), isA<AutoBackupFailed>());
    });
  });
}

/// [BackupFileStore] whose writes always fail (I/O failure simulation).
final class _FailingStore implements BackupFileStore {
  @override
  Future<void> deleteFile(String fileName) async {}

  @override
  Future<List<BackupFileInfo>> listFiles() async => const [];

  @override
  Future<String> readFile(String fileName) async =>
      throw const UnexpectedBackupFailure();

  @override
  Future<BackupFileInfo> write(String fileName, String contents) async =>
      throw const UnexpectedBackupFailure();
}
