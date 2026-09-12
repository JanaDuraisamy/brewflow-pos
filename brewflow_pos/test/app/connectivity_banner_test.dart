import 'dart:async';

import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/app/widgets/connectivity_banner.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// Hermetic [ConnectivityService] for the banner tests, mirroring
/// `fakeConnectivityService()` but with a chosen end state.
ConnectivityService serviceWith(ConnectivityStatus status) {
  final transports = status == ConnectivityStatus.online
      ? const [ConnectivityResult.wifi]
      : const [ConnectivityResult.none];
  final reachable = status == ConnectivityStatus.online
      ? InternetStatus.connected
      : InternetStatus.disconnected;
  return ConnectivityService(
    transportStream: const Stream<List<ConnectivityResult>>.empty(),
    checkTransport: () async => transports,
    reachabilityStream: const Stream<InternetStatus>.empty(),
    checkReachability: () async => reachable,
  );
}

/// A service whose initial state can never resolve — connectivity is still
/// "checking" (no plugins respond, no probe completes).
ConnectivityService pendingService() {
  final never = Completer<List<ConnectivityResult>>();
  final neverReachability = Completer<InternetStatus>();
  return ConnectivityService(
    transportStream: const Stream<List<ConnectivityResult>>.empty(),
    checkTransport: () => never.future,
    reachabilityStream: const Stream<InternetStatus>.empty(),
    checkReachability: () => neverReachability.future,
  );
}

void main() {
  Widget app(ConnectivityService service) => ProviderScope(
    overrides: [connectivityServiceProvider.overrideWithValue(service)],
    child: const MaterialApp(home: Scaffold(body: ConnectivityBanner())),
  );

  group('ConnectivityBanner', () {
    testWidgets('renders the offline notice when disconnected', (tester) async {
      await tester.pumpWidget(
        app(serviceWith(ConnectivityStatus.disconnected)),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('No Internet Connection'), findsOneWidget);
      expect(find.byIcon(Icons.wifi_off_outlined), findsOneWidget);
    });

    testWidgets('renders nothing while online', (tester) async {
      await tester.pumpWidget(app(serviceWith(ConnectivityStatus.online)));
      await tester.pumpAndSettle();

      expect(find.textContaining('No Internet Connection'), findsNothing);
    });

    testWidgets('renders nothing while connectivity is undetermined', (
      tester,
    ) async {
      await tester.pumpWidget(app(pendingService()));
      await tester.pump();

      expect(find.textContaining('No Internet Connection'), findsNothing);
    });
  });
}
