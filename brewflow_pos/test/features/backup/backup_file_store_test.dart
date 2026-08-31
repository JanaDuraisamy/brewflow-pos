import 'dart:io';

import 'package:brewflow_pos/features/backup/data/backup_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;
  late DirectoryBackupFileStore store;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('backup_store_test');
    store = DirectoryBackupFileStore(temp);
  });

  tearDown(() async {
    if (await temp.exists()) {
      await temp.delete(recursive: true);
    }
  });

  test('writes a backup and lists it newest first', () async {
    final first = await store.write('a.json', '{"a":1}');
    // Backdate the first file deterministically so ordering does not depend on
    // filesystem timestamp resolution.
    await File(first.path).setLastModified(DateTime.utc(2020, 1, 1));
    await store.write('b.json', '{"b":2}');

    final files = await store.listFiles();
    expect(files, hasLength(2));
    expect(files.first.name, 'b.json');
    expect(files.last.name, 'a.json');
    expect(files.first.sizeBytes, '{"b":2}'.length);

    final aFile = files.where((file) => file.name == first.name).single;
    expect(aFile.path, endsWith(first.name));
  });

  test('write picks a suffixed name on collision', () async {
    await store.write('same.json', 'first');
    final second = await store.write('same.json', 'second');
    final third = await store.write('same.json', 'third');

    expect(second.name, 'same_2.json');
    expect(third.name, 'same_3.json');
    expect(await store.readFile('same.json'), 'first');
    expect(await store.readFile('same_2.json'), 'second');
    expect(await store.readFile('same_3.json'), 'third');
  });

  test('read returns the exact written contents', () async {
    await store.write('x.json', '{"hello":"world"}');
    expect(await store.readFile('x.json'), '{"hello":"world"}');
  });

  test('delete removes only the requested file', () async {
    await store.write('a.json', '1');
    await store.write('b.json', '2');

    await store.deleteFile('a.json');
    expect(await store.readFile('b.json'), '2');
    expect(await store.listFiles(), hasLength(1));
  });

  test('reading or deleting a missing file is safe', () async {
    await store.deleteFile('nope.json');
    await expectLater(
      store.readFile('nope.json'),
      throwsA(anything), // surfaces an UnexpectedBackupFailure upstream
    );
  });

  test('list ignores non-JSON files', () async {
    await store.write('a.json', '{}');
    await File(
      '${temp.path}${Platform.pathSeparator}notes.txt',
    ).writeAsString('ignore me');
    final files = await store.listFiles();
    expect(files, hasLength(1));
    expect(files.single.name, 'a.json');
  });

  test('creates the directory lazily on first write', () async {
    final nested = Directory('${temp.path}${Platform.pathSeparator}backups');
    final nestedStore = DirectoryBackupFileStore(nested);
    expect(await nested.exists(), isFalse);

    await nestedStore.write('a.json', '{}');
    expect(await nested.exists(), isTrue);
    expect(await nestedStore.listFiles(), hasLength(1));
  });

  group('backupFileName', () {
    test('produces a sortable local timestamp name', () {
      final name = backupFileName(DateTime(2026, 8, 31, 15, 7, 9));
      expect(name, 'brewflow_backup_20260831_150709.json');
    });
  });
}
