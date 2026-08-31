import 'package:share_plus/share_plus.dart';

import 'share_service.dart';

/// Platform implementation backed by `share_plus` (system share sheet:
/// WhatsApp, email, nearby, etc. — whatever the OS offers).
final class SystemShareService implements ShareService {
  const SystemShareService();

  @override
  Future<void> shareText({
    required String subject,
    required String text,
  }) async {
    await Share.share(text, subject: subject);
  }
}
