import 'package:brewflow_pos/app/app.dart';
import 'package:brewflow_pos/app/providers.dart';
import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_page.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_connectivity_service.dart';
import '../../helpers/fake_customer_ledger_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_settings_repository.dart';

const _owner = AuthUser(id: 'u1', email: 'owner@brewflow.example');

void main() {
  late FakeAuthRepository fakeAuth;
  late FakeInventoryRepository fakeInventory;
  late FakeOrdersRepository fakeOrders;

  setUp(() {
    fakeAuth = FakeAuthRepository();
    fakeInventory = FakeInventoryRepository();
    fakeOrders = FakeOrdersRepository();
  });

  Widget app() => ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(fakeAuth),
      inventoryRepositoryProvider.overrideWithValue(fakeInventory),
      ordersRepositoryProvider.overrideWithValue(fakeOrders),
      customerLedgerRepositoryProvider.overrideWithValue(
        FakeCustomerLedgerRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      connectivityServiceProvider.overrideWithValue(fakeConnectivityService()),
    ],
    child: const BrewFlowApp(),
  );

  Future<void> pumpAuthenticated(WidgetTester tester) async {
    await tester.pumpWidget(app());
    fakeAuth.emit(_owner);
    await tester.pumpAndSettle();
  }

  Future<void> pumpAsync(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  Future<void> openDashboard(WidgetTester tester) async {
    final element = tester.element(find.byType(Scaffold).first);
    final router = ProviderScope.containerOf(element).read(appRouterProvider);
    router.go(AppRoutes.dashboard);
    await pumpAsync(tester);
  }

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    await pumpAuthenticated(tester);
    await openDashboard(tester);
  }

  const widths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

  for (final width in widths) {
    testWidgets(
      'dashboard renders phone layout without overflow at ${width.toInt()}dp',
      (tester) async {
        await pumpAt(tester, width);

        expect(tester.takeException(), isNull);
        expect(find.byType(DashboardPage), findsOneWidget);
        expect(find.text('Dashboard'), findsWidgets);
        expect(find.text('Sales Overview'), findsOneWidget);
      },
    );
  }
}
