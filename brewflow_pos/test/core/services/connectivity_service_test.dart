import 'dart:async';

import 'package:brewflow_pos/core/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// In-memory stand-in for the platform plugins. Drive it with the exposed
/// controllers; the probe results answer the initial `init()` determination.
class _FakeConnectivitySource {
  int transportListenCount = 0;
  int reachabilityListenCount = 0;

  late final StreamController<List<ConnectivityResult>> transportController =
      StreamController<List<ConnectivityResult>>.broadcast(
        onListen: () => transportListenCount++,
      );
  late final StreamController<InternetStatus> reachabilityController =
      StreamController<InternetStatus>.broadcast(
        onListen: () => reachabilityListenCount++,
      );

  List<ConnectivityResult> probeTransport;
  InternetStatus probeReachability;
  bool throwOnTransportProbe = false;

  _FakeConnectivitySource({
    this.probeTransport = const [ConnectivityResult.none],
    this.probeReachability = InternetStatus.disconnected,
  });

  ConnectivityService build() => ConnectivityService(
    transportStream: transportController.stream,
    checkTransport: () async {
      if (throwOnTransportProbe) {
        throw StateError('platform unavailable');
      }
      return probeTransport;
    },
    reachabilityStream: reachabilityController.stream,
    checkReachability: () async => probeReachability,
  );

  Future<void> dispose() async {
    await transportController.close();
    await reachabilityController.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('initial state', () {
    test('status is unknown before init', () {
      final service = _FakeConnectivitySource().build();
      expect(service.status, ConnectivityStatus.unknown);
      expect(service.snapshot.status, ConnectivityStatus.unknown);
    });
  });

  group('initial determination (init)', () {
    test('no network -> disconnected', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.disconnected);
      expect(service.snapshot.internetReachable, isFalse);
      expect(service.snapshot.transports, [NetworkTransport.none]);
    });

    test('transport available but no internet -> disconnected', () async {
      final source = _FakeConnectivitySource(
        probeTransport: const [ConnectivityResult.wifi],
        probeReachability: InternetStatus.disconnected,
      );
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.disconnected);
      expect(service.snapshot.transports, [NetworkTransport.wifi]);
    });

    test('transport + internet -> online', () async {
      final source = _FakeConnectivitySource(
        probeTransport: const [ConnectivityResult.mobile],
        probeReachability: InternetStatus.connected,
      );
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.online);
      expect(service.snapshot.transports, [NetworkTransport.mobile]);
      expect(service.snapshot.internetReachable, isTrue);
    });

    test('probe failure degrades to disconnected without crashing', () async {
      final source = _FakeConnectivitySource()..throwOnTransportProbe = true;
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.disconnected);
    });
  });

  group('state changes', () {
    test('transport loss while online -> disconnected', () async {
      final source = _FakeConnectivitySource(
        probeTransport: const [ConnectivityResult.wifi],
        probeReachability: InternetStatus.connected,
      );
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.online);

      source.transportController.add([ConnectivityResult.none]);
      await Future<void>.delayed(Duration.zero);
      expect(service.status, ConnectivityStatus.disconnected);

      source.transportController.add([ConnectivityResult.wifi]);
      await Future<void>.delayed(Duration.zero);
      expect(service.status, ConnectivityStatus.online);
    });

    test(
      'reachability change while transport present -> state changes',
      () async {
        final source = _FakeConnectivitySource(
          probeTransport: const [ConnectivityResult.wifi],
          probeReachability: InternetStatus.connected,
        );
        final service = source.build();
        await service.init();

        source.reachabilityController.add(InternetStatus.disconnected);
        await Future<void>.delayed(Duration.zero);
        expect(service.status, ConnectivityStatus.disconnected);

        source.reachabilityController.add(InternetStatus.connected);
        await Future<void>.delayed(Duration.zero);
        expect(service.status, ConnectivityStatus.online);
      },
    );

    test('stream emits snapshots and deduplicates identical states', () async {
      final source = _FakeConnectivitySource(
        probeTransport: const [ConnectivityResult.wifi],
        probeReachability: InternetStatus.connected,
      );
      final service = source.build();
      final events = <ConnectivitySnapshot>[];
      final sub = service.snapshots.listen(events.add);
      await service.init();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.length, 1);
      expect(events.single.status, ConnectivityStatus.online);

      source.reachabilityController.add(InternetStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.length, 2);
      expect(events.last.status, ConnectivityStatus.disconnected);
      expect(events.last.transports, [NetworkTransport.wifi]);

      source.reachabilityController.add(InternetStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events.length, 2, reason: 'duplicate event must be deduplicated');

      source.transportController.add([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        events.length,
        3,
        reason: 'transport change emits even when status is unchanged',
      );
      expect(events.last.transports, [NetworkTransport.none]);
      expect(events.last.status, ConnectivityStatus.disconnected);
      await sub.cancel();
    });

    test('checkNow re-probes on demand', () async {
      final source = _FakeConnectivitySource(
        probeTransport: const [ConnectivityResult.wifi],
        probeReachability: InternetStatus.disconnected,
      );
      final service = source.build();
      await service.init();
      expect(service.status, ConnectivityStatus.disconnected);

      source.probeReachability = InternetStatus.connected;
      final snapshot = await service.checkNow();
      expect(snapshot.status, ConnectivityStatus.online);
      expect(service.status, ConnectivityStatus.online);
    });
  });

  group('lifecycle', () {
    test('init is idempotent and subscribes exactly once', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.init();
      await service.init();
      await service.init();
      expect(source.transportListenCount, 1);
      expect(source.reachabilityListenCount, 1);
      await service.dispose();
    });

    test('init after dispose throws StateError', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.dispose();
      expect(service.init(), throwsStateError);
    });

    test('dispose cancels subscriptions and closes the stream', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.init();
      await service.dispose();

      expect(source.transportListenCount, 1);
      await expectLater(service.snapshots, emitsDone);
    });

    test('events after dispose are ignored without crashing', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.init();
      await service.dispose();

      source.transportController.add([ConnectivityResult.wifi]);
      source.reachabilityController.add(InternetStatus.connected);
      expect(service.status, ConnectivityStatus.disconnected);
    });

    test('dispose is idempotent', () async {
      final source = _FakeConnectivitySource();
      final service = source.build();
      await service.init();
      await service.dispose();
      await service.dispose();
    });
  });
}
