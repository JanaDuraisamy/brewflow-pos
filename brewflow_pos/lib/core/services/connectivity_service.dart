import 'dart:async';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Connectivity Service
///
/// Monitors two distinct signals and merges them into one application-level
/// connectivity state:
///
/// 1. **Network transport** — whether the device is attached to a network
///    (Wi-Fi, mobile, ethernet, ...) as reported by `connectivity_plus`.
/// 2. **Internet reachability** — whether an actual internet endpoint is
///    reachable, as reported by `internet_connection_checker_plus`.
///
/// A device connected to a network is NOT considered online until an internet
/// reachability check succeeds (e.g. a router without a WAN link).
///
/// Consumers must use the typed [NetworkTransport], [InternetStatus]-agnostic
/// [ConnectivitySnapshot] and [ConnectivityStatus] models instead of raw
/// plugin values, so feature modules never depend on the packages directly.
///
/// The service is Riverpod-independent: ownership will be handed to a provider
/// in a later step.
/// ---------------------------------------------------------------------------

/// Physical network interfaces reported by the platform.
enum NetworkTransport {
  none,
  wifi,
  mobile,
  ethernet,
  vpn,
  bluetooth,
  other;

  /// Maps a `connectivity_plus` transport result to the app-level type.
  static NetworkTransport from(ConnectivityResult result) => switch (result) {
    ConnectivityResult.none => NetworkTransport.none,
    ConnectivityResult.wifi => NetworkTransport.wifi,
    ConnectivityResult.mobile => NetworkTransport.mobile,
    ConnectivityResult.ethernet => NetworkTransport.ethernet,
    ConnectivityResult.vpn => NetworkTransport.vpn,
    ConnectivityResult.bluetooth => NetworkTransport.bluetooth,
    ConnectivityResult.satellite => NetworkTransport.other,
    ConnectivityResult.other => NetworkTransport.other,
  };
}

/// Application-level connectivity state.
enum ConnectivityStatus {
  /// Not determined yet (before the first successful check).
  unknown,

  /// No transport available, or transport present but no internet reachability.
  disconnected,

  /// Transport present AND internet reachable.
  online,
}

/// Immutable, app-level view of the connectivity at a point in time.
@immutable
class ConnectivitySnapshot {
  const ConnectivitySnapshot({
    required this.transports,
    required this.internetReachable,
    required this.status,
  });

  /// All currently active transports. Empty or [NetworkTransport.none]-only
  /// means the device is attached to no network.
  final List<NetworkTransport> transports;

  /// Whether an actual internet endpoint was reachable in the last check.
  final bool internetReachable;

  /// Combined application-level state.
  final ConnectivityStatus status;

  @override
  bool operator ==(Object other) =>
      other is ConnectivitySnapshot &&
      other.status == status &&
      other.internetReachable == internetReachable &&
      listEquals(other.transports, transports);

  @override
  int get hashCode =>
      Object.hash(status, internetReachable, Object.hashAll(transports));
}

/// Monitors network transport and internet reachability and exposes a single
/// typed state stream.
///
/// All plugin access happens through constructor-injected streams and probe
/// callbacks, so tests can drive the service with in-memory fakes and the
/// application never hard-codes static package APIs.
final class ConnectivityService {
  /// Default interval between automatic internet reachability checks.
  static const Duration defaultReachabilityInterval = Duration(seconds: 10);

  /// Wires the real platform plugins into a [ConnectivityService].
  ///
  /// [reachabilityInterval] controls how often the internet checker re-probes
  /// endpoints while the device is idle on a network.
  factory ConnectivityService.create({
    Duration reachabilityInterval = defaultReachabilityInterval,
  }) {
    final connectivity = Connectivity();
    final internet = InternetConnection.createInstance(
      checkInterval: reachabilityInterval,
    );
    return ConnectivityService(
      transportStream: connectivity.onConnectivityChanged,
      checkTransport: connectivity.checkConnectivity,
      reachabilityStream: internet.onStatusChange,
      checkReachability: () => internet.internetStatus,
    );
  }

  /// Test-friendly constructor: every plugin interaction is replaceable.
  ConnectivityService({
    required this._transportStream,
    required this._checkTransport,
    required this._reachabilityStream,
    required this._checkReachability,
  });

  final Stream<List<ConnectivityResult>> _transportStream;
  final Future<List<ConnectivityResult>> Function() _checkTransport;
  final Stream<InternetStatus> _reachabilityStream;
  final Future<InternetStatus> Function() _checkReachability;

  final StreamController<ConnectivitySnapshot> _controller =
      StreamController<ConnectivitySnapshot>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _transportSub;
  StreamSubscription<InternetStatus>? _reachabilitySub;

