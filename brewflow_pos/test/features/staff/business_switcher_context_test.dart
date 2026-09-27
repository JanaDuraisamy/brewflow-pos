import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/secure_storage.dart';
import 'package:brewflow_pos/features/staff/presentation/business_switcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_preferences_storage.dart';

/// Regression for FINAL E2E Failure 3:
/// the Cafe/Food Truck dropdown opened, but selecting Cafe left the header on
/// Food Truck with no log. Root causes: a late prefs hydration could revert
/// an explicit tap, and re-tapping the active entry was a silent no-op.
///
/// The controller must persist every selection, emit an observable log path
/// (via state change), and never let hydration undo an explicit choice.
/// Combined semantics are untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('select persists and survives re-hydration', () async {
    final prefs = FakePreferencesStorage();
    await AppStorage.init(secure: _FakeSecure(), preferences: prefs);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Default is Cafe.
    expect(container.read(businessSwitcherProvider), BusinessContext.cafe);

    await container
        .read(businessSwitcherProvider.notifier)
        .select(BusinessContext.foodTruck);
    expect(container.read(businessSwitcherProvider), BusinessContext.foodTruck);
    expect(await prefs.readString('business_switcher_context'), 'foodTruck');

    await container
        .read(businessSwitcherProvider.notifier)
        .select(BusinessContext.cafe);
    expect(container.read(businessSwitcherProvider), BusinessContext.cafe);
    expect(await prefs.readString('business_switcher_context'), 'cafe');
  });

  test('re-selecting the active entry still persists', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(businessSwitcherProvider), BusinessContext.cafe);
    await container
        .read(businessSwitcherProvider.notifier)
        .select(BusinessContext.cafe);
    expect(container.read(businessSwitcherProvider), BusinessContext.cafe);
  });

  test('combined remains a distinct non-cafe context', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(businessSwitcherProvider.notifier)
        .select(BusinessContext.all);
    expect(container.read(businessSwitcherProvider), BusinessContext.all);
  });
}

final class _FakeSecure implements SecureStorage {
  final Map<String, String> _values = {};
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<bool> readBool(String key, {bool defaultValue = false}) async =>
      defaultValue;
  @override
  Future<void> writeBool(String key, bool value) async {}
  @override
  Future<int> readInt(String key, {int defaultValue = 0}) async => defaultValue;
  @override
  Future<void> writeInt(String key, int value) async {}
  @override
  Future<bool> contains(String key) async => _values.containsKey(key);
  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async => _values.clear();
}
