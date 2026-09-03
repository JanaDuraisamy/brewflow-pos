import 'dart:convert';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:brewflow_pos/features/offers/presentation/offers_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_inventory_repository.dart';
import '../../helpers/fake_offers_repository.dart';
import '../../helpers/fake_settings_repository.dart';
import '../../helpers/fake_staff_repository.dart';

void main() {
  late FakeInventoryRepository inventory;
  late FakeOffersRepository offers;
  late ProviderContainer container;

  Product product({
    required String id,
    required String name,
    required int pricePaise,
    int stock = 5,
  }) {
    final created = Product(
      id: id,
      categoryId: 'c1',
      name: name,
      sku: null,
      sellingPricePaise: pricePaise,
      costPricePaise: null,
      stockQuantity: stock,
      isActive: true,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );
    inventory.storedProducts.add(created);
    return created;
  }

  setUp(() {
    inventory = FakeInventoryRepository();
    offers = FakeOffersRepository();
    container = ProviderContainer(
      overrides: [
        inventoryRepositoryProvider.overrideWithValue(inventory),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
        offersRepositoryProvider.overrideWithValue(offers),
      ],
    );
    addTearDown(container.dispose);
  });

  Cart cart() => container.read(cartProvider);
  CartController controller() => container.read(cartProvider.notifier);

  group('cart offer application', () {
    test(
      'combo applies with real offer identity and post-offer total',
      () async {
        final combo = await offers.createOffer(
          shopId: 'shop-1',
          name: 'Lunch Combo',
          type: OfferType.combo,
          configJson: jsonEncode(
            const ComboOfferConfig(
              productIds: ['p1', 'p2'],
              comboPricePaise: 25000,
            ).toJson(),
          ),
        );
        await container.read(posOffersProvider.future);

        controller().add(product(id: 'p1', name: 'Coffee', pricePaise: 12000));
        controller().add(
          product(id: 'p2', name: 'Sandwich', pricePaise: 18000),
        );

        final lines = cart().lines;
        expect(lines, hasLength(2));
        for (final line in lines) {
          expect(line.appliedOffer, isNotNull);
          expect(line.appliedOffer!.offerId, combo.id);
          expect(line.appliedOffer!.offerName, 'Lunch Combo');
          expect(line.appliedOffer!.offerType, OfferType.combo);
        }
        // Combo total 30000 - price 25000 = 5000 across both lines.
        expect(cart().totalOfferDiscountPaise, 5000);
        expect(cart().chargedTotalAfterOffersPaise, 25000);
        expect(cart().totalPaise, 25000);
      },
    );

    test(
      'percentage stamps real identity and lowers the charged total',
      () async {
        final pct = await offers.createOffer(
          shopId: 'shop-1',
          name: 'Monsoon 10%',
          type: OfferType.percentage,
          configJson: jsonEncode(
            const PercentageOfferConfig(percent: 10).toJson(),
          ),
        );
        await container.read(posOffersProvider.future);

        controller().add(product(id: 'p1', name: 'Coffee', pricePaise: 10000));

        final line = cart().lines.single;
        expect(line.appliedOffer!.offerId, pct.id);
        expect(line.appliedOffer!.offerName, 'Monsoon 10%');
        expect(line.appliedOffer!.discountPaise, 1000);
        expect(cart().chargedTotalAfterOffersPaise, 9000);
      },
    );

    test('unmet combo leaves the cart undiscounted', () async {
      await offers.createOffer(
        shopId: 'shop-1',
        name: 'Lunch Combo',
        type: OfferType.combo,
        configJson: jsonEncode(
          const ComboOfferConfig(
            productIds: ['p1', 'p2'],
            comboPricePaise: 25000,
          ).toJson(),
        ),
      );
      await container.read(posOffersProvider.future);

      controller().add(product(id: 'p1', name: 'Coffee', pricePaise: 12000));

      expect(cart().lines.single.appliedOffer, isNull);
      expect(cart().totalOfferDiscountPaise, 0);
      expect(cart().chargedTotalAfterOffersPaise, 12000);
    });
  });
}
