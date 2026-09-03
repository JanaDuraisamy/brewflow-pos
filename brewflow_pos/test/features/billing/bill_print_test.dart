import 'dart:async';

import 'package:brewflow_pos/core/sharing/share_service.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/billing/domain/receipt_document.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/billing/presentation/pos_page.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_models.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';
import 'package:brewflow_pos/features/printing/data/unverified_printer_service.dart';
import 'package:brewflow_pos/features/printing/domain/printer_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_billing_repository.dart';
import '../../helpers/fake_customers_repository.dart';
import '../../helpers/fake_inventory_repository.dart';

/// Printer that always fails — used to prove the sale survives print errors.
final class FailingPrinterService implements PrinterService {
  int attempts = 0;

  @override
  String get statusLabel => 'Test printer (failing)';

  @override
  Future<PrintResult> print(ReceiptDocument document) async {
    attempts += 1;
    return const PrintFailure('Printer reported a paper jam.');
  }

  @override
  Future<PrintResult> testPrint() => print(
    ReceiptDocument.fromSale(
      shopName: 'Test',
      sale: Sale(
        id: 't',
        receiptNumber: 'BF-000001',
        subtotalPaise: 0,
        totalPaise: 0,
        offerDiscountPaise: 0,
        paymentStatus: PaymentStatus.paid,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      items: const [],
    ),
  );
}

/// Records every submitted document so tests can assert exactly what the
/// printer received; optionally blocks until [release] completes so an
/// in-flight job can be inspected.
final class RecordingPrinterService implements PrinterService {
  final List<ReceiptDocument> printed = [];
  int attempts = 0;
  Completer<void>? release;

  @override
  String get statusLabel => 'Test printer (recording)';

  @override
  Future<PrintResult> print(ReceiptDocument document) async {
    attempts += 1;
    printed.add(document);
    final gate = release;
    if (gate != null) {
      await gate.future;
    }
    return const PrintSuccess();
  }

  @override
  Future<PrintResult> testPrint() => print(
    ReceiptDocument.fromSale(
      shopName: 'Test',
      sale: Sale(
        id: 't',
        receiptNumber: 'BF-000001',
        subtotalPaise: 0,
        totalPaise: 0,
        offerDiscountPaise: 0,
        paymentStatus: PaymentStatus.paid,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
      items: const [],
    ),
  );
}

Future<(ProviderContainer, FakeBillingRepository, FailingPrinterService)>
_pumpCompletedSale(WidgetTester tester) async {
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
  final printer = FailingPrinterService();
  final container = ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inventory),
      billingRepositoryProvider.overrideWithValue(billing),
      customersRepositoryProvider.overrideWithValue(FakeCustomersRepository()),
      shareServiceProvider.overrideWithValue(_NoopShare()),
      printerServiceProvider.overrideWithValue(printer),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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

  expect(find.text('Sale Complete'), findsOneWidget);
  return (container, billing, printer);
}

final class _NoopShare implements ShareService {
  @override
  Future<void> shareText({
    required String subject,
    required String text,
  }) async {}
}

/// Pumps the POS and completes a [customerToSelect]-linked sale with [printer]
/// bound. Returns the container plus the customer repo so tests can seed and
/// inspect data.
Future<(ProviderContainer, FakeCustomersRepository, PrinterService)>
_pumpReceipt(
  WidgetTester tester, {
  required PrinterService printer,
  FakeCustomersRepository? customers,
  bool completeSale = true,
}) async {
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
  final customersRepo = customers ?? FakeCustomersRepository();
  final container = ProviderContainer(
    overrides: [
      inventoryRepositoryProvider.overrideWithValue(inventory),
      billingRepositoryProvider.overrideWithValue(billing),
      customersRepositoryProvider.overrideWithValue(customersRepo),
      shareServiceProvider.overrideWithValue(_NoopShare()),
      printerServiceProvider.overrideWithValue(printer),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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

  if (completeSale) {
    await tester.ensureVisible(find.text('Cash'));
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Complete Sale'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
    await tester.pumpAndSettle();
    expect(find.text('Sale Complete'), findsOneWidget);
  }

  return (container, customersRepo, printer);
}

Future<void> _selectCustomer(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.text('Walk-in'));
  await tester.tap(find.text('Walk-in'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('print failure surfaces the message and keeps the sale intact', (
    tester,
  ) async {
    final (_, billing, printer) = await _pumpCompletedSale(tester);

    await tester.ensureVisible(find.text('Print'));
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.attempts, 1);
    expect(find.textContaining('paper jam'), findsOneWidget);
    expect(
      billing.storedSales.length,
      1,
      reason: 'print failure never affects the completed sale',
    );
    expect(
      find.text('Sale Complete'),
      findsOneWidget,
      reason: 'receipt stays open so the counter can retry',
    );
  });

  testWidgets('unverified default printer reports honest unavailability', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final service = container.read(printerServiceProvider);
    expect(service, isA<UnverifiedPrinterService>());
    expect(service.statusLabel, contains('not yet verified'));
  });

  testWidgets('retry after a failed print submits the receipt again', (
    tester,
  ) async {
    final printer = FailingPrinterService();
    await _pumpReceipt(tester, printer: printer);

    await tester.ensureVisible(find.text('Print'));
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(find.textContaining('paper jam'), findsOneWidget);

    // Counter retries from the still-open receipt; each attempt moves the
    // job again and never touches the completed sale.
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(printer.attempts, 2);
    expect(find.textContaining('paper jam'), findsOneWidget);
    expect(find.text('Sale Complete'), findsOneWidget);
  });

  testWidgets('Print cannot double-submit while a job is in flight', (
    tester,
  ) async {
    final printer = RecordingPrinterService()..release = Completer<void>();
    await _pumpReceipt(tester, printer: printer);

    await tester.ensureVisible(find.text('Print'));
    await tester.tap(find.text('Print'));
    await tester.pump();

    // First job is in flight; the action is disabled and relabelled.
    expect(printer.attempts, 1);
    expect(find.text('Printing…'), findsOneWidget);

    // The disabled control cannot enqueue a second job.
    await tester.tap(find.text('Printing…'));
    await tester.pump();
    expect(printer.attempts, 1);

    printer.release!.complete();
    await tester.pumpAndSettle();
    expect(printer.attempts, 1, reason: 'one sale prints exactly once');
    expect(find.text('Printed'), findsOneWidget);
  });

  testWidgets('receipt print carries the linked customer name', (tester) async {
    final customers = FakeCustomersRepository()
      ..storedCustomers.add(
        Customer(
          id: 'c1',
          name: 'Anand',
          phone: null,
          isActive: true,
          membershipActive: false,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    final printer = RecordingPrinterService();
    await _pumpReceipt(
      tester,
      printer: printer,
      customers: customers,
      completeSale: false,
    );
    await _selectCustomer(tester, 'Anand');
    expect(find.text('Anand'), findsOneWidget);

    await tester.ensureVisible(find.text('Cash'));
    await tester.tap(find.text('Cash'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Complete Sale'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Complete Sale'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Print'));
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printer.printed, hasLength(1));
    expect(printer.printed.single.customerName, 'Anand');
  });
}
