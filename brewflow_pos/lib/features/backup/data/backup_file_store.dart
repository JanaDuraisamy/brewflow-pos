import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Backup File Store
///
/// Encapsulates where backups live on disk and how they are written, listed,
/// read and deleted. Production uses the app's documents directory
/// (`<documents>/backups/`, via [AppDocumentsBackupFileStore]); the abstract
/// [BackupFileStore] keeps the repository and the UI independent of the
/// platform and lets tests run against plain in-memory sandboxes.
/// ---------------------------------------------------------------------------

/// Metadata of a backup file listed from the store.
final class BackupFileInfo {
  const BackupFileInfo({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;
}

/// Sort order for the extraction dialog: newest first, then name.
int compareBackupFileInfo(BackupFileInfo a, BackupFileInfo b) {
  final byDate = b.modifiedAt.compareTo(a.modifiedAt);
  if (byDate != 0) return byDate;
  return a.name.compareTo(b.name);
}

/// Human-safe default name for a full backup package:
/// `brewflow_backup_YYYYMMDD_HHMMSS.zip`. The ZIP is self-contained (backup
/// JSON + metadata + images) so it can be restored without anything else.
String backupPackageFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  final stamp =
      '${local.year}'
      '${two(local.month)}'
      '${two(local.day)}'
      '_'
      '${two(local.hour)}'
      '${two(local.minute)}'
      '${two(local.second)}';
  return 'brewflow_backup_$stamp.zip';
}

/// Human-safe default name: `brewflow_backup_YYYYMMDD_HHMMSS.json`.
String backupFileName(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  final local = time.toLocal();
  final stamp =
      '${local.year}'
      '${two(local.month)}'
      '${two(local.day)}'
      '_'
      '${two(local.hour)}'
      '${two(local.minute)}'
      '${two(local.second)}';
  return 'brewflow_backup_$stamp.json';
}

abstract interface class BackupFileStore {
  /// All JSON backups currently in the store, newest first.
  Future<List<BackupFileInfo>> listFiles();

  /// All ZIP backup packages currently in the store, newest first.
  Future<List<BackupFileInfo>> listPackages();

  /// Writes [contents] as [fileName], appending a collision suffix when a
  /// file with that name already exists. Returns the written file info.
  Future<BackupFileInfo> write(String fileName, String contents);

  /// Writes raw [bytes] (ZIP package, PDF report, CSV export) as [fileName],
  /// appending a collision suffix when a file with that name already exists.
  /// Returns the written file info.
  Future<BackupFileInfo> writeBytes(String fileName, List<int> bytes);

  /// Reads the full contents of a stored backup.
  Future<String> readFile(String fileName);

  /// Reads the raw bytes of a stored file (package, report or export).
  Future<List<int>> readBytes(String fileName);

  /// Deletes a stored backup. Missing files are ignored.
  Future<void> deleteFile(String fileName);
}

/// [BackupFileStore] backed by a plain directory, creating it on demand.
final class DirectoryBackupFileStore implements BackupFileStore {
  DirectoryBackupFileStore(this.directory);

  final Directory directory;

  @override
  Future<List<BackupFileInfo>> listFiles() async {
    return _listByExtension('.json');
  }

  @override
  Future<List<BackupFileInfo>> listPackages() async {
    return _listByExtension('.zip');
  }

  Future<List<BackupFileInfo>> _listByExtension(String extension) async {
    if (!await directory.exists()) return const [];
    final files = directory.listSync().whereType<File>().where(
      (file) => file.path.toLowerCase().endsWith(extension),
    );
    final infos = <BackupFileInfo>[
      for (final file in files)
        BackupFileInfo(
          name: p.basename(file.path),
          path: file.path,
          sizeBytes: await file.length(),
          modifiedAt: await file.lastModified(),
        ),
    ];
    infos.sort(compareBackupFileInfo);
    return infos;
  }

  @override
  Future<BackupFileInfo> write(String fileName, String contents) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    var target = File(p.join(directory.path, fileName));
    var index = 2;
    while (await target.exists()) {
      target = File(p.join(directory.path, _suffixed(fileName, index++)));
    }
    await target.writeAsString(contents, flush: true);
    return BackupFileInfo(
      name: p.basename(target.path),
      path: target.path,
      sizeBytes: contents.length,
      modifiedAt: await target.lastModified(),
    );
  }

  @override
  Future<BackupFileInfo> writeBytes(String fileName, List<int> bytes) async {
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    var target = File(p.join(directory.path, fileName));
    var index = 2;
    while (await target.exists()) {
      target = File(p.join(directory.path, _suffixed(fileName, index++)));
    }
    await target.writeAsBytes(bytes, flush: true);
    return BackupFileInfo(
      name: p.basename(target.path),
      path: target.path,
      sizeBytes: bytes.length,
      modifiedAt: await target.lastModified(),
    );
  }

  @override
  Future<String> readFile(String fileName) async {
    final file = File(p.join(directory.path, fileName));
    if (!await file.exists()) throw const UnexpectedBackupFailure();
    return file.readAsString();
  }

  @override
  Future<List<int>> readBytes(String fileName) async {
    final file = File(p.join(directory.path, fileName));
    if (!await file.exists()) throw const UnexpectedBackupFailure();
    return file.readAsBytes();
  }

  @override
  Future<void> deleteFile(String fileName) async {
    final file = File(p.join(directory.path, fileName));
    if (await file.exists()) await file.delete();
  }

  static String _suffixed(String name, int index) {
    final extension = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    return '$base${"_$index"}$extension';
  }
}

/// [BackupFileStore] rooted at `<app documents>/backups`, the durable,
/// app-private location used in production.
final class AppDocumentsBackupFileStore implements BackupFileStore {
  AppDocumentsBackupFileStore._(this._inner);

  static const String _folderName = 'backups';

  final BackupFileStore _inner;

  /// Resolves the platform documents directory and lazily wraps it. Safe to
  /// call at startup; no directory is created until the first write.
  static Future<AppDocumentsBackupFileStore> open() async {
    final documents = await getApplicationDocumentsDirectory();
    return AppDocumentsBackupFileStore._(
      DirectoryBackupFileStore(Directory(p.join(documents.path, _folderName))),
    );
  }

  @override
  Future<List<BackupFileInfo>> listFiles() => _inner.listFiles();

  @override
  Future<List<BackupFileInfo>> listPackages() => _inner.listPackages();

  @override
  Future<BackupFileInfo> write(String fileName, String contents) =>
      _inner.write(fileName, contents);

  @override
  Future<BackupFileInfo> writeBytes(String fileName, List<int> bytes) =>
      _inner.writeBytes(fileName, bytes);

  @override
  Future<String> readFile(String fileName) => _inner.readFile(fileName);

  @override
  Future<List<int>> readBytes(String fileName) => _inner.readBytes(fileName);

  @override
  Future<void> deleteFile(String fileName) => _inner.deleteFile(fileName);
}
