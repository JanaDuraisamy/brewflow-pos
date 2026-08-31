import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/shells/app_shell.dart';
import 'package:brewflow_pos/app/shells/splash_shell.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_shell.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
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

void main() {
  Widget app(FakeAuthRepository fake) => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fake),
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

  GoRouter routerOf(WidgetTester tester) {
    final element = tester.element(find.byType(Scaffold).first);
    return ProviderScope.containerOf(element).read(appRouterProvider);
  }

  testWidgets('splash stays visible while auth is initializing', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));

    expect(find.byType(SplashShell), findsOneWidget);
    expect(find.byType(AuthShell), findsNothing);
    expect(find.byType(AppShell), findsNothing);
  });

  testWidgets(
    'unauthenticated users are sent to /auth and /dashboard is protected',
    (tester) async {
      final fake = FakeAuthRepository();
      await tester.pumpWidget(app(fake));

      fake.emit(null);
      await tester.pumpAndSettle();

      expect(find.byType(AuthShell), findsOneWidget);
      expect(find.byType(SplashShell), findsNothing);

      final router = routerOf(tester);
      router.go(AppRoutes.dashboard);
      await tester.pumpAndSettle();

      expect(find.byType(AuthShell), findsOneWidget);
      expect(find.byType(AppShell), findsNothing);
    },
  );

  testWidgets(
    'authenticated users land on /dashboard and /auth redirects back',
    (tester) async {
      final fake = FakeAuthRepository();
      await tester.pumpWidget(app(fake));

      fake.emit(const AuthUser(id: 'u1', email: 'owner@brewflow.example'));
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);

      final router = routerOf(tester);
      router.go(AppRoutes.auth);
      await tester.pumpAndSettle();

      expect(find.byType(AppShell), findsOneWidget);
      expect(find.byType(AuthShell), findsNothing);
    },
  );

  testWidgets('no redirect loop: unauthenticated users settle on /auth', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(null);
    await tester.pumpAndSettle();

    expect(find.byType(AuthShell), findsOneWidget);
    final router = routerOf(tester);

    for (var attempt = 0; attempt < 3; attempt++) {
      router.go(AppRoutes.auth);
      router.go(AppRoutes.splash);
      await tester.pumpAndSettle();
      expect(
        find.byType(AuthShell),
        findsOneWidget,
        reason: 'stays on /auth, never bounces',
      );
    }
  });

  testWidgets('no redirect loop: authenticated users settle on /dashboard', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(const AuthUser(id: 'u1', email: 'owner@brewflow.example'));
    await tester.pumpAndSettle();

    expect(find.byType(AppShell), findsOneWidget);
    final router = routerOf(tester);

    for (var attempt = 0; attempt < 3; attempt++) {
      router.go(AppRoutes.splash);
      await tester.pumpAndSettle();
      expect(
        find.byType(AppShell),
        findsOneWidget,
        reason: 'stays on /dashboard, never bounces',
      );
    }
  });

  testWidgets('signing out from the dashboard returns to /auth', (
    tester,
  ) async {
    final fake = FakeAuthRepository();
    await tester.pumpWidget(app(fake));
    fake.emit(const AuthUser(id: 'u1', email: 'owner@brewflow.example'));
    await tester.pumpAndSettle();
    expect(find.byType(AppShell), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthShell), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
    expect(fake.signOutCalls, 1);
  });

  testWidgets('error-state users stay on /auth and can retry', (tester) async {
    final fake = FakeAuthRepository()..signInError = const NetworkFailure();
    await tester.pumpWidget(app(fake));
    fake.emit(null);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'a@b.com');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.byType(AuthShell), findsOneWidget);
    expect(
      find.text(
        'Cannot reach the server. Check your connection and try again.',
      ),
      findsOneWidget,
    );
  });
}
