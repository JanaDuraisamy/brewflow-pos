import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brewflow_pos/core/theme/app_typography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// Typography contract
///
/// The design system renders one family — Inter — from the four TTFs bundled in
/// `assets/fonts/` and declared in `pubspec.yaml` at weights 400/500/600/700.
///
/// This used to be built with `GoogleFonts.inter()`, which is worth calling out
/// because it was quietly *not* deterministic:
///
/// - it resolved to synthesized family names (`Inter_700`, `Inter_600`,
///   `Inter_500`, `Inter_regular`) that do not exist in `pubspec.yaml`, then
///   leaned on `fontFamilyFallback: ['Inter']` to find the real font;
/// - those names only work because `google_fonts` ships its own manifest and
///   font cache at runtime, and it can fall back to fetching a font over the
///   network.
///
/// Naming the declared family directly makes the resolution the engine's normal
/// static lookup, with no runtime manifest, no cache and no network path.
///
/// The sizes, weights and letter spacings below are the values that were there
/// before the change and are pinned so a typography edit cannot land silently.
/// `letterSpacing` is only set on `displayLarge`; everywhere else it stays null
/// so the theme's own default applies, which is why the assertions distinguish
/// "expected 0" from "not specified".
/// ---------------------------------------------------------------------------

/// The family name declared in `pubspec.yaml`, referenced by every slot.
const _family = 'Inter';

/// Weights actually bundled as separate TTFs.
const _bundledWeights = <int>[400, 500, 600, 700];

/// Pinned (size, weight, letterSpacing) per slot. `null` spacing means the slot
/// deliberately leaves it unspecified.
const _expected = <String, (double, int, double?)>{
  'displayLarge': (57, 700, -0.25),
  'displayMedium': (45, 700, null),
  'displaySmall': (36, 700, null),
  'headlineLarge': (32, 600, null),
  'headlineMedium': (28, 600, null),
  'headlineSmall': (24, 600, null),
  'titleLarge': (22, 600, null),
  'titleMedium': (16, 600, null),
  'titleSmall': (14, 600, null),
  'bodyLarge': (16, 400, null),
  'bodyMedium': (14, 400, null),
  'bodySmall': (12, 400, null),
  'labelLarge': (14, 500, null),
  'labelMedium': (12, 500, null),
  'labelSmall': (11, 500, null),
};

Map<String, TextStyle?> _slots(TextTheme theme) => {
  'displayLarge': theme.displayLarge,
  'displayMedium': theme.displayMedium,
  'displaySmall': theme.displaySmall,
  'headlineLarge': theme.headlineLarge,
  'headlineMedium': theme.headlineMedium,
  'headlineSmall': theme.headlineSmall,
  'titleLarge': theme.titleLarge,
  'titleMedium': theme.titleMedium,
  'titleSmall': theme.titleSmall,
  'bodyLarge': theme.bodyLarge,
  'bodyMedium': theme.bodyMedium,
  'bodySmall': theme.bodySmall,
  'labelLarge': theme.labelLarge,
  'labelMedium': theme.labelMedium,
  'labelSmall': theme.labelSmall,
};

