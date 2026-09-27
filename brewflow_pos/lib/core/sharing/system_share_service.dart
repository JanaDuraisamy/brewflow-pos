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

  @override
  Future<void> shareFile({
    required String subject,
    required String filePath,
  }) async {
    await Share.shareXFiles([XFile(filePath)], subject: subject);
  }

  @override
  Future<void> shareFiles({
    required String subject,
    required List<String> filePaths,
  }) async {
    await Share.shareXFiles([
      for (final path in filePaths) XFile(path),
    ], subject: subject);
  }
}
