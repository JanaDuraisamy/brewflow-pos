import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// BrewFlow POS — Offers table
///
/// Business-scoped promotional offers. Each row belongs to exactly one shop/
/// business (Cafe or Food Truck) via `shopId`. Owner Phone creates/edits,
/// tablets receive only their business's offers.
@DataClassName('Offer')
@TableIndex(name: 'idx_offers_shop', columns: {#shopId})
@TableIndex(name: 'idx_offers_shop_active', columns: {#shopId, #isActive})
class Offers extends Table {
  @override
  String get tableName => 'offers';

  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this offer.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  /// Offer type wire value: PERCENTAGE | COMBO | BUY_X_GET_Y
  TextColumn get type => text().customConstraint(
    "CHECK (type IN ('PERCENTAGE','COMBO','BUY_X_GET_Y')) NOT NULL",
  )();

  /// JSON config: percentage, combo price, buyXGetY numbers, productIds, etc.
  TextColumn get configJson => text().named('config_json')();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get startAt => dateTime().nullable()();

  DateTimeColumn get endAt => dateTime().nullable()();

  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  @override
  List<Set<Column>> get uniqueKeys => [];

  @override
  List<String> get customConstraints => [
    'CHECK (start_at IS NULL OR end_at IS NULL OR start_at <= end_at)',
  ];
}
