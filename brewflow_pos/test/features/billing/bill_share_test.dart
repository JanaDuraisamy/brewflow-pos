import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';

/// Captures shared content instead of opening the platform share sheet.
final class FakeShareService implements ShareService {
  final List<({String subject, String text})> calls = [];
  Object? error;

  @override
  Future<void> shareText({
    required String subject,
    required String text,
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    calls.add((subject: subject, text: text));
  }
}

void main() {
  testWidgets(
    'receipt dialog Share Bill hands the document to the share service',
    (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final inventory = FakeInventoryRepository()
        ..storedProducts.add(
          Product(
            id: 'p1',
            categoryId: 'c1',
            name: 'Filter Coffee',
            sku: 'FC-01',
            sellingPricePaise: 12000,
            costPricePaise: null,
            stockQuantity: 5,
            isActive: true,
            createdAt: DateTime.now().toUtc(),
            updatedAt: DateTime.now().toUtc(),
          ),
        );
      final billing = FakeBillingRepository(inventory);
      final share = FakeShareService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            inventoryRepositoryProvider.overrideWithValue(inventory),
            billingRepositoryProvider.overrideWithValue(billing),
            customersRepositoryProvider.overrideWithValue(
              FakeCustomersRepository(),
            ),
            shareServiceProvider.overrideWithValue(share),
          ],
          child: const MaterialApp(home: Scaffold(body: PosPage())),
        ),
      );
      await tester.pumpAndSettle();

      // Complete a sale.
      await tester.tap(
        find.descendant(
          of: find.ancestor(
            of: find.text('Filter Coffee'),
            matching: find.byType(Card),
          ),
          matching: find.widgetWithText(FilledButton, 'Add'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('UPI'));
      await tester.tap(find.text('UPI'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Complete Sale'),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
      await tester.pumpAndSettle();

      expect(find.text('Sale Complete'), findsOneWidget);
      expect(share.calls, isEmpty);

      await tester.ensureVisible(find.text('Share Bill'));
      await tester.tap(find.text('Share Bill'));
      await tester.pumpAndSettle();

      expect(share.calls.length, 1);
      expect(share.calls.single.subject, 'Receipt BF-000001');
      expect(share.calls.single.text, contains('BrewFlow POS'));
      expect(share.calls.single.text, contains('Filter Coffee'));
      expect(share.calls.single.text, contains('Total: ₹120.00 (Paid)'));

      // Sharing must not close the receipt nor create another sale.
      expect(find.text('Sale Complete'), findsOneWidget);
      expect(billing.storedSales.length, 1);
    },
  );

  testWidgets('a share failure surfaces a safe message and keeps the sale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final inventory = FakeInventoryRepository()
      ..storedProducts.add(
        Product(
          id: 'p1',
          categoryId: 'c1',
          name: 'Filter Coffee',
          sku: null,
          sellingPricePaise: 12000,
          costPricePaise: null,
          stockQuantity: 5,
          isActive: true,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    final billing = FakeBillingRepository(inventory);
    final share = FakeShareService()..error = StateError('no share targets');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryRepositoryProvider.overrideWithValue(inventory),
          billingRepositoryProvider.overrideWithValue(billing),
          customersRepositoryProvider.overrideWithValue(
            FakeCustomersRepository(),
          ),
          shareServiceProvider.overrideWithValue(share),
        ],
        child: const MaterialApp(home: Scaffold(body: PosPage())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.ancestor(
          of: find.text('Filter Coffee'),
          matching: find.byType(Card),
        ),
        matching: find.widgetWithText(FilledButton, 'Add'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Cash'));
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Complete Sale'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Share Bill'));
    await tester.tap(find.text('Share Bill'));
    await tester.pumpAndSettle();

    expect(find.text('Could not open sharing.'), findsOneWidget);
    expect(
      billing.storedSales.length,
      1,
      reason: 'share failure never affects the sale',
    );
  });
}
