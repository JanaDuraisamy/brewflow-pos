import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const coffee = CartLine(
    productId: 'p1',
    productName: 'Filter Coffee',
    sku: 'FC-01',
    unitPricePaise: 12000,
    quantity: 1,
    maxQuantity: 5,
  );
  const tea = CartLine(
    productId: 'p2',
    productName: 'Green Tea',
    unitPricePaise: 8000,
    quantity: 2,
    maxQuantity: 3,
  );

  group('Cart model', () {
    test('empty cart has no lines, total, or count', () {
      const cart = Cart.empty;
      expect(cart.isEmpty, isTrue);
      expect(cart.lines, isEmpty);
      expect(cart.itemCount, 0);
      expect(cart.subtotalPaise, 0);
      expect(cart.totalPaise, 0);
      expect(cart.lineFor('p1'), isNull);
    });

    test('lines compute their total from unit price times quantity', () {
      expect(coffee.lineTotalPaise, 12000);
      expect(tea.lineTotalPaise, 16000);
    });

    test('withAdded appends and totals lines', () {
      final cart = Cart.empty.withAdded(coffee).withAdded(tea);
      expect(cart.isEmpty, isFalse);
      expect(cart.lines.length, 2);
      expect(cart.itemCount, 3);
      expect(cart.quantityOf('p1'), 1);
      expect(cart.quantityOf('p2'), 2);
      expect(cart.subtotalPaise, 28000);
      expect(cart.totalPaise, 28000);
    });

    test('withLineQuantity replaces an existing line quantity only', () {
      final cart = Cart.empty.withAdded(coffee).withAdded(tea);
      final updated = cart.withLineQuantity('p1', 3);
      expect(updated.quantityOf('p1'), 3);
      expect(updated.lines.length, 2);
      expect(updated.subtotalPaise, 52000);

      final untouched = cart.withLineQuantity('missing', 9);
      expect(untouched, same(cart));
    });

    test('without removes a line and is a no-op for unknown ids', () {
      final cart = Cart.empty.withAdded(coffee).withAdded(tea);
      final reduced = cart.without('p1');
      expect(reduced.lines.length, 1);
      expect(reduced.quantityOf('p1'), 0);
      expect(reduced.subtotalPaise, 16000);

      final untouched = cart.without('missing');
      expect(untouched.lines.length, 2);
    });

    test('clear returns an empty cart', () {
      final cart = Cart.empty.withAdded(coffee).clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.lines, isEmpty);
    });

    test('an empty cart is a walk-in sale', () {
      expect(Cart.empty.selectedCustomerId, isNull);
    });

    test('withCustomer sets and clears the linked customer', () {
      expect(Cart.empty.withCustomer('c1').selectedCustomerId, 'c1');
      expect(
        Cart.empty.withCustomer('c1').withCustomer(null).selectedCustomerId,
        isNull,
      );
    });

    test(
      'the selected customer survives line mutations and resets on clear',
      () {
        final cart = Cart.empty
            .withCustomer('c1')
            .withAdded(coffee)
            .withLineQuantity('p1', 3)
            .without('p1')
            .withAdded(tea);
        expect(cart.selectedCustomerId, 'c1');
        expect(cart.clear().selectedCustomerId, isNull);
      },
    );

    test('exposed lines cannot be mutated through the getter', () {
      final cart = Cart.empty.withAdded(coffee);
      expect(() => cart.lines.add(tea), throwsUnsupportedError);
    });

    test('CartLine enforces positive quantity and capped maxQuantity', () {
      expect(
        () => CartLine(
          productId: 'p1',
          productName: 'X',
          unitPricePaise: 10,
          quantity: 0,
          maxQuantity: 5,
        ),
        throwsAssertionError,
      );
      expect(
        () => CartLine(
          productId: 'p1',
          productName: 'X',
          unitPricePaise: 10,
          quantity: 6,
          maxQuantity: 5,
        ),
        throwsAssertionError,
      );
    });
  });

  group('PaymentMethod', () {
    test('db values round-trip through fromDbValue', () {
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.fromDbValue(method.dbValue), method);
      }
    });

    test('unknown db values are rejected', () {
      expect(PaymentMethod.fromDbValue('CHEQUE'), isNull);
      expect(PaymentMethod.fromDbValue(''), isNull);
    });
  });

  group('member pricing', () {
    const memberCoffee = CartLine(
      productId: 'p1',
      productName: 'Filter Coffee',
      unitPricePaise: 12000,
      memberPricePaise: 9000,
      quantity: 1,
      maxQuantity: 5,
    );

    test(
      'chargedUnitPricePaise applies the member price only when enabled',
      () {
        expect(memberCoffee.chargedUnitPricePaise(false), 12000);
        expect(memberCoffee.chargedUnitPricePaise(true), 9000);
        expect(coffee.chargedUnitPricePaise(true), 12000);
      },
    );

    test('chargedLineTotalPaise guards the member price times quantity', () {
      expect(memberCoffee.chargedLineTotalPaise(true), 9000);
      expect(memberCoffee.chargedLineTotalPaise(false), 12000);
      expect(tea.chargedLineTotalPaise(true), 16000);
    });

    test('chargedTotalPaise mixes member and regular lines', () {
      final cart = Cart.empty
          .withAdded(memberCoffee)
          .withAdded(tea)
          .withMemberPricing(true);
      expect(cart.chargedTotalPaise, 9000 + 16000);
      expect(cart.subtotalPaise, 12000 + 16000);
    });

    test('resolvedLines re-price only items with a member snapshot', () {
      final cart = Cart.empty
          .withAdded(memberCoffee)
          .withAdded(tea)
          .withMemberPricing(true);
      final resolved = cart.resolvedLines;
      expect(resolved.first.unitPricePaise, 9000);
      expect(resolved.last.unitPricePaise, 8000);

      final regular = cart.withMemberPricing(false).resolvedLines;
      expect(regular.first.unitPricePaise, 12000);
    });

    test('withMemberPricing toggles and survives line mutations', () {
      final cart = Cart.empty
          .withMemberPricing(true)
          .withAdded(memberCoffee)
          .withLineQuantity('p1', 2)
          .withCustomer('c1');
      expect(cart.memberPricing, isTrue);
      expect(cart.chargedTotalPaise, 18000);

      final toggled = cart.withMemberPricing(false);
      expect(toggled.memberPricing, isFalse);
      expect(toggled.chargedTotalPaise, 24000);
      expect(toggled.selectedCustomerId, 'c1');

      expect(cart.clear().memberPricing, isFalse);
    });
  });
}
