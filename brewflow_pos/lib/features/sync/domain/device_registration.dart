/// ---------------------------------------------------------------------------
/// BrewFlow POS — Device Registration (domain)
///
/// Identity separation enforced across Phase 6 (never merged):
///
///   DEVICE = installation uuid   (DeviceIdentity — stable per install)
///   USER   = supabase auth uid   (identity + role/permissions basis)
///   SHOP   = shops.id            (business scope)
///
/// The SAME user may own MANY devices (owner phone + tablet + …), so nothing
/// here is unique on user. Authorization stays USER-based; a device row only
///   answers "which installations exist for this shop".
/// ---------------------------------------------------------------------------
library;

/// A device installation registering itself for one shop/user binding.
final class DeviceRegistration {
  const DeviceRegistration({
    required this.deviceId,
    required this.shopId,
    required this.userId,
    this.deviceName,
    this.platform,
    this.isActive = true,
    this.lastSeenAt,
  });

  /// Stable installation UUID ([DeviceIdentity.value]).
  final String deviceId;

  /// Shop scope the installation operates in.
  final String shopId;

  /// Supabase auth user id that signed in on this installation.
  final String userId;

  /// Optional human-friendly label; informational only.
  final String? deviceName;

  /// Platform hint ('android', 'windows', …); informational only.
  final String? platform;

  /// Soft switch so a shop can retire a lost device later.
  final bool isActive;

  /// UTC instant of the registration/heartbeat.
  final DateTime? lastSeenAt;

  @override
  bool operator ==(Object other) =>
      other is DeviceRegistration &&
      other.deviceId == deviceId &&
      other.shopId == shopId &&
      other.userId == userId &&
      other.deviceName == deviceName &&
      other.platform == platform &&
      other.isActive == isActive;

  @override
  int get hashCode =>
      Object.hash(deviceId, shopId, userId, deviceName, platform, isActive);
}

/// Cloud boundary for device registration. Implementations MUST be idempotent
/// per [DeviceRegistration.deviceId] (re-registration refreshes, never
/// duplicates) and MUST NOT trust client claims beyond validating them
/// server-side against the authenticated session's shop membership.
abstract interface class RemoteDeviceGateway {
  /// Upserts the installation row for its shop. Throws on failure so callers
  /// can distinguish "stored" from "still pending".
  Future<void> registerDevice(DeviceRegistration registration);
}
