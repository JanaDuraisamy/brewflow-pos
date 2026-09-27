// One-off branding generator: builds the JiggarTea Bill LAUNCHER/APP icons
// from the square cup-mark logo, on a brand-green tile so they read clearly
// at small sizes. Platform icons that previously used the wide wordmark JPEG
// (which rendered as a faint white square) are regenerated here.
//
//   dart run tool/generate_brand_assets.dart
//
// The in-app inner logo (assets/images/brand_logo.png) is intentionally
// regenerated from the same source, byte-for-byte unchanged.
// Uses the `image` package already declared in pubspec.yaml.

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Square cup-mark logo (transparent-ized: white background removed).
const String _sourceInner =
    r'P:\New folder\web image\New folder\inner logo.jpeg';

/// Legacy (non-adaptive) Android launcher tiles, brand tile + cup.
const List<(int, String)> _androidMipmaps = [
  (48, r'android\app\src\main\res\mipmap-mdpi\ic_launcher.png'),
  (72, r'android\app\src\main\res\mipmap-hdpi\ic_launcher.png'),
  (96, r'android\app\src\main\res\mipmap-xhdpi\ic_launcher.png'),
  (144, r'android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png'),
  (192, r'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'),
];

/// Adaptive-icon foregrounds (108dp canvas; cup kept inside the safe zone).
const List<(int, String)> _androidForegrounds = [
  (108, r'android\app\src\main\res\mipmap-mdpi\ic_launcher_foreground.png'),
  (162, r'android\app\src\main\res\mipmap-hdpi\ic_launcher_foreground.png'),
  (216, r'android\app\src\main\res\mipmap-xhdpi\ic_launcher_foreground.png'),
  (324, r'android\app\src\main\res\mipmap-xxhdpi\ic_launcher_foreground.png'),
  (432, r'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher_foreground.png'),
];

const List<(int, String)> _webIcons = [
  (192, r'web\icons\Icon-192.png'),
  (512, r'web\icons\Icon-512.png'),
  (32, r'web\favicon.png'),
];

