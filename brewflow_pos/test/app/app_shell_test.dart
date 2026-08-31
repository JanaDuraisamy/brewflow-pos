import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/shells/splash_shell.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_billing_repository.dart';
import '../helpers/fake_customer_ledger_repository.dart';
import '../helpers/fake_inventory_repository.dart';
import '../helpers/fake_orders_repository.dart';

Widget _app() => ProviderScope(
  overrides: [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    inventoryRepositoryProvider.overrideWithValue(FakeInventoryRepository()),
    billingRepositoryProvider.overrideWithValue(
      FakeBillingRepository(FakeInventoryRepository()),
    ),
    ordersRepositoryProvider.overrideWithValue(FakeOrdersRepository()),
    customerLedgerRepositoryProvider.overrideWithValue(
      FakeCustomerLedgerRepository(),
    ),
  ],
  child: const BrewFlowApp(),
);

GoRouter _routerFor(WidgetTester tester) {
  final context = tester.element(find.byType(SplashShell).first);
  return ProviderScope.containerOf(context).read(appRouterProvider);
}

void main() {
  testWidgets('app starts on the splash shell with BrewFlow branding', (
    tester,
  ) async {
    await tester.pumpWidget(_app());

    expect(find.byType(SplashShell), findsOneWidget);
    expect(find.text('BrewFlow'), findsOneWidget);
    expect(find.text('Point of Sale'), findsOneWidget);
  });

  testWidgets('navigates from splash to auth and dashboard shells', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    final router = _routerFor(tester);

    router.go(AppRoutes.auth);
    await tester.pumpAndSettle();
    expect(find.byType(AuthShell), findsOneWidget);
    expect(find.byType(SplashShell), findsNothing);

    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
    expect(find.byType(AuthShell), findsNothing);
  });

  testWidgets('named route navigation works (goNamed)', (tester) async {
    await tester.pumpWidget(_app());
    final router = _routerFor(tester);

    router.goNamed('dashboard');
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);
    expect(find.byType(DashboardPage), findsOneWidget);
  });

  testWidgets('redirect extension point guards routes without rewrites', (
    tester,
  ) async {
    final router = buildAppRouter(
      redirect: (context, state) {
        if (state.matchedLocation == AppRoutes.dashboard) {
          return AppRoutes.auth;
        }
        return null;
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SplashShell), findsOneWidget);

    router.go(AppRoutes.dashboard);
    await tester.pumpAndSettle();
    expect(find.byType(AuthShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
