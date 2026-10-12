import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — UPI App Discovery & Launch Seam
///
/// The payable-payment sheet offers a UPI handoff: list the installed apps
/// that can handle a UPI payment intent, launch the one the owner picks, and
/// — only after the owner returns and manually confirms — record the payment
/// through the existing payable flow. Nothing here verifies money movement:
/// launching or returning from an app is never payment success, and the
/// recorded row is the owner's manual attestation.
///
/// Platform split:
/// - Android: [MethodChannelUpiAppLauncher] asks PackageManager (behind a
///   narrow `<queries>` declaration) which apps resolve the UPI VIEW intent
///   and launches the chosen package explicitly.
/// - Everywhere else: [UnavailableUpiAppLauncher] reports no apps, so the
///   sheet falls back to the existing manual record workflow.
/// ---------------------------------------------------------------------------

/// One installed app that can handle the UPI payment intent.
final class UpiAppInfo {
  const UpiAppInfo({required this.packageName, required this.displayName});

  /// Android application id, used to launch this exact app.
  final String packageName;

  /// Human-readable label from the package manager.
  final String displayName;
}

/// A launch/discovery failure. Always user-safe display text: the sheet
/// shows it and keeps the manual record workflow available.
final class UpiLauncherException implements Exception {
  const UpiLauncherException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Discovers installed UPI apps and launches the chosen one. Implementations
/// must never claim anything about whether money moved.
abstract interface class UpiAppLauncher {
  /// Apps on this device that resolve the UPI payment intent, sorted by
  /// display name. Empty on platforms without UPI app discovery.
  Future<List<UpiAppInfo>> installedUpiApps();

  /// Opens [packageName] with a best-effort UPI payment URI carrying
  /// [amountRupees] (validated `1000.00` shape), [currency] and [note].
  ///
  /// The URI is a handoff hint, not a payment request: the payee address is
  /// unknown to BrewFlow, so the owner completes and confirms the payment in
  /// the UPI app. Throws [UpiLauncherException] when the app is gone or the
  /// launch fails.
  Future<void> launchUpiApp({
    required String packageName,
    required String amountRupees,
    String currency = 'INR',
    String? note,
  });
}

/// Android implementation over `brewflow_pos/upi` (see MainActivity).
final class MethodChannelUpiAppLauncher implements UpiAppLauncher {
  MethodChannelUpiAppLauncher({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('brewflow_pos/upi');

  final MethodChannel _channel;

  @override
  Future<List<UpiAppInfo>> installedUpiApps() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'getInstalledUpiApps',
      );
      if (raw == null) return const [];
      final apps = <UpiAppInfo>[];
      for (final entry in raw) {
        if (entry is! Map) continue;
        final packageName = entry['packageName'];
        final displayName = entry['displayName'];
        if (packageName is! String ||
            packageName.isEmpty ||
            displayName is! String ||
            displayName.isEmpty) {
          continue;
        }
        apps.add(
          UpiAppInfo(packageName: packageName, displayName: displayName),
        );
      }
      return apps;
    } on PlatformException catch (error) {
      throw UpiLauncherException(
        error.message ?? 'Could not list the installed UPI apps.',
      );
    }
  }

  @override
  Future<void> launchUpiApp({
    required String packageName,
    required String amountRupees,
    String currency = 'INR',
    String? note,
  }) async {
    try {
      await _channel.invokeMethod('launchUpiApp', <String, Object?>{
        'packageName': packageName,
        'amountRupees': amountRupees,
        'currency': currency,
        'note': note,
      });
    } on PlatformException catch (error) {
      throw UpiLauncherException(
        error.message ?? 'Could not open the selected UPI app.',
      );
    }
  }
}

/// Non-Android implementation: no discovery, so the sheet keeps the manual
/// record workflow with no UPI-specific UI beyond the method picker itself.
final class UnavailableUpiAppLauncher implements UpiAppLauncher {
  const UnavailableUpiAppLauncher();

  @override
  Future<List<UpiAppInfo>> installedUpiApps() async => const [];

  @override
  Future<void> launchUpiApp({
    required String packageName,
    required String amountRupees,
    String currency = 'INR',
    String? note,
  }) {
    throw const UpiLauncherException('UPI apps are only available on Android.');
  }
}

/// Owns the UPI launcher for the application scope (override with a fake in
/// widget tests; widget tests must never depend on real installed apps).
final upiAppLauncherProvider = Provider<UpiAppLauncher>((ref) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    return MethodChannelUpiAppLauncher();
  }
  return const UnavailableUpiAppLauncher();
});
