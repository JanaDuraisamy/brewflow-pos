import 'dart:io';
import 'dart:typed_data';

import 'package:brewflow_pos/features/inventory/data/product_image_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Product Image Processor (Todo: cloud sync)
///
/// Pure-Dart resize/compress/encode: verifies the 800×800 cover bounds, the
/// JPEG output format and byte accumulation toward the 100–300 KB band across
/// a representative set of source sizes (small, oversized, huge). All IO is
/// in temporary directories; no platform channels.
/// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('brewflow_processor_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Builds a deterministic RGB test image of the given size as [File] bytes.
  File imageFile(int width, int height, {String name = 'src'}) {
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(x, y, (x * 7) % 256, (y * 5) % 256, (x + y) % 256);
      }
    }
    final bytes = img.encodeJpg(image, quality: 90);
    final file = File('${tempDir.path}/$name.jpg');
    file.writeAsBytesSync(bytes);
    return file;
  }

  group('ProductImageProcessor.process', () {
    test(
      'download bound: a huge image is scaled to fit within 800×800',
      () async {
        final src = imageFile(3200, 2400);
        final result = await ProductImageProcessor.process(
          sourcePath: src.path,
        );

        expect(
          result.width,
          lessThanOrEqualTo(ProductImageProcessor.maxDimension),
        );
        expect(
          result.height,
          lessThanOrEqualTo(ProductImageProcessor.maxDimension),
        );
        expect(result.format, 'JPEG');

        final out = File(result.path);
        expect(out.existsSync(), isTrue);
        expect(out.lengthSync(), result.byteLength);
      },
    );

    test('aspect ratio is preserved under resize', () async {
      // 4:3 landscape that exceeds 800 on both axes → 800×600.
      final src = imageFile(1600, 1200);
      final result = await ProductImageProcessor.process(sourcePath: src.path);

      expect(result.width, ProductImageProcessor.maxDimension);
      expect(result.height, 600);
    });

    test('small images are not upscaled beyond their source', () async {
      // 400×300 is already within bounds — no resize.
      final src = imageFile(400, 300);
      final result = await ProductImageProcessor.process(sourcePath: src.path);

      expect(result.width, 400);
      expect(result.height, 300);
    });

    test('output target lands at or under 300 KB', () async {
      final src = imageFile(1200, 900);
      final result = await ProductImageProcessor.process(sourcePath: src.path);

      expect(
        result.byteLength,
        lessThanOrEqualTo(ProductImageProcessor.maxBytes),
        reason: 'quality stepping + downscale must cap the byte size',
      );
    });

    test('output is a decodable JPEG', () async {
      final src = imageFile(1200, 900);
      final result = await ProductImageProcessor.process(sourcePath: src.path);

      final decoded = img.decodeImage(File(result.path).readAsBytesSync());
      expect(decoded, isNotNull);
      expect(decoded!.width, result.width);
      expect(decoded.height, result.height);
    });

    test('writes to a provided destPath', () async {
      final src = imageFile(800, 600);
      final dest = '${tempDir.path}/out/custom.jpg';
      Directory('${tempDir.path}/out').createSync();
      final result = await ProductImageProcessor.process(
        sourcePath: src.path,
        destPath: dest,
      );

      expect(result.path, dest);
      expect(File(dest).existsSync(), isTrue);
    });

    test('throws ImageProcessingFailure for a missing source', () async {
      await expectLater(
        ProductImageProcessor.process(
          sourcePath: '${tempDir.path}/does_not_exist.jpg',
        ),
        throwsA(isA<ImageProcessingFailure>()),
      );
    });
  });

  group('ProductImageProcessor.processBytes', () {
    test('resizes and encodes raw bytes to a dest file', () async {
      final image = img.Image(width: 2000, height: 1000);
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));
      final dest = '${tempDir.path}/bytes_out.jpg';

      final result = await ProductImageProcessor.processBytes(
        bytes: bytes,
        destPath: dest,
      );

      expect(result.width, ProductImageProcessor.maxDimension);
      expect(result.height, 400);
      expect(File(dest).existsSync(), isTrue);
      expect(result.format, 'JPEG');
    });

    test('throws ImageProcessingFailure for undecodable bytes', () async {
      await expectLater(
        ProductImageProcessor.processBytes(
          bytes: Uint8List.fromList([1, 2, 3, 4, 5]),
          destPath: '${tempDir.path}/bad.jpg',
        ),
        throwsA(isA<ImageProcessingFailure>()),
      );
    });
  });
}
