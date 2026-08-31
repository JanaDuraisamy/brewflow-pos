import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — WhatsApp Verification Boundary
///
/// Honest reachability status for a customer phone number. A *valid* phone
/// number is NOT proof of a WhatsApp account, so VERIFIED can only ever come
/// from a real verification provider.
///
/// CURRENT REALITY: no verification provider is integrated. The default
/// binding reports UNAVAILABLE for every lookup and nothing in the app may
/// present a green "verified" indicator unless a provider returned verified.
///
/// Future integration shape (documented contract):
///   Customer UI → WhatsAppVerificationService → server-side boundary
///   (Edge Function holding the Meta/WhatsApp Business API credentials) →
///   provider response mapped to [WhatsAppStatus]. Credentials must stay on
///   the server; never in Flutter/.env shipped to clients.
/// ---------------------------------------------------------------------------

/// Reachability state of a customer's phone number on WhatsApp.
enum WhatsAppStatus {
  /// No verification has been attempted yet (initial state).
  unknown('UNKNOWN'),

  /// A real provider confirmed a WhatsApp account exists for this number.
  verified('VERIFIED'),

  /// A real provider confirmed no WhatsApp account exists for this number.
  notVerified('NOT_VERIFIED'),

  /// Verification could not be performed (no provider configured, network
  /// or provider failure).
  unavailable('UNAVAILABLE');

  const WhatsAppStatus(this.dbValue);

  /// Database-storage value, kept stable for history.
  final String dbValue;

  /// Parses a stored DB value (e.g. 'NOT_VERIFIED'). Falls back to [unknown]
  /// for anything unrecognized so corrupted rows can never fabricate a
  /// verified state.
  static WhatsAppStatus fromDbValue(String value) => WhatsAppStatus.values
      .firstWhere((status) => status.dbValue == value, orElse: () => unknown);

  /// User-facing wording used consistently across the app.
  String get label => switch (this) {
    WhatsAppStatus.unknown => 'WhatsApp: Not verified',
    WhatsAppStatus.verified => '✓ WhatsApp',
    WhatsAppStatus.notVerified => 'WhatsApp: Not on WhatsApp',
    WhatsAppStatus.unavailable => 'WhatsApp verification unavailable',
  };
}

/// Contract for a real verification provider. Implementations must be
/// server-backed (credentials server-side) and map their raw response onto
/// [WhatsAppStatus] values only — never invent states from formatting.
abstract interface class WhatsAppVerificationService {
  /// Verifies whether [phoneNumberE164] (canonical E.164) currently has a
  /// WhatsApp account. Returns an honest status; throws typed failures for
  /// transport problems rather than guessing.
  Future<WhatsAppStatus> verify(String phoneNumberE164);
}

/// Default binding while no provider exists: every request honestly reports
/// [WhatsAppStatus.unavailable]. Replaced via provider override when a real,
/// server-backed integration lands.
final class UnavailableWhatsAppVerificationService
    implements WhatsAppVerificationService {
  const UnavailableWhatsAppVerificationService();

  @override
  Future<WhatsAppStatus> verify(String phoneNumberE164) async {
    return WhatsAppStatus.unavailable;
  }
}

/// Composition root. Tests override with fakes; production replaces with a
/// real server-backed implementation when available.
final whatsappVerificationServiceProvider =
    Provider<WhatsAppVerificationService>((ref) {
      return const UnavailableWhatsAppVerificationService();
    });
