import 'dart:convert';

import 'package:brewflow_pos/features/offers/domain/offers_models.dart';
import 'package:flutter_test/flutter_test.dart';

Offer _offer({
  required String id,
  required String name,
  required OfferType type,
  required Map<String, dynamic> config,
  bool isActive = true,
  DateTime? startAt,
  DateTime? endAt,
}) => Offer(
  id: id,
  shopId: 'shop-1',
  name: name,
  type: type,
  configJson: jsonEncode(config),
  isActive: isActive,
  startAt: startAt,
  endAt: endAt,
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

CartLineContext _line({
  required String productId,
  String? variantId,
  required int quantity,
  required int unitPricePaise,
}) => CartLineContext(
  productId: productId,
  variantId: variantId,
  quantity: quantity,
  unitPricePaise: unitPricePaise,
  memberPricePaise: null,
  memberPricing: false,
);

void main() {
  group('calculateLineOffers offer identity', () {
    test('percentage stamps the real offer id and name', () {
      final offer = _offer(
        id: 'off-pct-1',
        name: 'Monsoon 10%',
        type: OfferType.percentage,
        config: const PercentageOfferConfig(
          percent: 10,
          productIds: ['p1'],
        ).toJson(),
      );

      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 2, unitPricePaise: 10000),
        activeOffers: [offer],
      );

      expect(results, hasLength(1));
      expect(results.single.offerId, 'off-pct-1');
      expect(results.single.offerName, 'Monsoon 10%');
      expect(results.single.offerType, OfferType.percentage);
      expect(results.single.discountPaise, 2000);
    });

    test('buyXGetY stamps the real offer id and name', () {
      final offer = _offer(
        id: 'off-b2g1',
        name: 'Buy 2 Get 1',
        type: OfferType.buyXGetY,
        config: const BuyXGetYOfferConfig(
          productId: 'p1',
          buyQty: 2,
          getQty: 1,
        ).toJson(),
      );

      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 3, unitPricePaise: 5000),
        activeOffers: [offer],
      );

      expect(results, hasLength(1));
      expect(results.single.offerId, 'off-b2g1');
      expect(results.single.offerName, 'Buy 2 Get 1');
      expect(results.single.discountPaise, 5000);
    });

    test('combo is skipped by line-level calculation', () {
      final offer = _offer(
        id: 'off-combo-1',
        name: 'Lunch Combo',
        type: OfferType.combo,
        config: const ComboOfferConfig(
          productIds: ['p1', 'p2'],
          comboPricePaise: 25000,
        ).toJson(),
      );

      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 1, unitPricePaise: 12000),
        activeOffers: [offer],
      );

      expect(results, isEmpty);
    });

    test('inactive and expired offers never calculate', () {
      final config = const PercentageOfferConfig(percent: 10).toJson();
      final inactive = _offer(
        id: 'off-off',
        name: 'Off',
        type: OfferType.percentage,
        config: config,
        isActive: false,
      );
      final expired = _offer(
        id: 'off-exp',
        name: 'Expired',
        type: OfferType.percentage,
        config: config,
        endAt: DateTime.utc(2020, 1, 1),
      );

      for (final offer in [inactive, expired]) {
        expect(
          calculateLineOffers(
            line: _line(productId: 'p1', quantity: 1, unitPricePaise: 10000),
            activeOffers: [offer],
          ),
          isEmpty,
        );
      }
    });
  });

  group('calculateComboLineOffers', () {
    Offer combo({
      String id = 'off-combo-1',
      String name = 'Lunch Combo',
      List<String> productIds = const ['p1', 'p2'],
      int price = 25000,
    }) => _offer(
      id: id,
      name: name,
      type: OfferType.combo,
      config: ComboOfferConfig(
        productIds: productIds,
        comboPricePaise: price,
      ).toJson(),
    );

    test('applies real identity and splits discount across combo lines', () {
      final lines = [
        _line(productId: 'p1', quantity: 1, unitPricePaise: 12000),
        _line(productId: 'p2', quantity: 1, unitPricePaise: 18000),
      ];

      final byLine = calculateComboLineOffers(
        lines: lines,
        comboOffers: [combo()],
      );

      expect(byLine.keys, unorderedEquals([0, 1]));
      final total = byLine.values
          .expand((calcs) => calcs)
          .fold(0, (sum, c) => sum + c.discountPaise);
      // Combo total 30000 - price 25000 = 5000, split exactly.
      expect(total, 5000);
      for (final calcs in byLine.values) {
        expect(calcs.single.offerId, 'off-combo-1');
        expect(calcs.single.offerName, 'Lunch Combo');
        expect(calcs.single.offerType, OfferType.combo);
      }
    });

    test('missing combo product yields no discount', () {
      final lines = [
        _line(productId: 'p1', quantity: 1, unitPricePaise: 12000),
      ];

      expect(
        calculateComboLineOffers(lines: lines, comboOffers: [combo()]),
        isEmpty,
      );
    });

    test('combo priced above the shelf total yields no discount', () {
      final lines = [
        _line(productId: 'p1', quantity: 1, unitPricePaise: 12000),
        _line(productId: 'p2', quantity: 1, unitPricePaise: 18000),
      ];

      expect(
        calculateComboLineOffers(
          lines: lines,
          comboOffers: [combo(price: 99999)],
        ),
        isEmpty,
      );
    });

    test('duplicate product ids require matching quantities', () {
      final one = [_line(productId: 'p1', quantity: 1, unitPricePaise: 10000)];
      final two = [_line(productId: 'p1', quantity: 2, unitPricePaise: 10000)];
      final offer = combo(productIds: const ['p1', 'p1'], price: 15000);

      expect(
        calculateComboLineOffers(lines: one, comboOffers: [offer]),
        isEmpty,
      );

      final met = calculateComboLineOffers(lines: two, comboOffers: [offer]);
      final total = met.values
          .expand((calcs) => calcs)
          .fold(0, (sum, c) => sum + c.discountPaise);
      expect(total, 5000);
    });

    test('matches by variant id', () {
      final lines = [
        _line(
          productId: 'p1',
          variantId: 'v-large',
          quantity: 1,
          unitPricePaise: 15000,
        ),
        _line(productId: 'p2', quantity: 1, unitPricePaise: 15000),
      ];

      final byLine = calculateComboLineOffers(
        lines: lines,
        comboOffers: [
          combo(productIds: const ['v-large', 'p2']),
        ],
      );

      expect(byLine.keys, unorderedEquals([0, 1]));
    });

    test('invalid configs are ignored', () {
      final lines = [
        _line(productId: 'p1', quantity: 1, unitPricePaise: 12000),
      ];
      final emptyIds = combo(productIds: const []);
      final negativePrice = combo(price: -5);

      expect(
        calculateComboLineOffers(
          lines: lines,
          comboOffers: [emptyIds, negativePrice],
        ),
        isEmpty,
      );
    });
  });

  group('selectBestOffer', () {
    test('selects an offer when one exists', () {
      const pct = OfferCalculation(
        offerId: 'pct',
        offerName: 'Pct',
        offerType: OfferType.percentage,
        discountPaise: 100,
        appliedQuantity: 1,
      );
      const comboCalc = OfferCalculation(
        offerId: 'combo',
        offerName: 'Combo',
        offerType: OfferType.combo,
        discountPaise: 9000,
        appliedQuantity: 1,
      );
      const bogo = OfferCalculation(
        offerId: 'bogo',
        offerName: 'Bogo',
        offerType: OfferType.buyXGetY,
        discountPaise: 5000,
        appliedQuantity: 1,
      );

      expect(selectBestOffer([comboCalc, bogo]), isNotNull);
      expect(selectBestOffer([bogo, comboCalc, pct]), isNotNull);
      expect(selectBestOffer([]), isNull);
    });
  });
}
