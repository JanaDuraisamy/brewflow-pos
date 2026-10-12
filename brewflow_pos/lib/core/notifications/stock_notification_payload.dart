/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock system-notification tap payload codec.
///
/// Payloads are plain strings (`stock|<productId>|<variantId|->|<shopId|->`)
/// carried by the local notification. Decoding is total and never throws:
/// a malformed payload yields null and the tap is ignored, so a bad payload
/// can never break navigation.
/// ---------------------------------------------------------------------------
library;

/// Encodes a stock-alert deep link. `null` ids encode as `-`.
String encodeStockAlertTap({
  required String productId,
  String? variantId,
  String? shopId,
}) => 'stock|$productId|${variantId ?? '-'}|${shopId ?? '-'}';

/// Decoded tap target, or null when [payload] is not a stock payload.
({String productId, String? variantId, String? shopId})? decodeStockAlertTap(
  String? payload,
) {
  if (payload == null || payload.isEmpty) return null;
  final parts = payload.split('|');
  if (parts.length != 4 || parts[0] != 'stock') return null;
  if (parts[1].isEmpty || parts[1] == '-') return null;
  String? orNull(String part) => part.isEmpty || part == '-' ? null : part;
  return (
    productId: parts[1],
    variantId: orNull(parts[2]),
    shopId: orNull(parts[3]),
  );
}
