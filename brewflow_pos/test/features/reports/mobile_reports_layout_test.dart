import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/orders/domain/orders_models.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/reports/presentation/reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_orders_repository.dart';

/// One sale line bounded by the repository's snapshot semantics.
OrderItem _item(
  String name, {
  int price = 1500,
  int quantity = 1,
  String? productId,
}) => OrderItem(
  productName: name,
  unitPricePaise: price,
  quantity: quantity,
  lineTotalPaise: price * quantity,
  productId: productId,
);

/// Pumps the Reports page at [width] on the phone-only layout with a seeded
/// world (sales + expenses + cost resolution) and fails if any exception
/// escapes layout or a deep scroll.
Future<void> _pumpPhone(WidgetTester tester, double width) async {
  final inventory = FakeInventoryRepository();
  final category = await inventory.createCategory('Beverages');
  await inventory.createProduct(
    categoryId: category.id,
    name: 'Chai',
    sellingPricePaise: 1500,
    costPricePaise: 1000,
    stockQuantity: 10,
    isActive: true,
  );

  final now = DateTime.now();
  final orders = FakeOrdersRepository();
  orders.add(
    receiptNumber: 'R-001',
    createdAt: now.toUtc(),
    paymentMethod: PaymentMethod.cash,
    totalPaise: 3000,
    items: [_item('Chai', price: 3000, quantity: 2, productId: 'product-1')],
  );
  orders.add(
    receiptNumber: 'R-002',
    createdAt: now.subtract(const Duration(days: 1)).toUtc(),
    paymentMethod: PaymentMethod.upi,
    totalPaise: 10000,
    items: [_item('Cookie', price: 2000, quantity: 5, productId: 'product-1')],
  );

  final expenses = FakeExpensesRepository();
  expenses.seed(
    name: 'Shop Rent',
    amountPaise: 5000,
    category: ExpenseCategory.rent,
    paymentMethod: PaymentMethod.bank,
    expenseDate: now.toUtc(),
  );

  final container = ProviderContainer(
    // Riverpod retries failing builds by default; tests want deterministic
    // error surfacing without background backoff timers.
    retry: (count, error) => null,
    overrides: [
      ordersRepositoryProvider.overrideWithValue(orders),
      inventoryRepositoryProvider.overrideWithValue(inventory),
      expensesRepositoryProvider.overrideWithValue(expenses),
    ],
  );
  addTearDown(container.dispose);

  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 850);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: ReportsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const phoneWidths = [360.0, 375.0, 390.0, 411.0, 430.0, 480.0];

  for (final width in phoneWidths) {
    testWidgets('lays out without overflow at ${width.round()}dp', (
      tester,
    ) async {
      await _pumpPhone(tester, width);
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
