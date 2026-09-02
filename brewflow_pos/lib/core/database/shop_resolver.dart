import 'package:brewflow_pos/core/database/app_database.dart' as db;
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Writable Shop Resolver
///
/// Replaces the legacy `shopId ?? 'cafe-id'` fallback with a real shop row
/// resolution. When [shopId] is provided, it is used directly (the FK will
/// validate). When null, the single existing shop is returned — or a Cafe
/// shop is created for backward-compatible single-shop databases.
///
/// This mirrors the `ensureShop()` pattern used by
/// [BusinessSwitcherController] and is safe for both production and tests.
/// ---------------------------------------------------------------------------

Future<String> resolveWritableShopId(
  db.AppDatabase database, [
  String? shopId,
]) async {
  if (shopId != null) return shopId;
  final rows = await database.select(database.shops).get();
  if (rows.isNotEmpty) return rows.first.id;
  // Legacy single-shop: the first write auto-creates a Cafe shop.
  final id = const Uuid().v4();
  await database
      .into(database.shops)
      .insert(db.ShopsCompanion.insert(id: Value(id), name: 'Cafe'));
  return id;
}
