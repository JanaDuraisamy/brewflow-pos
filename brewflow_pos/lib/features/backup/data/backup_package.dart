import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'package:brewflow_pos/features/backup/domain/backup_failures.dart';
import 'package:brewflow_pos/features/backup/domain/backup_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Full Backup Package (ZIP)
///
/// A self-contained, restorable archive for one shop:
///
///   backup.json    the complete [BackupEnvelope] JSON (the restorable backup)
///   metadata.json  package identity (format/version/shop/backup ids, image
///                  list) — never credentials, tokens or secrets
///   `images/<file>` the product image files referenced by the backed-up
///                  product rows (`images/` mirrors the image basenames)
///
/// Building never mutates the database; missing images are tolerated (listed
/// in [BuiltBackupPackage.missingImages]) so one cleaned file can never fail
/// an otherwise complete backup. Unpacking is strict about `backup.json`
/// (it must be present) and lenient about the rest.
/// ---------------------------------------------------------------------------

/// Wire identifier of a BrewFlow backup package document.
const String kBackupPackageFormat = 'brewflow.backup-package';

/// Version of the package layout. Bump when the entry layout changes.
const int kBackupPackageVersion = 1;

/// Entry names inside the archive.
const String kPackageBackupEntry = 'backup.json';
const String kPackageMetadataEntry = 'metadata.json';

/// Folder inside the archive holding product images (by file basename).
const String kPackageImagesDir = 'images';

/// Identity block stored as `metadata.json` inside every package.
final class BackupPackageMetadata {
  const BackupPackageMetadata({
    required this.shopId,
    required this.backupId,
    required this.schemaVersion,
    required this.backupVersion,
    required this.createdAt,
    required this.imageNames,
    this.format = kBackupPackageFormat,
    this.packageVersion = kBackupPackageVersion,
  });

  final String format;
  final int packageVersion;
  final String shopId;
  final String backupId;
  final int schemaVersion;
  final int backupVersion;
  final DateTime createdAt;
  final List<String> imageNames;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'packageVersion': packageVersion,
    'shopId': shopId,
    'backupId': backupId,
    'schemaVersion': schemaVersion,
    'backupVersion': backupVersion,
    'createdAt': createdAt.toIso8601String(),
    'imageCount': imageNames.length,
    'images': imageNames,
  };

  factory BackupPackageMetadata.fromJson(Map<String, dynamic> json) {
    if (json['format'] != kBackupPackageFormat) {
      throw const InvalidBackupFormatFailure();
    }
    final shopId = json['shopId'];
    final backupId = json['backupId'];
    if (shopId is! String ||
        shopId.trim().isEmpty ||
        backupId is! String ||
        backupId.trim().isEmpty) {
      throw const CorruptBackupFailure();
    }
    final images = json['images'];
    return BackupPackageMetadata(
      shopId: shopId,
      backupId: backupId,
      schemaVersion: json['schemaVersion'] is int
          ? json['schemaVersion'] as int
          : 0,
      backupVersion: json['backupVersion'] is int
          ? json['backupVersion'] as int
          : 0,
      createdAt: json['createdAt'] is String
          ? (DateTime.tryParse(json['createdAt'] as String) ??
                DateTime.now().toUtc())
          : DateTime.now().toUtc(),
      imageNames: images is List
          ? [
              for (final name in images)
                if (name is String) name,
            ]
          : const [],
    );
  }
}

/// Result of building a package: the ZIP bytes plus what went into it.
final class BuiltBackupPackage {
  const BuiltBackupPackage({
    required this.bytes,
    required this.metadata,
    required this.includedImages,
    required this.missingImages,
  });

  /// The complete `.zip` file contents.
  final Uint8List bytes;

  /// The identity block also stored as `metadata.json`.
  final BackupPackageMetadata metadata;

  /// Image basenames embedded under `images/`.
  final List<String> includedImages;

  /// Referenced images that could not be read (cleaned/stale files).
  final List<String> missingImages;
}

