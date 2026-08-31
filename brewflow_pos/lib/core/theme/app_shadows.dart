import 'package:flutter/widgets.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System
/// App Shadows
///
/// Subtle, professional elevation matching the approved reference style.
/// Elevation is never heavy:
/// - [xs] resting cards on white content areas
/// - [sm] default card elevation
/// - [md] dialogs, popovers, floating elements
/// - [lg] overlays and side panels
/// ---------------------------------------------------------------------------

final class AppShadows {
  AppShadows._();

  static const BoxShadow xs = BoxShadow(
    color: Color(0x0A0F172A),
    blurRadius: 3,
    offset: Offset(0, 1),
  );

  static const BoxShadow sm = BoxShadow(
    color: Color(0x0D0F172A),
    blurRadius: 6,
    offset: Offset(0, 2),
  );

  static const List<BoxShadow> md = [
    BoxShadow(color: Color(0x0F0F172A), blurRadius: 8, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6)),
  ];

  static const List<BoxShadow> lg = [
    BoxShadow(color: Color(0x140F172A), blurRadius: 12, offset: Offset(0, 4)),
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 28, offset: Offset(0, 10)),
  ];
}
