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

  group('quantity tier offers (buy X for Rs.Y)', () {
    // The Kulfi ladder from the business example: 1 = 45, 2 = 85, 3 = 120.
    final kulfi = _offer(
      id: 'off-tier-1',
      name: 'Kulfi Tiers',
      type: OfferType.quantityTier,
      config: const QuantityTierOfferConfig(
        productIds: ['kulfi'],
        tiers: [
          QuantityTier(quantity: 1, pricePaise: 4500),
          QuantityTier(quantity: 2, pricePaise: 8500),
          QuantityTier(quantity: 3, pricePaise: 12000),
        ],
      ).toJson(),
    );

    OfferCalculation? bestFor(int quantity, {int unitPricePaise = 4500}) {
      final results = calculateLineOffers(
        line: _line(
          productId: 'kulfi',
          quantity: quantity,
          unitPricePaise: unitPricePaise,
        ),
        activeOffers: [kulfi],
      );
      return selectBestOffer(results);
    }

    test('one unit at the single-unit tier gives no discount', () {
      expect(bestFor(1), isNull);
    });

    test('two units use the 2-unit tier: 2x4500 shelf, 8500 tier', () {
      final best = bestFor(2);
      expect(best, isNotNull);
      expect(best!.offerType, OfferType.quantityTier);
      expect(best.discountPaise, 9000 - 8500);
      expect(best.appliedQuantity, 2);
    });

    test('three units use the 3-unit tier: 3x4500 shelf, 12000 tier', () {
      final best = bestFor(3);
      expect(best, isNotNull);
      expect(best!.discountPaise, 13500 - 12000);
      expect(best.appliedQuantity, 3);
    });

    test('five units decompose into the 3-unit then 2-unit tier', () {
      // 3 -> 12000 plus 2 -> 8500 = 20500 against a 22500 shelf.
      final best = bestFor(5);
      expect(best, isNotNull);
      expect(best!.discountPaise, 22500 - 20500);
      expect(best.appliedQuantity, 5);
    });

    test('four units decompose into the 3-unit then 1-unit tier', () {
      // 3 -> 12000 plus 1 -> 4500 = 16500 against a 18000 shelf.
      final best = bestFor(4);
      expect(best, isNotNull);
      expect(best!.discountPaise, 18000 - 16500);
      expect(best.appliedQuantity, 4);
    });

    test('stamps the real offer id and name', () {
      final best = bestFor(2);
      expect(best!.offerId, 'off-tier-1');
      expect(best.offerName, 'Kulfi Tiers');
    });

    test('does not apply to another product', () {
      final results = calculateLineOffers(
        line: _line(productId: 'other', quantity: 3, unitPricePaise: 4500),
        activeOffers: [kulfi],
      );
      expect(results, isEmpty);
    });

    test('empty productIds applies to every product', () {
      final anyProduct = _offer(
        id: 'off-tier-any',
        name: 'Any Product Tiers',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: [],
          tiers: [QuantityTier(quantity: 2, pricePaise: 8500)],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'whatever', quantity: 2, unitPricePaise: 4500),
        activeOffers: [anyProduct],
      );
      expect(selectBestOffer(results)!.discountPaise, 9000 - 8500);
    });

    test('a tier that is not cheaper than the shelf price is not applied', () {
      final badTier = _offer(
        id: 'off-tier-bad',
        name: 'Not A Discount',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['kulfi'],
          tiers: [QuantityTier(quantity: 2, pricePaise: 9500)],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'kulfi', quantity: 2, unitPricePaise: 4500),
        activeOffers: [badTier],
      );
      expect(results, isEmpty);
    });

    test(
      'tiers are honoured in ascending order regardless of config order',
      () {
        final unsorted = _offer(
          id: 'off-tier-unsorted',
          name: 'Unsorted Tiers',
          type: OfferType.quantityTier,
          config: const QuantityTierOfferConfig(
            productIds: ['kulfi'],
            tiers: [
              QuantityTier(quantity: 3, pricePaise: 12000),
              QuantityTier(quantity: 1, pricePaise: 4500),
              QuantityTier(quantity: 2, pricePaise: 8500),
            ],
          ).toJson(),
        );
        final results = calculateLineOffers(
          line: _line(productId: 'kulfi', quantity: 3, unitPricePaise: 4500),
          activeOffers: [unsorted],
        );
        expect(selectBestOffer(results)!.discountPaise, 13500 - 12000);
      },
    );

    test('malformed tiers are ignored instead of throwing', () {
      final broken = _offer(
        id: 'off-tier-broken',
        name: 'Broken Tiers',
        type: OfferType.quantityTier,
        config: const {
          'productIds': ['kulfi'],
          'tiers': [
            {'quantity': 0, 'pricePaise': 100},
            {'quantity': 2},
            'not-a-map',
            {'quantity': 2, 'pricePaise': 8500},
          ],
        },
      );
      final results = calculateLineOffers(
        line: _line(productId: 'kulfi', quantity: 2, unitPricePaise: 4500),
        activeOffers: [broken],
      );
      expect(selectBestOffer(results)!.discountPaise, 500);
    });

    test('an empty tier list applies nothing', () {
      final empty = _offer(
        id: 'off-tier-empty',
        name: 'Empty Tiers',
        type: OfferType.quantityTier,
        config: const {
          'productIds': ['kulfi'],
          'tiers': <dynamic>[],
        },
      );
      final results = calculateLineOffers(
        line: _line(productId: 'kulfi', quantity: 3, unitPricePaise: 4500),
        activeOffers: [empty],
      );
      expect(results, isEmpty);
    });

    test('member pricing is the shelf the tier is measured against', () {
      // 2 units at the member price 4000 = 8000 shelf; the 8500 tier is then
      // not a discount, so no offer applies.
      final results = calculateLineOffers(
        line: CartLineContext(
          productId: 'kulfi',
          variantId: null,
          quantity: 2,
          unitPricePaise: 4500,
          memberPricePaise: 4000,
          memberPricing: true,
        ),
        activeOffers: [kulfi],
      );
      expect(results, isEmpty);
    });

    test('variant id matches the configured product', () {
      final results = calculateLineOffers(
        line: CartLineContext(
          productId: 'kulfi-parent',
          variantId: 'kulfi',
          quantity: 3,
          unitPricePaise: 4500,
          memberPricePaise: null,
          memberPricing: false,
        ),
        activeOffers: [kulfi],
      );
      expect(selectBestOffer(results)!.discountPaise, 1500);
    });
  });

  group('offer priority with quantity tiers', () {
    test('percentage still outranks a quantity tier', () {
      final pct = _offer(
        id: 'pct',
        name: 'Pct',
        type: OfferType.percentage,
        config: const PercentageOfferConfig(
          percent: 50,
          productIds: ['p1'],
        ).toJson(),
      );
      final tier = _offer(
        id: 'tier',
        name: 'Tier',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['p1'],
          tiers: [QuantityTier(quantity: 1, pricePaise: 1000)],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 1, unitPricePaise: 10000),
        activeOffers: [tier, pct],
      );
      expect(results.first.offerType, OfferType.percentage);
    });

    test('a quantity tier outranks combo and buy X get Y', () {
      final tier = _offer(
        id: 'tier',
        name: 'Tier',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['p1'],
          tiers: [QuantityTier(quantity: 1, pricePaise: 1000)],
        ).toJson(),
      );
      final bogo = _offer(
        id: 'bogo',
        name: 'Bogo',
        type: OfferType.buyXGetY,
        config: const BuyXGetYOfferConfig(
          productId: 'p1',
          buyQty: 2,
          getQty: 1,
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 3, unitPricePaise: 10000),
        activeOffers: [bogo, tier],
      );
      expect(results.first.offerType, OfferType.quantityTier);
    });
  });

  group('multi-product quantity tier', () {
    test('single product still works (compatibility)', () {
      final offer = _offer(
        id: 'qt-single',
        name: 'Single Kulfi',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['kulfi-1'],
          tiers: [QuantityTier(quantity: 1, pricePaise: 8000)],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'kulfi-1', quantity: 1, unitPricePaise: 10000),
        activeOffers: [offer],
      );
      expect(results, hasLength(1));
      expect(results.single.discountPaise, 2000);
    });

    test('multiple products share the same tiers', () {
      final offer = _offer(
        id: 'qt-multi',
        name: 'Kulfi Quantity Offer',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['strawberry', 'blueberry', 'bombay', 'brownie'],
          tiers: [
            QuantityTier(quantity: 1, pricePaise: 8000),
            QuantityTier(quantity: 2, pricePaise: 14000),
            QuantityTier(quantity: 3, pricePaise: 19500),
          ],
        ).toJson(),
      );
      for (final id in ['strawberry', 'blueberry', 'bombay', 'brownie']) {
        final results = calculateLineOffers(
          line: _line(productId: id, quantity: 2, unitPricePaise: 10000),
          activeOffers: [offer],
        );
        expect(results, hasLength(1), reason: '$id should match');
        expect(results.single.discountPaise, 6000, reason: '$id');
      }
    });

    test('product not in the list does not match', () {
      final offer = _offer(
        id: 'qt-excl',
        name: 'Excluded',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['strawberry'],
          tiers: [QuantityTier(quantity: 1, pricePaise: 8000)],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'other', quantity: 1, unitPricePaise: 10000),
        activeOffers: [offer],
      );
      expect(results, isEmpty);
    });

    test('popsicles qty 1 = 80, qty 2 = 140, qty 3 = 195', () {
      final offer = _offer(
        id: 'popsicle',
        name: 'Popsicle Offer',
        type: OfferType.quantityTier,
        config: const QuantityTierOfferConfig(
          productIds: ['popsicle-1'],
          tiers: [
            QuantityTier(quantity: 1, pricePaise: 8000),
            QuantityTier(quantity: 2, pricePaise: 14000),
            QuantityTier(quantity: 3, pricePaise: 19500),
          ],
        ).toJson(),
      );
      final r1 = calculateLineOffers(
        line: _line(
          productId: 'popsicle-1',
          quantity: 1,
          unitPricePaise: 10000,
        ),
        activeOffers: [offer],
      );
      expect(r1.single.discountPaise, 2000);
      final r2 = calculateLineOffers(
        line: _line(
          productId: 'popsicle-1',
          quantity: 2,
          unitPricePaise: 10000,
        ),
        activeOffers: [offer],
      );
      expect(r2.single.discountPaise, 6000);
      final r3 = calculateLineOffers(
        line: _line(
          productId: 'popsicle-1',
          quantity: 3,
          unitPricePaise: 10000,
        ),
        activeOffers: [offer],
      );
      expect(r3.single.discountPaise, 10500);
    });

    test('non-quantity-tier offers are unaffected', () {
      final pct = _offer(
        id: 'pct',
        name: '10%',
        type: OfferType.percentage,
        config: const PercentageOfferConfig(
          percent: 10,
          productIds: ['p1'],
        ).toJson(),
      );
      final results = calculateLineOffers(
        line: _line(productId: 'p1', quantity: 5, unitPricePaise: 10000),
        activeOffers: [pct],
      );
      expect(results.single.discountPaise, 5000);
    });
  });
}