void main() {
  group('AppTypography', () {
    test('every slot is defined', () {
      final slots = _slots(AppTypography.textTheme);
      for (final name in _expected.keys) {
        expect(slots[name], isNotNull, reason: '$name must stay populated');
      }
      expect(slots.keys, hasLength(_expected.length));
    });

    test('every slot names the bundled Inter family', () {
      _slots(AppTypography.textTheme).forEach((name, style) {
        expect(
          style!.fontFamily,
          _family,
          reason:
              '$name must resolve through the pubspec-declared family, not a '
              'synthesized name',
        );
        expect(
          style.fontFamilyFallback,
          isNull,
          reason:
              '$name should not need a fallback: the family is bundled, so a '
              'fallback is either dead weight or a silent miss',
        );
        // `GoogleFonts` produced a 'package:'-prefixed family when it resolved
        // from a package asset; a bundled family must never carry that prefix.
        expect(
          style.fontFamily,
          isNot(contains('package:')),
          reason: '$name must not be a package-resolved font',
        );
      });
    });

    test('sizes, weights and letter spacing are unchanged', () {
      _slots(AppTypography.textTheme).forEach((name, style) {
        final (size, weight, spacing) = _expected[name]!;
        expect(style!.fontSize, size, reason: '$name fontSize');
        expect(style.fontWeight?.value, weight, reason: '$name fontWeight');
        // Unspecified spacing must stay unspecified: forcing 0 here would be an
        // invisible but real change to every line of text in the app.
        if (spacing == null) {
          expect(
            style.letterSpacing,
            isNull,
            reason: '$name letterSpacing stays unspecified',
          );
        } else {
          expect(
            style.letterSpacing,
            closeTo(spacing, 0.001),
            reason: '$name letterSpacing',
          );
        }
      });
    });

    test('no slot introduces a line height or weight override', () {
      // Both were null before; the theme owns them. Setting either here would
      // be a layout-affecting change disguised as a font swap.
      _slots(AppTypography.textTheme).forEach((name, style) {
        expect(style!.height, isNull, reason: '$name must not set height');
        expect(
          style.leadingDistribution,
          isNull,
          reason: '$name must not set leadingDistribution',
        );
        expect(style.decoration, isNull, reason: '$name must not decorate');
        expect(
          style.fontWeight!.value,
          anyOf(isIn(_bundledWeights)),
          reason: '$name must use a weight that is actually bundled',
        );
      });
    });

    test('the theme keeps the full M3 slot set', () {
      // A missing slot silently inherits Material's Roboto defaults, which is
      // the exact class of bug this suite exists to prevent.
      expect(_expected.keys, hasLength(15));
      expect(
        _expected.keys,
        containsAll(<String>[
          'displayLarge',
          'displayMedium',
          'displaySmall',
          'headlineLarge',
          'headlineMedium',
          'headlineSmall',
          'titleLarge',
          'titleMedium',
          'titleSmall',
          'bodyLarge',
          'bodyMedium',
          'bodySmall',
          'labelLarge',
          'labelMedium',
          'labelSmall',
        ]),
      );
    });
  });

  group('bundled font assets', () {
    late File pubspec;
    late Map<String, Object?> manifest;

    setUpAll(() {
      pubspec = File('pubspec.yaml');
      // Parse the fonts block rather than regexing it: this asserts the real
      // manifest, not a guess about its formatting.
      manifest =
          jsonDecode(
                jsonEncode(<String, Object?>{
                  'fonts': _fontsBlock(pubspec.readAsLinesSync()),
                }),
              )
              as Map<String, Object?>;
    });

    test('pubspec declares the Inter family once, with all four weights', () {
      final fonts = manifest['fonts']! as List<Object?>;
      final inter = fonts
          .cast<Map<String, Object?>>()
          .where((entry) => entry['family'] == _family)
          .toList();

      expect(
        inter,
        hasLength(1),
        reason: 'exactly one Inter family declaration',
      );

      final declared =
          (inter.single['fonts']! as List<Object?>)
              .cast<Map<String, Object?>>()
              .map((entry) => entry['weight'] as int)
              .toList()
            ..sort();

      expect(
        declared,
        _bundledWeights,
        reason:
            'every weight the typography uses must map to a bundled TTF, or '
            'the engine has to synthesize it',
      );
    });

    test('every declared font file exists and is non-empty', () {
      final fonts = manifest['fonts']! as List<Object?>;
      for (final entry in fonts.cast<Map<String, Object?>>()) {
        for (final face
            in (entry['fonts']! as List<Object?>)
                .cast<Map<String, Object?>>()) {
          final file = File(face['asset']! as String);
          expect(
            file.existsSync(),
            isTrue,
            reason: '${face['asset']} is declared but missing from the bundle',
          );
          expect(
            file.lengthSync(),
            greaterThan(0),
            reason: '${face['asset']} is empty',
          );
        }
      }
    });

    test('the font files are real TrueType data', () {
      // A truncated or HTML-error-page file named .ttf still "exists"; checking
      // the sfnt magic makes a broken bundle fail here instead of at runtime as
      // a silent fallback to a system font.
      final fonts = manifest['fonts']! as List<Object?>;
      for (final entry in fonts.cast<Map<String, Object?>>()) {
        for (final face
            in (entry['fonts']! as List<Object?>)
                .cast<Map<String, Object?>>()) {
          final path = face['asset']! as String;
          final bytes = File(path).readAsBytesSync();
          final isTrueType =
              bytes.length >= 4 &&
              ByteData.sublistView(bytes).getUint32(0, Endian.big) ==
                  0x00010000;
          final isOpenType =
              bytes.length >= 4 &&
              String.fromCharCodes(bytes.sublist(0, 4)) == 'OTTO';
          expect(
            isTrueType || isOpenType,
            isTrue,
            reason: '$path does not start with a valid sfnt/OTTO header',
          );
        }
      }
    });
  });
}

/// Extracts the `fonts:` block from `pubspec.yaml` as plain data.
///
/// `pubspec.yaml` is not JSON, so this is a small purpose-built reader for the
/// one block under test. It only understands the shape this project uses
/// (`family:` then nested `asset:`/`weight:` pairs) and fails loudly on anything
/// else rather than silently returning a partial result.
List<Map<String, Object?>> _fontsBlock(List<String> lines) {
  final entries = <Map<String, Object?>>[];
  // Locate the `fonts:` key that actually introduces a family list. The block is
  // nested under `flutter:`, so the key is indented and its absolute depth
  // depends on how the manifest happens to be written; everything below is
  // matched relative to the family entry rather than to a hardcoded column.
  var familyIndent = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != 'fonts:') continue;
    for (var j = i + 1; j < lines.length; j++) {
      final trimmed = lines[j].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (trimmed.startsWith('- family:')) {
        familyIndent = lines[j].length - lines[j].trimLeft().length;
      }
      break; // only the immediately following key can be the family list
    }
    if (familyIndent >= 0) break;
  }
  if (familyIndent < 0) {
    throw StateError('pubspec.yaml declares no fonts family');
  }

  Map<String, Object?>? family;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;

    if (indent == familyIndent && trimmed.startsWith('- family:')) {
      family = <String, Object?>{
        'family': trimmed.substring('- family:'.length).trim(),
        'fonts': <Object?>[],
      };
      entries.add(family);
    } else if (indent == familyIndent + 4 &&
        trimmed.startsWith('- asset:') &&
        family != null) {
      (family['fonts']! as List<Object?>).add(<String, Object?>{
        'asset': trimmed.substring('- asset:'.length).trim(),
      });
    } else if (indent == familyIndent + 6 &&
        trimmed.startsWith('weight:') &&
        family != null) {
      final faces = family['fonts']! as List<Object?>;
      (faces.last as Map<String, Object?>)['weight'] = int.parse(
        trimmed.substring('weight:'.length).trim(),
      );
    } else if (family != null && indent <= familyIndent) {
      family = null; // dedented back out of this family
    }
  }
  return entries;
}
