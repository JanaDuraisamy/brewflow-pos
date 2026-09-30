// Drift generates its own `SalePayment` row class; the domain model's
// `SalePayment` is what the API takes, so only the generated name is hidden.
import 'package:brewflow_pos/core/database/app_database.dart' hide SalePayment;
import 'package:brewflow_pos/features/billing/data/drift_billing_repository.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/billing_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_cloud_gateway.dart';

/// ---------------------------------------------------------------------------
/// Split-payment persistence and shop isolation, against a real Drift database.
///
/// The gates a split sale passes through, each of which used to reject or
/// corrupt a valid split:
///
///  1. `DriftBillingRepository.completeSale` demanded a single `paymentMethod`
///     even when valid `payments` legs were supplied, so every split died with
///     INVALID_PAYMENT.
///  2. `_completeSaleViaCloud` force-unwrapped `paymentMethod!` (a null-check
///     crash that bypassed every failure mapping) and never forwarded
///     `payments`, so the server would persist a split with no `sale_payments`
///     rows at all.
///  3. The POS gate on the Complete Sale button is covered in
///     `pos_split_payment_test.dart`.
///
/// Cafe and Food Truck are separate shops with separate stock, so the same
/// cases run against both to prove no payment or sale state leaks across.
/// ---------------------------------------------------------------------------
void main() {
  const cafeShop = 'shop-cafe';
  const truckShop = 'shop-truck';

  // ₹278 exactly, so the brief's amounts are the real ones.
  const totalPaise = 27800;

  late AppDatabase db;
  late DriftBillingRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = DriftBillingRepository(db);

    for (final shop in [cafeShop, truckShop]) {
      await db
          .into(db.shops)
          .insert(ShopsCompanion.insert(id: Value(shop), name: shop));
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: Value('cat-$shop'),
              shopId: Value(shop),
              name: 'Beverages',
            ),
          );
      await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              id: Value('p-$shop'),
              shopId: Value(shop),
              categoryId: 'cat-$shop',
              name: 'Combo Ride $shop',
              sellingPricePaise: totalPaise,
              stockQuantity: const Value(10),
              isActive: const Value(true),
            ),
          );
    }
    // An OWNER carries no shop, so the sale shop must come from the product.
    await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            email: 'owner@example.com',
            role: const Value('OWNER'),
          ),
        );
  });

  tearDown(() async => db.close());

  String productOf(String shop) => 'p-$shop';

  CartLine line(String shop) => CartLine(
    productId: productOf(shop),
    productName: 'Combo Ride $shop',
    sku: null,
    unitPricePaise: totalPaise,
    quantity: 1,
    maxQuantity: 99,
  );

  /// Reads back the rows the sale actually wrote.
  Future<
    ({
      String? shopId,
      int headerPaise,
      String? headerMethod,
      List<({String m, int a})> legs,
    })
  >
  persisted(String saleId) async {
    final sale = await (db.select(
      db.sales,
    )..where((t) => t.id.equals(saleId))).getSingle();
    final rows = await (db.select(
      db.salePayments,
    )..where((t) => t.saleId.equals(saleId))).get();
    return (
      shopId: sale.shopId,
      headerPaise: sale.totalPaise,
      headerMethod: sale.paymentMethod,
      legs: [for (final r in rows) (m: r.paymentMethod, a: r.amountPaise)],
    );
  }

  Future<int> stockOf(String shop) async {
    final row = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productOf(shop)))).getSingle();
    return row.stockQuantity;
  }

  Future<int> movementCount(String shop) async {
    final rows = await (db.select(
      db.stockMovements,
    )..where((t) => t.productId.equals(productOf(shop)))).get();
    return rows.length;
  }

  List<SalePayment> legsOf(int cash, int upi) => [
    SalePayment(paymentMethod: PaymentMethod.cash, amountPaise: cash),
    SalePayment(paymentMethod: PaymentMethod.upi, amountPaise: upi),
  ];

  /// Runs the same contract against whichever shop, proving identical
  /// behaviour and no cross-shop leakage.
  void splitContract(String shop) {
    group(shop == cafeShop ? 'Cafe' : 'Food Truck', () {
      test(
        '₹200 CASH + ₹78 UPI = ₹278 completes and persists both legs',
        () async {
          final completed = await repo.completeSale(
            lines: [line(shop)],
            paymentStatus: PaymentStatus.paid,
            shopId: shop,
            payments: legsOf(20000, 7800),
          );

          expect(completed.sale.totalPaise, totalPaise);
          expect(completed.sale.payments, hasLength(2));
          expect(completed.sale.payments[0].paymentMethod, PaymentMethod.cash);
          expect(completed.sale.payments[0].amountPaise, 20000);
          expect(completed.sale.payments[1].paymentMethod, PaymentMethod.upi);
          expect(completed.sale.payments[1].amountPaise, 7800);

          final rows = await persisted(completed.sale.id);
          expect(rows.shopId, shop, reason: 'the sale is scoped to its shop');
          expect(rows.headerPaise, totalPaise);
          expect(
            rows.headerMethod,
            isNull,
            reason: 'a split leaves the header method empty; the legs carry it',
          );
          expect(rows.legs, hasLength(2));
          expect(rows.legs[0].m, 'CASH');
          expect(rows.legs[0].a, 20000);
          expect(rows.legs[1].m, 'UPI');
          expect(rows.legs[1].a, 7800);
        },
      );

      test(
        '₹100 CASH + ₹178 UPI = ₹278 completes and persists both legs',
        () async {
          final completed = await repo.completeSale(
            lines: [line(shop)],
            paymentStatus: PaymentStatus.paid,
            shopId: shop,
            payments: legsOf(10000, 17800),
          );

          final rows = await persisted(completed.sale.id);
          expect(rows.legs.map((l) => l.a), [10000, 17800]);
          expect(rows.legs.map((l) => l.m), ['CASH', 'UPI']);
          expect(rows.headerPaise, totalPaise);
        },
      );

      test('decimal rupees persist exactly: ₹200.50 + ₹77.50', () async {
        final completed = await repo.completeSale(
          lines: [line(shop)],
          paymentStatus: PaymentStatus.paid,
          shopId: shop,
          payments: legsOf(20050, 7750),
        );

        final rows = await persisted(completed.sale.id);
        expect(rows.legs.map((l) => l.a), [20050, 7750]);
        // Integer paise throughout: no float drift, and the legs still sum to
        // the integer total.
        expect(rows.legs.fold<int>(0, (a, l) => a + l.a), totalPaise);
      });

      test('an incomplete split is rejected and writes nothing', () async {
        // The controller checks the sum first, but the repository is what
        // inserts `sale_payments`, so it re-checks and must leave no trace.
        await expectLater(
          () => repo.completeSale(
            lines: [line(shop)],
            paymentStatus: PaymentStatus.paid,
            shopId: shop,
            payments: legsOf(20000, 7000),
          ),
          throwsA(
            isA<UnexpectedBillingFailure>().having(
              (e) => e.message,
              'message',
              contains('short'),
            ),
          ),
        );
        expect(await stockOf(shop), 10);
        expect(await movementCount(shop), 0);
        expect(await db.select(db.sales).get(), isEmpty);
        expect(await db.select(db.salePayments).get(), isEmpty);
      });

      test('overpayment is rejected and writes nothing', () async {
        await expectLater(
          () => repo.completeSale(
            lines: [line(shop)],
            paymentStatus: PaymentStatus.paid,
            shopId: shop,
            payments: legsOf(20000, 10000),
          ),
          throwsA(
            isA<UnexpectedBillingFailure>().having(
              (e) => e.message,
              'message',
              contains('exceed'),
            ),
          ),
        );
        expect(await stockOf(shop), 10);
        expect(await db.select(db.salePayments).get(), isEmpty);
      });

      test('a zero-value leg is rejected before the insert', () async {
        // `sale_payments.amount_paise` has CHECK (> 0); a zero leg would abort
        // the whole sale at the insert instead of failing with a reason.
        await expectLater(
          () => repo.completeSale(
            lines: [line(shop)],
            paymentStatus: PaymentStatus.paid,
            shopId: shop,
            payments: const [
              SalePayment(paymentMethod: PaymentMethod.cash, amountPaise: 0),
            ],
          ),
          throwsA(isA<InvalidPaymentFailure>()),
        );
        expect(await stockOf(shop), 10);
      });

      test('inventory is mutated exactly once', () async {
        final before = await stockOf(shop);
        await repo.completeSale(
          lines: [line(shop)],
          paymentStatus: PaymentStatus.paid,
          shopId: shop,
          payments: legsOf(20000, 7800),
        );
        expect(await stockOf(shop), before - 1);
        expect(
          await movementCount(shop),
          1,
          reason: 'a split is one sale, so stock moves once — not once per leg',
        );
      });

      test('single CASH still works', () async {
        final completed = await repo.completeSale(
          lines: [line(shop)],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.cash,
          shopId: shop,
        );
        final rows = await persisted(completed.sale.id);
        expect(rows.headerMethod, 'CASH');
        expect(rows.legs, isEmpty);
      });

      test('single UPI still works', () async {
        final completed = await repo.completeSale(
          lines: [line(shop)],
          paymentStatus: PaymentStatus.paid,
          paymentMethod: PaymentMethod.upi,
          shopId: shop,
        );
        final rows = await persisted(completed.sale.id);
        expect(rows.headerMethod, 'UPI');
        expect(rows.legs, isEmpty);
      });
    });
  }

  splitContract(cafeShop);
  splitContract(truckShop);

  group('shop isolation', () {
    test('a Cafe split does not touch Food Truck stock or payments', () async {
      final cafeSale = await repo.completeSale(
        lines: [line(cafeShop)],
        paymentStatus: PaymentStatus.paid,
        shopId: cafeShop,
        payments: legsOf(20000, 7800),
      );
      final truckSale = await repo.completeSale(
        lines: [line(truckShop)],
        paymentStatus: PaymentStatus.paid,
        shopId: truckShop,
        payments: legsOf(10000, 17800),
      );

      expect((await persisted(cafeSale.sale.id)).shopId, cafeShop);
      expect((await persisted(truckSale.sale.id)).shopId, truckShop);

      // Each shop's legs are its own.
      expect((await persisted(cafeSale.sale.id)).legs.map((l) => l.a), [
        20000,
        7800,
      ]);
      expect((await persisted(truckSale.sale.id)).legs.map((l) => l.a), [
        10000,
        17800,
      ]);

      expect(await stockOf(cafeShop), 9);
      expect(await stockOf(truckShop), 9);
      expect(await movementCount(cafeShop), 1);
      expect(await movementCount(truckShop), 1);
    });

    test('payment rows stay attached to their own sale and shop', () async {
      final truck = await repo.completeSale(
        lines: [line(truckShop)],
        paymentStatus: PaymentStatus.paid,
        shopId: truckShop,
        payments: legsOf(20000, 7800),
      );
      final truckLegs = await (db.select(
        db.salePayments,
      )..where((t) => t.saleId.equals(truck.sale.id))).get();
      final sale = await (db.select(
        db.sales,
      )..where((t) => t.id.equals(truck.sale.id))).getSingle();

      expect(truckLegs, hasLength(2));
      expect(sale.shopId, truckShop);
      for (final leg in truckLegs) {
        expect(leg.saleId, truck.sale.id);
      }
    });
  });

  group('cloud path forwards the split', () {
    test('the RPC receives the legs and no single method', () async {
      final cloud = FakeBillingCloudGateway();
      final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

      await cloudRepo.completeSale(
        lines: [line(cafeShop)],
        paymentStatus: PaymentStatus.paid,
        shopId: cafeShop,
        payments: legsOf(20000, 7800),
      );

      expect(cloud.calls, hasLength(1));
      final call = cloud.lastCreateSale!;
      expect(call.shopId, cafeShop);
      expect(
        call.paymentMethod,
        isNull,
        reason: 'a split must not also send a single method',
      );
      expect(call.payments, hasLength(2));
      expect(call.payments!.first, {
        'payment_method': 'CASH',
        'amount_paise': 20000,
      });
      expect(call.payments!.last, {
        'payment_method': 'UPI',
        'amount_paise': 7800,
      });
      expect(call.totalPaise, totalPaise);
    });

    test(
      'the same split on the Food Truck context is forwarded there',
      () async {
        final cloud = FakeBillingCloudGateway();
        final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

        await cloudRepo.completeSale(
          lines: [line(truckShop)],
          paymentStatus: PaymentStatus.paid,
          shopId: truckShop,
          payments: legsOf(20000, 7800),
        );

        final call = cloud.lastCreateSale!;
        expect(call.shopId, truckShop);
        expect(call.payments, hasLength(2));
      },
    );

    test('a single method still sends the method and no legs', () async {
      final cloud = FakeBillingCloudGateway();
      final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

      await cloudRepo.completeSale(
        lines: [line(cafeShop)],
        paymentStatus: PaymentStatus.paid,
        paymentMethod: PaymentMethod.cash,
        shopId: cafeShop,
      );

      final call = cloud.lastCreateSale!;
      expect(call.paymentMethod, 'CASH');
      expect(call.payments, isNull);
    });

    test('a split does not null-check crash on the cloud path', () async {
      // The regression: `paymentMethod!.dbValue` threw a TypeError that no
      // failure mapping caught, so the sale never completed and the error
      // surfaced as an unhandled crash instead of a billing failure.
      final cloud = FakeBillingCloudGateway();
      final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

      await expectLater(
        cloudRepo.completeSale(
          lines: [line(cafeShop)],
          paymentStatus: PaymentStatus.paid,
          shopId: cafeShop,
          payments: legsOf(20000, 7800),
        ),
        completes,
      );
    });

    test('a mismatched split never reaches the server', () async {
      final cloud = FakeBillingCloudGateway();
      final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

      await expectLater(
        () => cloudRepo.completeSale(
          lines: [line(cafeShop)],
          paymentStatus: PaymentStatus.paid,
          shopId: cafeShop,
          payments: legsOf(20000, 7000),
        ),
        throwsA(isA<UnexpectedBillingFailure>()),
      );
      expect(
        cloud.calls,
        isEmpty,
        reason: 'a short split must not consume a server round trip',
      );
    });

    test('SPLIT_PAYMENT_MISMATCH becomes a readable failure', () async {
      final cloud = FakeBillingCloudGateway()
        ..nextError = Exception('SPLIT_PAYMENT_MISMATCH');
      final cloudRepo = DriftBillingRepository(db, cloudGateway: cloud);

      await expectLater(
        () => cloudRepo.completeSale(
          lines: [line(cafeShop)],
          paymentStatus: PaymentStatus.paid,
          shopId: cafeShop,
          payments: legsOf(20000, 7800),
        ),
        throwsA(
          isA<UnexpectedBillingFailure>().having(
            (e) => e.message,
            'message',
            contains('do not match'),
          ),
        ),
      );
    });
  });
}