  List<NetworkTransport> _transports = const [NetworkTransport.none];
  bool _internetReachable = false;
  ConnectivityStatus _status = ConnectivityStatus.unknown;
  ConnectivitySnapshot? _lastEmitted;
  bool _initialized = false;
  bool _disposed = false;
  bool _checkInFlight = false;

  /// Current application-level connectivity status.
  ConnectivityStatus get status => _status;

  /// Latest known connectivity state (no allocation surprises, immutable).
  ConnectivitySnapshot get snapshot => ConnectivitySnapshot(
    transports: List.unmodifiable(_transports),
    internetReachable: _internetReachable,
    status: _status,
  );

  /// Stream of connectivity state changes. Emits only when something actually
  /// changed; identical states are deduplicated.
  Stream<ConnectivitySnapshot> get snapshots => _controller.stream;

  /// Performs the initial state determination and starts monitoring.
  ///
  /// Idempotent: repeated calls are no-ops until [dispose]. Safe to call
  /// concurrently. Subscriptions are attached only after the initial state is
  /// determined, so the first snapshot is never lost to a race.
  Future<void> init() async {
    if (_disposed) {
      throw StateError(
        'ConnectivityService: init() is not allowed after dispose().',
      );
    }
    if (_initialized) {
      return;
    }
    _initialized = true;

    final transports = await _safeTransportProbe();
    final reachable = await _safeReachabilityProbe();
    _transports = transports;
    _internetReachable = reachable;
    _publish();

    _attachSubscriptions();
  }

  /// Re-probes transport and internet reachability immediately and publishes
  /// the merged result. Concurrent calls are collapsed into one check.
  Future<ConnectivitySnapshot> checkNow() async {
    if (_checkInFlight) {
      return snapshot;
    }
    _checkInFlight = true;
    try {
      final transportsFuture = _safeTransportProbe();
      final reachableFuture = _safeReachabilityProbe();
      _transports = await transportsFuture;
      _internetReachable = await reachableFuture;
      _publish();
      return snapshot;
    } finally {
      _checkInFlight = false;
    }
  }

  /// Stops monitoring and releases all resources. Idempotent. The service must
  /// not be used after this call.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _transportSub?.cancel();
    await _reachabilitySub?.cancel();
    _transportSub = null;
    _reachabilitySub = null;
    await _controller.close();
  }

  void _attachSubscriptions() {
    _transportSub = _transportStream.listen(
      _onTransportEvent,
      onError: _onStreamError,
    );
    _reachabilitySub = _reachabilityStream.listen(
      _onReachabilityEvent,
      onError: _onStreamError,
    );
  }

  void _onTransportEvent(List<ConnectivityResult> results) {
    if (_disposed) {
      return;
    }
    _transports = results.map(NetworkTransport.from).toList(growable: false);
    _publish();
  }

  void _onReachabilityEvent(InternetStatus status) {
    if (_disposed) {
      return;
    }
    _internetReachable = status == InternetStatus.connected;
    _publish();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    AppLog.error(
      'ConnectivityService: monitor stream error; using last known state.',
      tag: 'connectivity',
      error: error,
      stackTrace: stackTrace,
    );
  }

  Future<List<NetworkTransport>> _safeTransportProbe() async {
    try {
      final results = await _checkTransport();
      return results.map(NetworkTransport.from).toList(growable: false);
    } catch (error, stackTrace) {
      AppLog.error(
        'ConnectivityService: transport probe failed; treating as none.',
        tag: 'connectivity',
        error: error,
        stackTrace: stackTrace,
      );
      return const [NetworkTransport.none];
    }
  }

  Future<bool> _safeReachabilityProbe() async {
    try {
      return await _checkReachability() == InternetStatus.connected;
    } catch (error, stackTrace) {
      AppLog.error(
        'ConnectivityService: reachability probe failed; '
        'treating as unreachable.',
        tag: 'connectivity',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  void _publish() {
    if (_disposed) {
      return;
    }
    final previous = _status;
    _status = _resolveStatus(_transports, _internetReachable);

    final next = ConnectivitySnapshot(
      transports: List.unmodifiable(_transports),
      internetReachable: _internetReachable,
      status: _status,
    );
    if (_lastEmitted == next) {
      return;
    }
    _lastEmitted = next;
    _controller.add(next);

    if (_status != previous) {
      AppLog.info(
        'Connectivity: ${_status.name} '
        '(${_transports.map((t) => t.name).join('+')})',
        tag: 'connectivity',
      );
    }
  }

  static ConnectivityStatus _resolveStatus(
    List<NetworkTransport> transports,
    bool internetReachable,
  ) {
    final hasTransport = transports.any((t) => t != NetworkTransport.none);
    if (!hasTransport) {
      return ConnectivityStatus.disconnected;
    }
    return internetReachable
        ? ConnectivityStatus.online
        : ConnectivityStatus.disconnected;
  }
}
