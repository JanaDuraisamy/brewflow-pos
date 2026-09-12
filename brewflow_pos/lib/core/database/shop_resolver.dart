import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Writable Shop Resolver
///
/// Replaces the legacy `shopId ?? 'cafe-id'` fallback with a real shop row
/// resolution. When [shopId] is provided, it is used directly (the FK will
/// validate).
///
/// When null, the shop bound to the locally provisioned profile is the
/// authoritative target — the same shop the sync identity pushes and mints
/// memberships for (`profile.shopId`). The OWNER profile wins; any provisioned
/// profile is used as a fallback. This prevents single-shop fallback from
/// accidentally selecting a stale legacy `shops` row (e.g. an auto-created
/// orphan left over from an earlier single-shop boot) whose cloud identity
/// never existed — a profile-bound shop always carries a real cloud identity.
///
/// Pre-bootstrap databases (no profiles yet) keep the legacy single-shop
/// resolution: first existing row, or a Cafe shop auto-created for the first
/// write. That preserves all single-shop / fresh-install behavior.
/// ---------------------------------------------------------------------------

Future<String> resolveWritableShopId(
  db.AppDatabase database, [
  String? shopId,
]) async {
  if (shopId != null) return shopId;
  final authoritative = await _authoritativeProfileShopId(database);
  if (authoritative != null) return authoritative;
  final rows = await database.select(database.shops).get();
  if (rows.isNotEmpty) return rows.first.id;
  // Legacy single-shop: the first write auto-creates a Cafe shop.
  final id = const Uuid().v4();
  await database
      .into(database.shops)
      .insert(db.ShopsCompanion.insert(id: Value(id), name: 'Cafe'));
  return id;
}

/// The shop bound to the local OWNER profile (authoritative), falling back to
/// any provisioned profile's shop. Null when no profile carries a shop id yet.
Future<String?> _authoritativeProfileShopId(db.AppDatabase database) async {
  final profiles = await database.select(database.users).get();
  String? fallback;
  for (final profile in profiles) {
    final shop = profile.shopId;
    if (shop == null || shop.isEmpty) continue;
    if (profile.role == 'OWNER') return shop;
    fallback ??= shop;
  }
  return fallback;
}
