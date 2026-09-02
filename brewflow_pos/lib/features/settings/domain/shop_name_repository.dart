/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shop-Name Repository Contract
///
/// The shop display name has ONE authoritative local home: the Drift `shops`
/// row (and its cloud `shops.name` mirror). SharedPreferences is only a local
/// fast-render cache; it is never the cross-device source of truth.
///
/// [ShopsRepository] exposes the authoritative read/write used by the
/// settings feature so that rename flows persist locally AND enqueue a SHOP
/// outbox entry for cross-device propagation.
/// ---------------------------------------------------------------------------
library;

abstract interface class ShopNameRepository {
  /// The current authoritative shop name from the local `shops` row, or null
  /// when no shop has been bootstrapped yet (pre-owner / signed-out).
  Future<String?> currentName();

  /// Persists [name] as the authoritative shop name AND (when a sync session
  /// context resolves) enqueues a SHOP outbox entry so other devices pull it.
  ///
  /// Best-effort: offline-first, never throws on sync unavailability.
  Future<void> persist(String name);
}