/// Builds a self-contained ZIP package for [envelope].
///
/// [productImagePaths] are the `imagePath` values referenced by the backed-up
/// product rows; [readImageBytes] returns the file bytes for one such path or
/// null when the file is gone. Missing images never fail the build.
BuiltBackupPackage buildBackupPackage({
  required BackupEnvelope envelope,
  required List<String> productImagePaths,
  required Uint8List? Function(String imagePath) readImageBytes,
}) {
  final archive = Archive();
  final backupJson = envelope.encodeJson();
  archive.addFile(
    ArchiveFile(
      kPackageBackupEntry,
      backupJson.length,
      utf8.encode(backupJson),
    ),
  );

  final included = <String>[];
  final missing = <String>[];
  final seen = <String>{};
  for (final imagePath in productImagePaths) {
    final name = p.basename(imagePath);
    if (name.isEmpty || !seen.add(name)) continue;
    final bytes = readImageBytes(imagePath);
    if (bytes == null) {
      missing.add(name);
      continue;
    }
    archive.addFile(
      ArchiveFile('$kPackageImagesDir/$name', bytes.length, bytes),
    );
    included.add(name);
  }

  final metadata = BackupPackageMetadata(
    shopId: envelope.shopId,
    backupId: envelope.backupId,
    schemaVersion: envelope.schemaVersion,
    backupVersion: envelope.backupVersion,
    createdAt: envelope.createdAt,
    imageNames: included,
  );
  final metadataJson = const JsonEncoder().convert(metadata.toJson());
  archive.addFile(
    ArchiveFile(
      kPackageMetadataEntry,
      metadataJson.length,
      utf8.encode(metadataJson),
    ),
  );

  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
  return BuiltBackupPackage(
    bytes: bytes,
    metadata: metadata,
    includedImages: included,
    missingImages: missing,
  );
}

/// A package opened for inspection/restore.
final class UnpackedBackupPackage {
  const UnpackedBackupPackage({
    required this.backupJson,
    required this.metadata,
    required this.images,
  });

  /// Raw `backup.json` contents — parse with [BackupEnvelope.fromJsonString]
  /// so format, checksum and structure are validated in one place.
  final String backupJson;

  /// The `metadata.json` identity block, or null when absent.
  final BackupPackageMetadata? metadata;

  /// Image bytes keyed by basename (`images/<basename>` entries only).
  final Map<String, Uint8List> images;
}

/// Opens a package produced by [buildBackupPackage].
///
/// Throws [CorruptBackupFailure] when the bytes are not a ZIP archive or
/// `backup.json` is missing/unreadable. A damaged `metadata.json` fails too;
/// a missing one is tolerated.
UnpackedBackupPackage unpackBackupPackage(List<int> bytes) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } on Object {
    throw const CorruptBackupFailure();
  }
  String? backupJson;
  BackupPackageMetadata? metadata;
  final images = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile) continue;
    final name = file.name.replaceAll('\\', '/');
    // Never let a hostile archive write outside its own folder.
    if (name.contains('..')) continue;
    if (name == kPackageBackupEntry) {
      try {
        backupJson = utf8.decode(file.content as List<int>);
      } on Object {
        throw const CorruptBackupFailure();
      }
    } else if (name == kPackageMetadataEntry) {
      try {
        final decoded = const JsonDecoder().convert(
          utf8.decode(file.content as List<int>),
        );
        if (decoded is Map<String, dynamic>) {
          metadata = BackupPackageMetadata.fromJson(decoded);
        } else {
          throw const CorruptBackupFailure();
        }
      } on BackupFailure {
        rethrow;
      } on Object {
        throw const CorruptBackupFailure();
      }
    } else if (name.startsWith('$kPackageImagesDir/')) {
      final base = p.basename(name);
      if (base.isNotEmpty) {
        images[base] = Uint8List.fromList(file.content as List<int>);
      }
    }
  }
  if (backupJson == null) throw const CorruptBackupFailure();
  return UnpackedBackupPackage(
    backupJson: backupJson,
    metadata: metadata,
    images: images,
  );
}
