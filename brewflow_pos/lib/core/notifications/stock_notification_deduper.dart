import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Stock notification dedup decision (pure).
///
/// The app must never spam a system notification on every rebuild/open: only
/// genuine stock-state transitions notify —
///   - a brand-new alert key, or
///   - a low-stock key escalating to out-of-stock.
///
/// Resolved keys leave [known] so a recurring shortage re-notifies honestly.
/// Everything is keyed by [StockAlert.key] (`shop|product|variant`), so the
/// same entity can never produce two notifications for one state.
/// ---------------------------------------------------------------------------

/// Decides which of [current] deserve a system notification given [known]
/// (key → kind index from the last sync). Returns the alerts to show and the
/// next persisted state (exactly the current keys).
({List<StockAlert> toNotify, Map<String, int> nextKnown})
decideStockNotifications({
  required Map<String, int> known,
  required List<StockAlert> current,
}) {
  final toNotify = <StockAlert>[];
  final nextKnown = <String, int>{};
  for (final alert in current) {
    nextKnown[alert.key] = alert.kind.index;
    final previous = known[alert.key];
    if (previous == null) {
      toNotify.add(alert);
    } else if (previous != alert.kind.index &&
        alert.kind == StockAlertKind.outOfStock) {
      // Escalation only: low → out. An out → low change is the shelf being
      // restocked, which clears the key path via [nextKnown] without noise.
      // (previous out + current low cannot normally happen since out beats
      // low per entity, but the guard keeps the direction explicit.)
      toNotify.add(alert);
    }
  }
  return (toNotify: toNotify, nextKnown: nextKnown);
}
