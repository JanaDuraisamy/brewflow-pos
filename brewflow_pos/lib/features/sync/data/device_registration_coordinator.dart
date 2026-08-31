import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/identity/device_identity.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/domain/device_registration.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Device Registration Coordinator
///
/// Registers THIS installation for one authenticated session, in two layers:
///
///   1. LOCAL  — Drift `devices` row (always succeeds first; the POS keeps
///      working fully offline regardless of cloud state).
///   2. REMOTE — Supabase `devices` upsert through [RemoteDeviceGateway]
///      (best-effort: offline or RLS rejection leaves the installation
///      locally registered and simply reports the cloud copy as pending).
///
/// Both layers are idempotent by device id: repeated calls refresh the
/// binding and last-seen instead of duplicating rows, which also makes every
/// successful sync cycle act as a heartbeat.
/// ---------------------------------------------------------------------------

final class DeviceRegistrationCoordinator {
  DeviceRegistrationCoordinator({
    required DriftSyncRepository syncRepository,
    required RemoteDeviceGateway remoteGateway,
    Future<String> Function()? resolveDeviceId,
  }) : _sync = syncRepository,
       _remote = remoteGateway,
       _resolveDeviceId =
           resolveDeviceId ??
           (() => DeviceIdentity.resolve().then((identity) => identity.value));

  static const String tag = 'Sync/Device';

  final DriftSyncRepository _sync;
  final RemoteDeviceGateway _remote;
  final Future<String> Function() _resolveDeviceId;

  /// Whether the current installation has a local devices row already.
  Future<bool> isRegisteredLocally(String deviceId) =>
      _sync.hasDevice(deviceId);

  /// Runs both registration layers. Returns `true` when the cloud copy is
  /// confirmed stored; `false` means local-only (cloud pending/rejected) —
  /// callers should retry on the next online transition or sync cycle.
  ///
  /// Local database failures propagate: without the local row this
  /// installation cannot participate in sync bookkeeping at all.
  Future<bool> ensureRegistered(DeviceRegistration registration) async {
    await _sync.registerDevice(
      deviceId: registration.deviceId,
      shopId: registration.shopId,
      userId: registration.userId,
      deviceName: registration.deviceName,
      platform: registration.platform,
    );
    try {
      await _remote.registerDevice(registration);
      return true;
    } catch (error, stackTrace) {
      AppLog.warning(
        'Device registration pending in cloud (will retry)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Convenience overload resolving the stable installation id itself.
  Future<bool> ensureRegisteredForSession({
    required String shopId,
    required String userId,
    String? deviceName,
    String? platform,
  }) async {
    final deviceId = await _resolveDeviceId();
    return ensureRegistered(
      DeviceRegistration(
        deviceId: deviceId,
        shopId: shopId,
        userId: userId,
        deviceName: deviceName,
        platform: platform,
        isActive: true,
        lastSeenAt: DateTime.now().toUtc(),
      ),
    );
  }
}
