import 'package:brewflow_pos/core/notifications/stock_notification_deduper.dart';
import 'package:brewflow_pos/core/notifications/stock_notification_payload.dart';
import 'package:brewflow_pos/core/notifications/stock_notification_service.dart';
import 'package:brewflow_pos/features/inventory/domain/stock_alerts.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/inventory/presentation/stock_notification_gate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Android system stock notifications contract (local only).
///
/// Local notifications for stock transitions the app observes; no push
/// infrastructure exists, so killed-app cross-device delivery is an explicit
/// non-goal (reported, not claimed).
/// ---------------------------------------------------------------------------

StockAlert alert(
  String productId, {
  String? variantId,
  StockAlertKind kind = StockAlertKind.lowStock,
  String? shopId = 'shop-1',
  int stock = 4,
}) => StockAlert(
  key: '${shopId ?? '-'}|$productId|${variantId ?? '-'}',
  kind: kind,
  shopId: shopId,
  productId: productId,
  variantId: variantId,
  productName: 'Product $productId',
  variantName: variantId == null ? null : 'Variant $variantId',
  stock: stock,
  threshold: 10,
);

final class FakeStockGateway implements StockNotificationGateway {
  bool permissionGranted = true;
  bool permissionAsked = false;
  final List<StockAlert> shown = [];
  final List<String?> taps = [];
  Future<void> Function(String? payload)? onTap;

  @override
  Future<void> init(Future<void> Function(String? payload) onTap) async {
    this.onTap = onTap;
  }

  @override
  Future<bool> ensurePermission() async {
    permissionAsked = true;
    return permissionGranted;
  }

  @override
  Future<void> showAlert(StockAlert alert) async {
    shown.add(alert);
  }

  @override
  Future<String?> consumeLaunchPayload() async => null;

  Future<void> tap(String? payload) async {
    taps.add(payload);
    await onTap?.call(payload);
  }
}

void main() {
  group('payload codec', () {
    test('round-trips product and variant targets', () {
      final encoded = encodeStockAlertTap(
        productId: 'p-1',
        variantId: 'v-2',
        shopId: 'shop-1',
      );
      final decoded = decodeStockAlertTap(encoded)!;
      expect(decoded.productId, 'p-1');
      expect(decoded.variantId, 'v-2');
      expect(decoded.shopId, 'shop-1');
    });

    test('malformed payloads decode to null and never throw', () {
      expect(decodeStockAlertTap(null), isNull);
      expect(decodeStockAlertTap(''), isNull);
      expect(decodeStockAlertTap('garbage'), isNull);
      expect(decodeStockAlertTap('stock||'), isNull);
      expect(decodeStockAlertTap('other|p|v|s'), isNull);
    });
  });

  group('deduper', () {
    test('notifies new low-stock and out-of-stock transitions', () {
      final first = decideStockNotifications(
        known: const {},
        current: [
          alert('p-1'),
          alert('p-2', kind: StockAlertKind.outOfStock),
        ],
      );
      expect(first.toNotify.map((a) => a.productId), {'p-1', 'p-2'});

      // Same shelf on the next rebuild: silence (no spam).
      final second = decideStockNotifications(
        known: first.nextKnown,
        current: [
          alert('p-1'),
          alert('p-2', kind: StockAlertKind.outOfStock),
        ],
      );
      expect(second.toNotify, isEmpty);
    });

    test('low escalating to out notifies again', () {
      final first = decideStockNotifications(
        known: const {},
        current: [alert('p-1', kind: StockAlertKind.lowStock)],
      );
      final escalated = decideStockNotifications(
        known: first.nextKnown,
        current: [alert('p-1', kind: StockAlertKind.outOfStock, stock: 0)],
      );
      expect(escalated.toNotify.map((a) => a.productId), ['p-1']);
    });

    test('resolved then recurring shortages re-notify', () {
      final first = decideStockNotifications(
        known: const {},
        current: [alert('p-1')],
      );
      final cleared = decideStockNotifications(
        known: first.nextKnown,
        current: const [],
      );
      expect(cleared.toNotify, isEmpty);
      final recurred = decideStockNotifications(
        known: cleared.nextKnown,
        current: [alert('p-1')],
      );
      expect(recurred.toNotify.map((a) => a.productId), ['p-1']);
    });
  });

  group('gate with fake gateway', () {
    test('shows low and out alerts with shop/product identity', () async {
      final fake = FakeStockGateway();
      final container = ProviderContainer(
        overrides: [stockNotificationGatewayProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final gate = container.read(stockNotificationGateProvider);
      await gate.syncAlerts([
        alert('p-1', shopId: 'shop-1'),
        alert('p-2', kind: StockAlertKind.outOfStock, shopId: 'shop-2'),
      ]);

      expect(fake.permissionAsked, isTrue);
      expect(fake.shown, hasLength(2));
      expect(stockNotificationTitle(fake.shown.first), contains('Low stock'));
      expect(stockNotificationBody(fake.shown.last), contains('out of stock'));
      // Duplicate sync: no second system row.
      await gate.syncAlerts([
        alert('p-1', shopId: 'shop-1'),
        alert('p-2', kind: StockAlertKind.outOfStock, shopId: 'shop-2'),
      ]);
      expect(fake.shown, hasLength(2));
    });

    test('permission denial skips quietly and never crashes', () async {
      final fake = FakeStockGateway()..permissionGranted = false;
      final container = ProviderContainer(
        overrides: [stockNotificationGatewayProvider.overrideWithValue(fake)],
      );
      addTearDown(container.dispose);

      final gate = container.read(stockNotificationGateProvider);
      await gate.syncAlerts([alert('p-1')]);
      expect(fake.shown, isEmpty);
    });

    test('tap payload focuses Inventory on the exact product', () async {
      final container = ProviderContainer(
        overrides: [
          stockNotificationGatewayProvider.overrideWithValue(
            FakeStockGateway(),
          ),
        ],
      );
      addTearDown(container.dispose);

      final payload = encodeStockAlertTap(
        productId: 'p-9',
        variantId: 'v-3',
        shopId: 'shop-1',
      );
      final target = decodeStockAlertTap(payload)!;
      container
          .read(inventoryFilterProvider.notifier)
          .focusOn(productId: target.productId, variantId: target.variantId);
      expect(container.read(inventoryFilterProvider).focusProductId, 'p-9');
      expect(container.read(inventoryFilterProvider).focusVariantId, 'v-3');
    });
  });
}
