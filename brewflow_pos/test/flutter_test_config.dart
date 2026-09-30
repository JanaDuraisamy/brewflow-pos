import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter faces into the test font collection.
///
/// Without this, widget tests never resolve the `Inter` family declared in
/// `pubspec.yaml`: `flutter test` does not register `fonts:` assets for you, so
/// every `Text` silently falls back to the test runner's default font. That font
/// is roughly 1.9x wider than Inter, so a message that occupies two lines on a
/// device occupies three in the test, and fixed-height stacks overflow. Those
/// failures look like layout bugs but are really a phantom font, and they hide
/// genuine ones.
///
/// Loading the real faces makes the tests measure the same metrics the app
/// ships, so a height asserted here holds on a device.
Future<void> loadAppFonts() async {
  for (final asset in const [
    'assets/fonts/Inter-Regular.ttf',
    'assets/fonts/Inter-Medium.ttf',
    'assets/fonts/Inter-SemiBold.ttf',
    'assets/fonts/Inter-Bold.ttf',
  ]) {
    final loader = FontLoader('Inter')..addFont(rootBundle.load(asset));
    await loader.load();
  }
}

/// Applies to every test in the suite, matching the font the app declares.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadAppFonts();
  await testMain();
}