const List<(int, String)> _macIcons = [
  (16, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_16.png'),
  (32, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_32.png'),
  (64, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_64.png'),
  (128, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_128.png'),
  (256, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_256.png'),
  (512, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_512.png'),
  (1024, r'macos\Runner\Assets.xcassets\AppIcon.appiconset\app_icon_1024.png'),
];

const String _iosDir = r'ios\Runner\Assets.xcassets\AppIcon.appiconset';

const List<(int, String)> _iosIcons = [
  (20, 'Icon-App-20x20@1x.png'),
  (40, 'Icon-App-20x20@2x.png'),
  (60, 'Icon-App-20x20@3x.png'),
  (29, 'Icon-App-29x29@1x.png'),
  (58, 'Icon-App-29x29@2x.png'),
  (87, 'Icon-App-29x29@3x.png'),
  (40, 'Icon-App-40x40@1x.png'),
  (80, 'Icon-App-40x40@2x.png'),
  (120, 'Icon-App-40x40@3x.png'),
  (120, 'Icon-App-60x60@2x.png'),
  (180, 'Icon-App-60x60@3x.png'),
  (76, 'Icon-App-76x76@1x.png'),
  (152, 'Icon-App-76x76@2x.png'),
  (167, 'Icon-App-83.5x83.5@2x.png'),
  (1024, 'Icon-App-1024x1024@1x.png'),
];

const String _windowsIco = r'windows\runner\resources\app_icon.ico';

const String _innerLogo = r'assets\images\brand_logo.png';

/// Brand tile gradient (matches AppGradients.brand): #2E7D32 → #1B5E20.
const int _brandTop = 0x2E7D32;
const int _brandBottom = 0x1B5E20;

/// Corner radius ratio for the baked tile (Android legacy icon).
const double _tileRadiusRatio = 0.25;

void _writePng(String path, img.Image image) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(image));
  stdout.writeln('wrote $path (${image.width}x${image.height})');
}

void _writeText(String path, String content) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  stdout.writeln('wrote $path');
}

int _lerpChannel(int a, int b, double t) =>
    (a + (b - a) * t).round().clamp(0, 255);

int _lerpColor(int a, int b, double t) {
  final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
  final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
  final r = _lerpChannel(ar, br, t);
  final g = _lerpChannel(ag, bg, t);
  final bl = _lerpChannel(ab, bb, t);
  return (r << 16) | (g << 8) | bl;
}

/// Brand-green diagonal tile (top-left bright → bottom-right dark), optional
/// baked rounded corners.
img.Image _brandTile(int size, {required bool rounded}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final t = ((x / size) + (y / size)) / 2;
      final c = _lerpColor(_brandTop, _brandBottom, t);
      canvas.setPixelRgba(
        x,
        y,
        (c >> 16) & 0xFF,
        (c >> 8) & 0xFF,
        c & 0xFF,
        rounded
            ? _roundAlpha(x, y, size, (size * _tileRadiusRatio).round())
            : 255,
      );
    }
  }
  return canvas;
}

int _roundAlpha(int x, int y, int size, int r) {
  final dx = x < r ? r - x : (x >= size - r ? x - (size - 1 - r) : 0);
  final dy = y < r ? r - y : (y >= size - r ? y - (size - 1 - r) : 0);
  if (dx == 0 || dy == 0) return 255;
  return (dx * dx + dy * dy <= r * r) ? 255 : 0;
}

/// Removes the white background of the source JPEG so the cup mark is isolated.
img.Image _extractCup(img.Image source) {
  final out = img.Image(
    width: source.width,
    height: source.height,
    numChannels: 4,
  );
  for (var y = 0; y < source.height; y++) {
    for (var x = 0; x < source.width; x++) {
      final p = source.getPixel(x, y);
      final transparent = p.r >= 228 && p.g >= 228 && p.b >= 228;
      final a = transparent ? 0 : 255;
      out.setPixelRgba(x, y, p.r, p.g, p.b, a);
    }
  }
  return out;
}

/// Full app icon: brand tile + centered cup mark.
img.Image _appIcon(
  img.Image cup,
  int size, {
  required bool rounded,
  required double cupScale,
}) {
  final canvas = _brandTile(size, rounded: rounded);
  final cupSize = (size * cupScale).round();
  final cupResized = img.copyResize(
    cup,
    width: cupSize,
    height: cupSize,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    cupResized,
    dstX: (size - cupSize) ~/ 2,
    dstY: (size - cupSize) ~/ 2,
    blend: img.BlendMode.alpha,
  );
  return canvas;
}

/// Transparent canvas with the cup mark centered (adaptive-icon foreground).
img.Image _cupOnly(img.Image cup, int size, {required double cupScale}) {
  final canvas = img.Image(width: size, height: size, numChannels: 4);
  img.fill(canvas, color: img.ColorRgba8(0, 0, 0, 0));
  final cupSize = (size * cupScale).round();
  final cupResized = img.copyResize(
    cup,
    width: cupSize,
    height: cupSize,
    interpolation: img.Interpolation.cubic,
  );
  img.compositeImage(
    canvas,
    cupResized,
    dstX: (size - cupSize) ~/ 2,
    dstY: (size - cupSize) ~/ 2,
    blend: img.BlendMode.alpha,
  );
  return canvas;
}

/// Writes a single-image PNG-compressed ICO (256x256 entry).
void _writeIco(String path, img.Image image) {
  final png = img.encodePng(image);
  final data = BytesBuilder();
  data.add([0, 0, 1, 0]); // ICONDIR reserved + type=1
  data.add([1, 0]); // count = 1
  // ICONDIRENTRY: 256x256 -> width/height bytes = 0
  data.add([0, 0, 0, 0]);
  data.add([1, 0, 32, 0]); // planes=1, bitCount=32
  data.add([
    (png.length & 0xFF),
    ((png.length >> 8) & 0xFF),
    ((png.length >> 16) & 0xFF),
    ((png.length >> 24) & 0xFF),
  ]);
  data.add([22, 0, 0, 0]); // imageOffset = 6 + 16 = 22
  data.add(png);
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(data.toBytes());
  stdout.writeln('wrote $path (ICO 256x256 PNG payload)');
}

void main() {
  final innerSrc = img.decodeImage(File(_sourceInner).readAsBytesSync())!;
  final cup = _extractCup(innerSrc);

  for (final (size, path) in _androidMipmaps) {
    _writePng(path, _appIcon(cup, size, rounded: true, cupScale: 0.62));
  }
  // Android 8+ adaptive icon: gradient background drawable + cup foreground.
  for (final (size, path) in _androidForegrounds) {
    _writePng(path, _cupOnly(cup, size, cupScale: 0.5));
  }
  _writeText(
    r'android\app\src\main\res\mipmap-anydpi-v26\ic_launcher.xml',
    '''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''',
  );
  _writeText(
    r'android\app\src\main\res\drawable\ic_launcher_background.xml',
    '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <gradient
        android:type="linear"
        android:angle="315"
        android:startColor="#2E7D32"
        android:endColor="#1B5E20"/>
</shape>
''',
  );

  for (final (size, path) in _webIcons) {
    _writePng(path, _appIcon(cup, size, rounded: false, cupScale: 0.6));
  }
  // Maskable web icons are full-bleed; content stays inside the safe zone.
  _writePng(
    r'web\icons\Icon-maskable-192.png',
    _appIcon(cup, 192, rounded: false, cupScale: 0.52),
  );
  _writePng(
    r'web\icons\Icon-maskable-512.png',
    _appIcon(cup, 512, rounded: false, cupScale: 0.52),
  );

  for (final (size, path) in _macIcons) {
    _writePng(path, _appIcon(cup, size, rounded: false, cupScale: 0.6));
  }
  for (final (size, name) in _iosIcons) {
    _writePng(
      '$_iosDir\\$name',
      _appIcon(cup, size, rounded: false, cupScale: 0.6),
    );
  }
  _writeIco(_windowsIco, _appIcon(cup, 256, rounded: false, cupScale: 0.6));

  // In-app inner logo: kept byte-identical to the current asset.
  _writePng(_innerLogo, innerSrc);
  stdout.writeln('done');
}
