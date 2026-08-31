import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Picker Gateway
///
/// Thin seam over the device gallery so widget tests never touch the platform
/// picker. The picked file stays a transient cache reference — the
/// [ProductImageStore] copies it into persistent storage before it is ever
/// stored in the database.
/// ---------------------------------------------------------------------------

/// A user-picked image; the [File] lives in the picker's cache directory and
/// must be copied into persistent storage before being referenced anywhere.
final class PickedProductImage {
  const PickedProductImage(this.file);

  final File file;
}

/// Picks one image from the gallery; returns null when the user cancels.
abstract interface class ProductImagePicker {
  Future<PickedProductImage?> pickGallery();
}

/// Real implementation backed by the image_picker plugin. Resize parameters
/// cap the stored size (thumbnails never need full camera resolution) and
/// quality 82 keeps files reasonable while staying good enough for a POS
/// shelf.
final class GalleryProductImagePicker implements ProductImagePicker {
  GalleryProductImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  static const double _maxDimension = 1200;
  static const int _quality = 82;

  final ImagePicker _picker;

  @override
  Future<PickedProductImage?> pickGallery() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: _maxDimension,
      maxHeight: _maxDimension,
      imageQuality: _quality,
    );
    if (picked == null) {
      return null;
    }
    return PickedProductImage(File(picked.path));
  }
}

/// The app-wide image picker. Tests override it with a fake.
final productImagePickerProvider = Provider<ProductImagePicker>(
  (ref) => GalleryProductImagePicker(),
);
