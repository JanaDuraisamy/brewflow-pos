import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Hermetic [ConnectivityService] for tests.
///
/// Wired to inert in-memory streams: transport is always "none" and internet
/// reachability always fails, so the resolved status is
/// [ConnectivityStatus.disconnected]. No platform plugins and no timers are
/// ever touched, which keeps widget tests deterministic (nothing is left
/// pending that could hang `pumpAndSettle`).
ConnectivityService fakeConnectivityService() => ConnectivityService(
  transportStream: const Stream<List<ConnectivityResult>>.empty(),
  checkTransport: () async => const [ConnectivityResult.none],
  reachabilityStream: const Stream<InternetStatus>.empty(),
  checkReachability: () async => InternetStatus.disconnected,
);

ConnectivityService fakeConnectivityServiceOnline() => ConnectivityService(
  transportStream: const Stream<List<ConnectivityResult>>.empty(),
  checkTransport: () async => const [ConnectivityResult.wifi],
  reachabilityStream: const Stream<InternetStatus>.empty(),
  checkReachability: () async => InternetStatus.connected,
);
