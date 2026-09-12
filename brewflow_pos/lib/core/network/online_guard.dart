import 'package:brewflow_pos/core/services/connectivity_service.dart';

/// Thrown when a business mutation requires internet but none is available.
class OfflineException implements Exception {
  const OfflineException([
    this.message =
        'Internet connection required. Please check your connection and try again.',
  ]);

  final String message;

  @override
  String toString() => message;
}

/// Reusable online-only guard.

/// Phase 1 online-only: every business mutation must reject when offline
/// and must NOT create outbox entries.
class OnlineGuard {
  OnlineGuard(this._connectivity);

  final ConnectivityService _connectivity;

  /// Throws [OfflineException] when not online.
  /// Uses current snapshot first, then probes with [checkNow] for determinism.
  Future<void> requireOnline() async {
    // Fast path: already known online.
    if (_connectivity.status == ConnectivityStatus.online) return;

    // Deterministic probe (covers unknown/disconnected cases).
    final snapshot = await _connectivity.checkNow();
    if (snapshot.status != ConnectivityStatus.online) {
      throw const OfflineException();
    }
  }

  /// Synchronous check for hot paths where a fresh probe already happened.
  void requireOnlineSync() {
    if (_connectivity.status != ConnectivityStatus.online) {
      throw const OfflineException();
    }
  }
}
