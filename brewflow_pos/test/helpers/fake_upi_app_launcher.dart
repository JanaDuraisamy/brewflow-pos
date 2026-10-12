import 'dart:async';

import 'package:brewflow_pos/features/expenses/data/upi_app_launcher.dart';

/// In-memory [UpiAppLauncher] for widget tests.
///
/// Widget tests must never depend on real installed UPI apps: seed [apps]
/// (PhonePe / Google Pay / Paytm by default), fail launches on demand with
/// [launchError], or hold launches open with [launchGate] to prove the sheet
/// disables repeat launches while one is in flight.
final class FakeUpiAppLauncher implements UpiAppLauncher {
  FakeUpiAppLauncher({List<UpiAppInfo>? apps})
    : _apps =
          apps ??
          const [
            UpiAppInfo(
              packageName: 'com.google.android.apps.nbu.paisa.user',
              displayName: 'Google Pay',
            ),
            UpiAppInfo(packageName: 'com.phonepe.app', displayName: 'PhonePe'),
            UpiAppInfo(packageName: 'net.one97.paytm', displayName: 'Paytm'),
          ];

  List<UpiAppInfo> _apps;

  // ignore: avoid_setters_without_getters
  set apps(List<UpiAppInfo> value) => _apps = value;

  /// When set, [installedUpiApps] throws this instead of listing apps.
  Object? listError;

  /// When set, [launchUpiApp] throws this instead of recording the launch.
  Object? launchError;

  /// When set, launches wait until released (launch-guard tests).
  Completer<void>? launchGate;

  /// Every launch call, in order.
  final List<
    ({String packageName, String amountRupees, String currency, String? note})
  >
  launches = [];

  @override
  Future<List<UpiAppInfo>> installedUpiApps() async {
    final error = listError;
    if (error != null) throw error;
    return List.of(_apps);
  }

  @override
  Future<void> launchUpiApp({
    required String packageName,
    required String amountRupees,
    String currency = 'INR',
    String? note,
  }) async {
    final gate = launchGate;
    if (gate != null) await gate.future;
    final error = launchError;
    if (error != null) throw error;
    launches.add((
      packageName: packageName,
      amountRupees: amountRupees,
      currency: currency,
      note: note,
    ));
  }
}
