import 'package:brewflow_pos/features/settings/domain/shop_name_repository.dart';

/// In-memory [ShopNameRepository] for tests. Mirrors the authoritative
/// `shops.name` row without any database or sync engine.
final class FakeShopNameRepository implements ShopNameRepository {
  String? storedName;

  /// Opaque error thrown by [currentName] when set (unless [loadError] null).
  Object? loadError;

  /// Opaque error thrown by [persist] when set.
  Object? saveError;

  /// Records every name passed to [persist].
  final List<String> persistedNames = [];

  @override
  Future<String?> currentName() async {
    if (loadError != null) {
      throw loadError!;
    }
    return storedName;
  }

  @override
  Future<void> persist(String name) async {
    if (saveError != null) {
      throw saveError!;
    }
    persistedNames.add(name);
    storedName = name;
  }
}
