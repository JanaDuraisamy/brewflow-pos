import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'system_share_service.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sharing Boundary
///
/// Business/UI code depends on this interface only; the platform share sheet
/// lives in [SystemShareService]. Sharing is strictly post-sale and must
/// never influence the transaction.
/// ---------------------------------------------------------------------------

abstract interface class ShareService {
  /// Shares [text] (a [String] receipt document) through the system share
  /// sheet with an optional [subject]. Throws on platform failure; callers
  /// surface a safe message without touching the sale.
  Future<void> shareText({required String subject, required String text});
}

final shareServiceProvider = Provider<ShareService>((ref) {
  return SystemShareService();
});
