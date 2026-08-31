import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';

void main() {
  test('appRouterProvider creates one stable router starting at /splash', () {
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
      ],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    expect(container.read(appRouterProvider), same(router));
    expect(router.routeInformationProvider.value.uri.path, AppRoutes.splash);
  });

  test('buildAppRouter resolves all three shell routes', () async {
    final router = buildAppRouter();

    for (final path in [
      AppRoutes.splash,
      AppRoutes.auth,
      AppRoutes.dashboard,
    ]) {
      router.go(path);
      await Future<void>.delayed(Duration.zero);
      expect(router.routeInformationProvider.value.uri.path, path);
    }
  });
}
