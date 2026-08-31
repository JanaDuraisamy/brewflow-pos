import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Store
///
/// Owns the on-device files behind [Product.imagePath]. Images live in a
/// dedicated `product_images/` folder inside the app documents directory;
/// [Product.imagePath] stores only the relative path (matching the model
/// contract "relative to the app documents directory"), so the database never
/// carries raw bytes and the files survive restarts.
///
/// The directory is injected so tests can point the store at a temporary
/// folder instead of the real app sandbox.
/// ---------------------------------------------------------------------------

final class ProductImageStore {
  ProductImageStore({required Directory documentsDir})
    : _root = Directory(p.join(documentsDir.path, 'product_images'));

  /// Folder name inside the documents directory; prefix of every stored
  /// relative [Product.imagePath].
  static const String folderName = 'product_images';

  final Directory _root;

  /// Copies [source] into the store under a fresh name and returns the
  /// relative path to persist in [Product.imagePath]. Existing files are
  /// never mutated; every save produces a new file so a failed save can never
  /// corrupt the currently referenced image.
  Future<String> saveFrom(File source) async {
    await _root.create(recursive: true);
    final fileName = '${const Uuid().v4()}.jpg';
    final destination = File(p.join(_root.path, fileName));
    await source.copy(destination.path);
    return '$folderName/$fileName';
  }

  /// Resolves a stored relative [imagePath] to a readable file, or null when
  /// the image is missing (e.g. cleaned storage or a stale reference). The UI
  /// falls back to its placeholder in that case.
  File? resolve(String imagePath) {
    final file = File(p.join(_root.path, p.basename(imagePath)));
    return file.existsSync() ? file : null;
  }

  /// Deletes a stored relative [imagePath]. Missing files are a no-op — the
  /// app must never crash or surface an error because a file is gone.
  Future<void> delete(String imagePath) async {
    final file = File(p.join(_root.path, p.basename(imagePath)));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// The app-wide product image store. Defaults to the app documents directory
/// (lazy — path_provider is only touched when the store is first used);
/// tests override it with a store pointed at a temporary directory.
final productImageStoreProvider = FutureProvider<ProductImageStore>((
  ref,
) async {
  final documentsDir = await getApplicationDocumentsDirectory();
  return ProductImageStore(documentsDir: documentsDir);
});
