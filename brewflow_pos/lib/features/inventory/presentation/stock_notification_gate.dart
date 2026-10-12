import 'dart:convert';

import 'package:brewflow_pos/core/notifications/stock_notification_deduper.dart';
import 'package:brewflow_pos/core/notifications/stock_notification_service.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock notification gate (dedup + persistence).
///
/// Sits between [stockAlertsProvider] and the system gateway: each alert
/// list is diffed against the last-notified state ([decideStockNotifications])
/// so only new keys and low→out escalations produce a system notification —
/// never one per rebuild/open. State persists in prefs
/// (`brewflow_stock_notified_keys`) so a restart does not re-notify the same
/// shelf, while resolved-then-recurring shortages honestly re-notify.
///
/// Permission denial is session-cached and never fatal: denied means skip
/// (without advancing state, so a later grant still notifies).
/// ---------------------------------------------------------------------------

/// Gateway override point: production wires the Flutter-local plugin, widget
/// tests override with a fake. Defaults to noop off Android so desktop and
/// bare unit tests never touch a platform channel.
final stockNotificationGatewayProvider = Provider<StockNotificationGateway>((
  ref,
) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return NoopStockNotificationGateway();
  }
  return FlutterLocalStockNotifications();
});

final stockNotificationGateProvider = Provider<StockNotificationGate>((ref) {
  return StockNotificationGate(ref.watch(stockNotificationGatewayProvider));
});

final class StockNotificationGate {
  StockNotificationGate(this._gateway);

  static const String _prefsKey = 'brewflow_stock_notified_keys';

  final StockNotificationGateway _gateway;

  Map<String, int> _known = {};
  bool _loaded = false;
  bool _permissionAsked = false;
  bool _allowed = false;

  /// Serializes concurrent syncs: alert-list emissions can arrive faster than
  /// the prefs round-trip, and overlapping diffs against a stale [_known]
  /// would notify twice for one shelf state.
  Future<void> _tail = Future.value();

  /// Diffs [alerts] against the last-notified state and shows only genuine
  /// transitions. Safe to call on every alert-list rebuild.
  Future<void> syncAlerts(List<StockAlert> alerts) {
    final next = _tail.then((_) => _syncAlerts(alerts));
    // A dropped sync must never jam later ones behind it.
    _tail = next.catchError((_) {});
    return next;
  }

  Future<void> _syncAlerts(List<StockAlert> alerts) async {
    try {
      await _loadOnce();
      if (!_permissionAsked) {
        _permissionAsked = true;
        _allowed = await _gateway.ensurePermission();
      }
      if (!_allowed) return;
      final decision = decideStockNotifications(known: _known, current: alerts);
      for (final alert in decision.toNotify) {
        await _gateway.showAlert(alert);
      }
      _known = decision.nextKnown;
      await _save();
    } catch (error, stackTrace) {
      AppLog.warning(
        'Stock notification sync skipped (no crash)',
        tag: 'StockNotify',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadOnce() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await AppStorage.preferences.readString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = const JsonDecoder().convert(raw);
      if (decoded is Map<String, dynamic>) {
        _known = {
          for (final entry in decoded.entries)
            if (entry.value is num) entry.key: (entry.value as num).toInt(),
        };
      }
    } catch (_) {
      // Unavailable store (bare tests) or corrupt value: start fresh.
      _known = {};
    }
  }

  Future<void> _save() async {
    try {
      await AppStorage.preferences.writeString(
        _prefsKey,
        const JsonEncoder().convert(_known),
      );
    } catch (_) {
      // Persistence is best-effort; in-memory state still dedups the session.
    }
  }
}
