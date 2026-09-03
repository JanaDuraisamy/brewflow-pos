import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Processor
///
/// Resizes, compresses and encodes picked product images to meet the storage
/// target:
///   - Max dimensions: 800 × 800 (cover, aspect-ratio preserving)
///   - Format: JPEG
///   - Size: 100 – 300 KB (quality stepping to hit the band)
///
/// The processor is pure Dart — no platform channels — so it works identically
/// in production and in tests.
/// ---------------------------------------------------------------------------

final class ProductImageProcessor {
  /// Maximum pixel dimension on any side.
  static const int maxDimension = 800;

  /// Target minimum byte size (100 KB).
  static const int minBytes = 100 * 1024;

  /// Target maximum byte size (300 KB).
  static const int maxBytes = 300 * 1024;

  /// JPEG quality range boundaries.
  static const int minQuality = 50;
  static const int maxQuality = 92;

  /// Processes the image at [sourcePath]:
  ///
  /// 1. Decodes the file (JPG/PNG/BMP/WebP when supported by decoder).
  /// 2. Resizes to fit within [maxDimension] × [maxDimension].
  /// 3. Encodes as JPEG, stepping quality down from [maxQuality] until the
  ///    result fits under [maxBytes], or stepping up from [minQuality] when
  ///    the result is below [minBytes].
  /// 4. Writes the processed bytes to a new file next to [destPath] (or a
  ///    sibling of [sourcePath] when [destPath] is null) and returns the
  ///    absolute file path and its byte length.
  ///
  /// Returns [ProcessedImageResult] with the written file and metadata.
  /// Throws [ImageProcessingFailure] on decode / encode errors.
  static Future<ProcessedImageResult> process({
    required String sourcePath,
    String? destPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw ImageProcessingFailure('Source image not found: $sourcePath');
    }

    final img.Image? original;
    try {
      original = await img.decodeImageFile(sourcePath);
    } catch (e) {
      throw ImageProcessingFailure(
        'Failed to decode image: $sourcePath (${e.toString()})',
      );
    }
    if (original == null) {
      throw ImageProcessingFailure('Unsupported image format: $sourcePath');
    }

    final resized = _resize(original);
    final encoded = _encodeWithQualityStepping(resized);

    final outPath =
        destPath ??
        p.join(
          p.dirname(sourcePath),
          '${p.basenameWithoutExtension(sourcePath)}_processed.jpg',
        );
    await File(outPath).writeAsBytes(encoded, flush: true);

    return ProcessedImageResult(
      path: outPath,
      width: resized.width,
      height: resized.height,
      byteLength: encoded.length,
      format: 'JPEG',
    );
  }

  /// Encodes raw image bytes (e.g. from a picker stream) without requiring
  /// a source file on disk. Writes the result to [destPath] and returns
  /// the result metadata.
  static Future<ProcessedImageResult> processBytes({
    required Uint8List bytes,
    required String destPath,
  }) async {
    final img.Image? original;
    try {
      original = img.decodeImage(bytes);
    } catch (e) {
      throw ImageProcessingFailure(
        'Failed to decode image bytes (${e.toString()})',
      );
    }
    if (original == null) {
      throw const ImageProcessingFailure('Unsupported image format in bytes');
    }

    final resized = _resize(original);
    final encoded = _encodeWithQualityStepping(resized);

    await File(destPath).writeAsBytes(encoded, flush: true);

    return ProcessedImageResult(
      path: destPath,
      width: resized.width,
      height: resized.height,
      byteLength: encoded.length,
      format: 'JPEG',
    );
  }

  /// Resizes [image] to fit within [maxDimension] × [maxDimension] while
  /// preserving aspect ratio.
  static img.Image _resize(img.Image image) {
    final w = image.width;
    final h = image.height;
    if (w <= maxDimension && h <= maxDimension) {
      // Already within bounds — no resize needed.
      return image;
    }
    final scale = math.min(maxDimension / w, maxDimension / h);
    return img.copyResize(
      image,
      width: (w * scale).round(),
      height: (h * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }

  /// Encodes [image] as JPEG, stepping quality from [maxQuality] downward
  /// until the result is under [maxBytes]. If the lowest-quality encoding is
  /// still too large, the image is further down-scaled and retried. If the
  /// result is below [minBytes] at [maxQuality], quality is stepped up.
  static Uint8List _encodeWithQualityStepping(img.Image image) {
    var quality = maxQuality;
    var best = img.encodeJpg(image, quality: quality);

    // Step down until under maxBytes.
    while (best.length > maxBytes && quality > minQuality) {
      quality = math.max(minQuality, quality - 8);
      best = img.encodeJpg(image, quality: quality);
    }

    // If still too large, downscale and retry.
    if (best.length > maxBytes) {
      return _encodeWithDownscale(image);
    }

    // If under minBytes, try bumping quality up to get closer to the band.
    if (best.length < minBytes && quality < maxQuality) {
      final bumpQuality = math.min(maxQuality, quality + 10);
      final bumped = img.encodeJpg(image, quality: bumpQuality);
      if (bumped.length <= maxBytes) {
        best = bumped;
      }
    }

    return best;
  }

  /// Down-scales by 50 % and retries encoding when the initial pass could
  /// not meet the byte target.
  static Uint8List _encodeWithDownscale(img.Image image) {
    var current = image;
    for (var i = 0; i < 3; i++) {
      current = img.copyResize(
        current,
        width: (current.width * 0.75).round(),
        height: (current.height * 0.75).round(),
        interpolation: img.Interpolation.linear,
      );
      var quality = maxQuality;
      var encoded = img.encodeJpg(current, quality: quality);
      while (encoded.length > maxBytes && quality > minQuality) {
        quality = math.max(minQuality, quality - 8);
        encoded = img.encodeJpg(current, quality: quality);
      }
      if (encoded.length <= maxBytes) {
        return encoded;
      }
    }
    // Last resort: return the lowest-quality encoding at smallest size.
    return img.encodeJpg(current, quality: minQuality);
  }
}

/// Result of processing a product image.
final class ProcessedImageResult {
  const ProcessedImageResult({
    required this.path,
    required this.width,
    required this.height,
    required this.byteLength,
    required this.format,
  });

  final String path;
  final int width;
  final int height;
  final int byteLength;
  final String format;
}

/// Domain failure for image processing errors.
final class ImageProcessingFailure implements Exception {
  const ImageProcessingFailure(this.message);
  final String message;

  @override
  String toString() => 'ImageProcessingFailure: $message';
}
