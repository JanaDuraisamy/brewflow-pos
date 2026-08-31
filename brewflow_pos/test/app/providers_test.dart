import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

void main() {
  group('appDatabaseProvider', () {
    test('shares a single instance per scope and disposes cleanly', () async {
      final container = ProviderContainer();

      final database = container.read(appDatabaseProvider);
      expect(container.read(appDatabaseProvider), same(database));

      container.dispose();
      // No exception expected: the lazy connection was never opened.
    });
  });

  group('connectivityServiceProvider', () {
    test('shares a single instance per scope and disposes cleanly', () {
      final container = ProviderContainer();

      final service = container.read(connectivityServiceProvider);
      expect(container.read(connectivityServiceProvider), same(service));

      container.dispose();
    });

    test('can be overridden with a fake service (DI-friendly)', () {
      final fake = ConnectivityService(
        transportStream: Stream<List<ConnectivityResult>>.empty(),
        checkTransport: () async => const [],
        reachabilityStream: Stream<InternetStatus>.empty(),
        checkReachability: () async => InternetStatus.disconnected,
      );
      final container = ProviderContainer(
        overrides: [connectivityServiceProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      expect(container.read(connectivityServiceProvider), same(fake));
    });
  });
}
