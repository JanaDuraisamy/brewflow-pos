import 'dart:async';

import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/domain/settings_repository.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_shop_name_repository.dart';

void main() {
  late FakeSettingsRepository repository;
  late FakeShopNameRepository shopNameRepository;

  setUp(() {
    repository = FakeSettingsRepository();
    shopNameRepository = FakeShopNameRepository();
  });

  ProviderContainer buildContainer() => ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(repository),
      shopNameRepositoryProvider.overrideWithValue(shopNameRepository),
    ],
  );

  test('loads the persisted settings', () async {
    repository.stored = const ShopSettings(
      shopName: 'Cafe Marina',
      ownerName: 'Jana',
      lowStockThreshold: 3,
      theme: ThemePreference.dark,
    );

    final container = buildContainer();
    addTearDown(container.dispose);
    final state = await container.read(shopSettingsProvider.future);

    expect(state.shopName, 'Cafe Marina');
    expect(state.ownerName, 'Jana');
    expect(state.lowStockThreshold, 3);
    expect(state.theme, ThemePreference.dark);
  });

  test('uses defaults when nothing is saved', () async {
    final container = buildContainer();
    addTearDown(container.dispose);
    final state = await container.read(shopSettingsProvider.future);

    expect(state, ShopSettings.defaults());
  });

  test('surfaces a user-safe error when loading fails', () async {
    repository.loadError = const UnexpectedSettingsFailure();

    final container = buildContainer();
    addTearDown(container.dispose);

    container.read(shopSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shopSettingsProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<UnexpectedSettingsFailure>());
  });

  test('translates unexpected load errors into a safe failure', () async {
    repository.loadError = StateError('storage exploded');

    final container = buildContainer();
    addTearDown(container.dispose);

    container.read(shopSettingsProvider);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(shopSettingsProvider);
    expect(state.hasError, isTrue);
    expect(state.error, isA<UnexpectedSettingsFailure>());
  });

  test('save persists and exposes the new settings', () async {
    const next = ShopSettings(
      shopName: 'Cafe Marina',
      lowStockThreshold: 2,
      theme: ThemePreference.light,
    );

    final container = buildContainer();
    addTearDown(container.dispose);
    await container.read(shopSettingsProvider.future);
    await container.read(shopSettingsProvider.notifier).save(next);

    expect(container.read(shopSettingsProvider).value, next);
    expect(repository.stored, next);
    expect(repository.saved, [next]);
  });

  test('save keeps the previous state while saving', () async {
    repository.saveGate = Completer<void>();

    final container = buildContainer();
    addTearDown(container.dispose);
    final initial = await container.read(shopSettingsProvider.future);

    final saving = container
        .read(shopSettingsProvider.notifier)
        .save(const ShopSettings(shopName: 'Cafe Marina'));

    expect(
      container.read(shopSettingsProvider).value,
      initial,
      reason: 'The previous value must stay visible while saving.',
    );

    repository.saveGate!.complete();
    await saving;

    expect(container.read(shopSettingsProvider).value!.shopName, 'Cafe Marina');
  });

  test(
    'failed save keeps the previous state and surfaces the failure',
    () async {
      const previous = ShopSettings(shopName: 'Before');
      repository.stored = previous;
      repository.saveError = const UnexpectedSettingsFailure();

      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(shopSettingsProvider.future);

      await expectLater(
        container
            .read(shopSettingsProvider.notifier)
            .save(const ShopSettings(shopName: 'After')),
        throwsA(isA<UnexpectedSettingsFailure>()),
      );
      expect(container.read(shopSettingsProvider).value, previous);
    },
  );

  group('appThemeModeProvider', () {
    test('follows the stored theme preference', () async {
      repository.stored = const ShopSettings(
        shopName: 'Cafe Marina',
        theme: ThemePreference.dark,
      );

      final container = buildContainer();
      addTearDown(container.dispose);
      await container.read(shopSettingsProvider.future);

      expect(container.read(appThemeModeProvider), ThemeMode.dark);
    });

    test('falls back to the system theme when settings are unavailable', () {
      repository.loadError = const UnexpectedSettingsFailure();

      final container = buildContainer();
      addTearDown(container.dispose);

      expect(container.read(appThemeModeProvider), ThemeMode.system);
    });
  });
}
