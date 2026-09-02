import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'shops.dart';

/// ---------------------------------------------------------------------------
/// Categories — product grouping
///
/// Unique identity, name, active/inactive state and UTC timestamps.
/// ---------------------------------------------------------------------------

@TableIndex(name: 'idx_categories_shop', columns: {#shopId})
@TableIndex(name: 'idx_categories_updated_at', columns: {#shopId, #updatedAt})
class Categories extends Table {
  /// Local UUID v4 identifier, generated on this device.
  TextColumn get id => text().clientDefault(() => Uuid().v4())();

  @override
  Set<Column> get primaryKey => {id};

  /// Business/shop that owns this category.
  TextColumn get shopId =>
      text().nullable().references(Shops, #id, onDelete: KeyAction.cascade)();

  /// Category name. Unique per shop so each business's menu stays unambiguous.
  TextColumn get name => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {shopId, name},
  ];

  /// Soft switch to hide a category (and its products from new orders)
  /// without deleting data.
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// UTC timestamp of record creation.
  DateTimeColumn get createdAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();

  /// UTC timestamp of the last change; drives future sync.
  DateTimeColumn get updatedAt =>
      dateTime().clientDefault(() => DateTime.now().toUtc())();
}
