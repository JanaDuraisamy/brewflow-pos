import 'package:brewflow_pos/core/notifications/stock_notification_payload.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock system notifications (local Android).
///
/// Smallest production-safe solution over `flutter_local_notifications`:
/// one channel (`brewflow_stock`), titles/bodies identifying shop + product,
/// stable per-entity notification ids (same alert updates one row), tap
/// payload deep-links to the exact Inventory product via
/// [encodeStockAlertTap]. No remote push infrastructure is introduced (see
/// limitations below).
///
/// Safety rules:
/// - Every platform call is guarded: permission denial, missing plugin or a
///   background isolate failure degrades to silent skip, never a crash, never
///   broken navigation.
/// - Permission is requested lazily on first sync ([ensurePermission]);
///   denial means notifications are skipped for the session.
/// - Foreground/background taps route through [onTap]; terminated-launch
///   taps are exposed via [consumeLaunchPayload].
///
/// LIMITATION (reported, not claimed): these are LOCAL notifications for
/// stock transitions the app itself observes while running. Cloud changes
/// arriving while the app is fully terminated cannot notify without
/// push/background infrastructure, which this project does not have.
/// ---------------------------------------------------------------------------

/// Local stock channel (created on init).
const String stockNotificationChannelId = 'brewflow_stock';
const String stockNotificationChannelName = 'Stock Alerts';

/// Display strings for system notifications.
String stockNotificationTitle(StockAlert alert) => switch (alert.kind) {
  StockAlertKind.outOfStock => 'Out of stock: ${alert.displayName}',
  StockAlertKind.lowStock => 'Low stock: ${alert.displayName}',
};

String stockNotificationBody(StockAlert alert) {
  final shop = alert.shopId == null ? '' : ' · ${_shortShop(alert.shopId!)}';
  return switch (alert.kind) {
    StockAlertKind.outOfStock =>
      '${alert.displayName} is out of stock$shop. Restock to keep selling.',
    StockAlertKind.lowStock =>
      '${alert.displayName}: ${alert.stock} left'
          '${alert.threshold == null ? '' : ' (min ${alert.threshold})'}$shop.',
  };
}

String _shortShop(String shopId) =>
    shopId.length > 8 ? '${shopId.substring(0, 8)}…' : shopId;

/// Gateway boundary so tests drive a fake and the app degrades to noop off
/// Android (widget tests, desktop).
abstract interface class StockNotificationGateway {
  Future<void> init(Future<void> Function(String? payload) onTap);
  Future<bool> ensurePermission();
  Future<void> showAlert(StockAlert alert);
  Future<String?> consumeLaunchPayload();
}

final class FlutterLocalStockNotifications implements StockNotificationGateway {
  FlutterLocalStockNotifications([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  @override
  Future<void> init(Future<void> Function(String? payload) onTap) async {
    if (_ready) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (response) => onTap(response.payload),
      );
      const channel = AndroidNotificationChannel(
        stockNotificationChannelId,
        stockNotificationChannelName,
        description: 'Low and out-of-stock alerts for shop inventory.',
        importance: Importance.high,
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(channel);
      _ready = true;
    } catch (error, stackTrace) {
      AppLog.warning(
        'Stock notifications unavailable; continuing without system alerts',
        tag: 'StockNotify',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> ensurePermission() async {
    try {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      // Null (older Android, no runtime gate) means allowed.
      return granted ?? true;
    } catch (error, stackTrace) {
      AppLog.warning(
        'Stock notification permission check failed; skipping alerts',
        tag: 'StockNotify',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  @override
  Future<void> showAlert(StockAlert alert) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        stockNotificationChannelId,
        stockNotificationChannelName,
        channelDescription: 'Low and out-of-stock alerts for shop inventory.',
        importance: Importance.high,
        priority: Priority.high,
      );
      const details = NotificationDetails(android: androidDetails);
      await _plugin.show(
        _stableId(alert.key),
        stockNotificationTitle(alert),
        stockNotificationBody(alert),
        details,
        payload: encodeStockAlertTap(
          productId: alert.productId,
          variantId: alert.variantId,
          shopId: alert.shopId,
        ),
      );
    } catch (error, stackTrace) {
      AppLog.warning(
        'Stock system notification dropped (no crash)',
        tag: 'StockNotify',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<String?> consumeLaunchPayload() async {
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        return launch?.notificationResponse?.payload;
      }
    } catch (error, stackTrace) {
      AppLog.warning(
        'Stock launch-payload read failed',
        tag: 'StockNotify',
        error: error,
        stackTrace: stackTrace,
      );
    }
    return null;
  }

  /// Stable non-negative id per alert key so one entity updates one system
  /// row instead of stacking duplicates.
  static int _stableId(String key) => key.hashCode & 0x7fffffff;
}

/// Silent fallback for tests and non-Android platforms.
final class NoopStockNotificationGateway implements StockNotificationGateway {
  @override
  Future<void> init(Future<void> Function(String? payload) onTap) async {}

  @override
  Future<bool> ensurePermission() async => false;

  @override
  Future<void> showAlert(StockAlert alert) async {}

  @override
  Future<String?> consumeLaunchPayload() async => null;
}
