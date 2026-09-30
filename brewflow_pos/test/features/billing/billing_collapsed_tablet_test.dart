import 'package:brewflow_pos/app/widgets/filter_chip.dart';
import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/tablet_nav_scope.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
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
import '../../helpers/test_providers.dart';
import '../../helpers/fake_inventory_repository.dart';

/// Collapsed-tablet Billing regression coverage for the navigation/Billing
/// responsive fix.
///
/// Root cause locked here: the app shell used to reserve a 64dp left gutter
/// for its floating navigation controls AND Billing reserved its 176dp
/// vertical category rail, stacking two left insets. Billing now reclaims the
/// shell gutter and owns its own header/filter clearance, with the rail
/// pinned to the navigation-side area. Rail pills scroll horizontally instead
/// of overflowing (filter_chip.dart itself is untouched).
FakeInventoryRepository _seedInventory() {
  final now = DateTime.now().toUtc();
  final inventory = FakeInventoryRepository();
  inventory.storedCategories.addAll([
    Category(
      id: 'c-beverages',
      name: 'Beverages',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
    Category(
      id: 'c-long',
      name: 'A Very Long Category Name That Would Overflow',
      isActive: true,
      createdAt: now,
      updatedAt: now,
    ),
  ]);
  inventory.storedProducts.add(
    Product(
      id: 'p-chai',
      categoryId: 'c-beverages',
      name: 'Masala Chai',
      sku: null,
      sellingPricePaise: 12000,
      costPricePaise: null,
      stockQuantity: 50,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      // The Cafe shop id FakeStaffRepository.ensureShop() hands out, so seeded
      // products survive the business scope filter.
      shopId: 'shop-1',
    ),
  );
  return inventory;
}

Future<void> _pumpPos(
  WidgetTester tester, {
  required Size size,
  bool? collapsed,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final inventory = _seedInventory();
  final body = const Scaffold(body: PosPage());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...businessScopeOverrides(),
        inventoryRepositoryProvider.overrideWithValue(inventory),
        billingRepositoryProvider.overrideWithValue(
          FakeBillingRepository(inventory),
        ),
        customersRepositoryProvider.overrideWithValue(
          FakeCustomersRepository(),
        ),
      ],
      child: MaterialApp(
        home: collapsed == null
            // Phone/desktop shells never insert the scope.
            ? body
            : TabletNavScope(collapsed: collapsed, child: body),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

EdgeInsets _headerClearance(WidgetTester tester) {
  final paddings = find.ancestor(
    of: find.byType(PageHeader),
    matching: find.byType(Padding),
  );
  expect(paddings, findsWidgets, reason: 'header sits inside padding');
  // Immediate parent is Billing's own collapsed-tablet clearance; the outer
  // screen padding sits further up the tree.
  return tester.widget<Padding>(paddings.first).padding as EdgeInsets;
}

void main() {
  testWidgets(
    'collapsed tablet Billing keeps rail pills and cart without overflow',
    (tester) async {
      await _pumpPos(tester, size: const Size(800, 1024), collapsed: true);
      expect(tester.takeException(), isNull);

      // Vertical rail (navigation-side area) with the default selection.
      final railPill = find.text('Frequently Sold');
      expect(railPill, findsOneWidget);
      expect(
        tester
            .widget<AppFilterChip>(
              find.ancestor(of: railPill, matching: find.byType(AppFilterChip)),
            )
            .selected,
        isTrue,
      );
      expect(find.text('All categories'), findsOneWidget);
      expect(find.text('Beverages'), findsOneWidget);
      expect(
        find.text('A Very Long Category Name That Would Overflow'),
        findsOneWidget,
      );

      // Cart stays pinned in view.
      expect(find.text('Complete Sale'), findsOneWidget);
      expect(find.text('Hold Bill'), findsOneWidget);

      // Rail sits left of the cart (navigation side, not overlapping).
      final pillLeft = tester.getRect(railPill).left;
      final cartLeft = tester
          .getRect(find.widgetWithText(FilledButton, 'Complete Sale'))
          .left;
      expect(pillLeft, lessThan(cartLeft));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'collapsed tablet Billing header owns clearance; open tablet does not',
    (tester) async {
      await _pumpPos(tester, size: const Size(800, 1024), collapsed: true);
      expect(_headerClearance(tester).left, AppSpacing.ultra);

      await _pumpPos(tester, size: const Size(800, 1024), collapsed: false);
      expect(_headerClearance(tester).left, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('phone Billing stays narrow with no rail clearance', (
    tester,
  ) async {
    await _pumpPos(tester, size: const Size(390, 844));
    expect(tester.takeException(), isNull);

    // Narrow phone flow (Products/Cart segments), unchanged.
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Cart'), findsOneWidget);
    expect(_headerClearance(tester).left, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Billing rail scrolls long labels without overflow', (
    tester,
  ) async {
    await _pumpPos(tester, size: const Size(1280, 800));
    expect(tester.takeException(), isNull);
    expect(find.text('Frequently Sold'), findsOneWidget);
    expect(
      find.text('A Very Long Category Name That Would Overflow'),
      findsOneWidget,
    );
    expect(find.text('Complete Sale'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
