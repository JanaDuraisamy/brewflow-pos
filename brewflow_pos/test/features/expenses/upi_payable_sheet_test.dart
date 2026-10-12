import 'dart:async';

import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/upi_app_launcher.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/expenses/presentation/shop_payables_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_upi_app_launcher.dart';
import '../../helpers/test_providers.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Payable UPI handoff sheet.
///
/// The UPI flow never verifies money: apps are listed, one is launched, and
/// only a post-launch resume reveals an unchecked manual checkbox that gates
/// Record Payment. Every test below drives the real sheet against fakes —
/// never real installed apps.
/// ---------------------------------------------------------------------------

void main() {
  late FakeExpensesRepository expenses;
  late FakeUpiAppLauncher upi;

  setUp(() {
    expenses = FakeExpensesRepository();
    upi = FakeUpiAppLauncher();
    // One unpaid supplier bill: the only payable on screen, ₹1000.00 owed.
    expenses.seed(
      name: 'Naren',
      amountPaise: 100000,
      category: ExpenseCategory.supplies,
      paymentMethod: PaymentMethod.cash,
      expenseDate: DateTime.now().toUtc(),
      paymentStatus: ExpensePaymentStatus.notPaid,
    );
  });

  Widget harness() => ProviderScope(
    overrides: [
      expensesRepositoryProvider.overrideWithValue(expenses),
      upiAppLauncherProvider.overrideWithValue(upi),
      ...businessScopeOverrides(),
    ],
    child: const MaterialApp(home: Scaffold(body: ShopPayablesPage())),
  );

  Future<void> pumpSheet(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(800, 1600);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  Future<void> openPaySheet(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Pay'));
    await tester.pumpAndSettle();
    expect(find.text('Pay Naren'), findsOneWidget);
  }

  Future<void> selectMethod(WidgetTester tester, String label) async {
    await tester.tap(find.byType(DropdownButtonFormField<PaymentMethod>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectUpiApp(WidgetTester tester, String name) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  void resumeApp(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Finder recordButton() => find.widgetWithText(FilledButton, 'Record Payment');

  bool recordEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(recordButton()).onPressed != null;

  group('UPI app discovery', () {
    testWidgets('lists installed handlers after selecting UPI', (tester) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');

      expect(find.text('Select a UPI app'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('PhonePe'), findsOneWidget);
      expect(find.text('Paytm'), findsOneWidget);
      // Dismiss the app menu; the handoff picker stays unselected.
      await tester.tapAt(const Offset(400, 100));
      await tester.pumpAndSettle();
      expect(find.text('Open UPI app'), findsOneWidget);
      // Selecting UPI alone never reveals the confirmation.
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty app list falls back to manual record', (tester) async {
      upi.apps = const [];
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');

      expect(
        find.text(
          'No UPI apps found on this device. Pay in your UPI app, then '
          'record the payment here manually.',
        ),
        findsOneWidget,
      );
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isTrue);

      await tapVisible(tester, recordButton());
      final payment = expenses.storedPayablePayments.single;
      expect(payment.paymentMethod, PaymentMethod.upi);
      expect(payment.amountPaise, 100000);
      expect(tester.takeException(), isNull);
    });

    testWidgets('launch failure shows an error and allows manual record', (
      tester,
    ) async {
      upi.launchError = const UpiLauncherException('PhonePe is gone.');
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'PhonePe');

      await tapVisible(tester, find.text('Open UPI app'));
      expect(find.textContaining('PhonePe is gone.'), findsOneWidget);
      expect(
        find.textContaining('record the payment manually after paying'),
        findsOneWidget,
      );
      // Blocked launch must not block the expense.
      expect(recordEnabled(tester), isTrue);

      await tapVisible(tester, recordButton());
      expect(expenses.storedPayablePayments.single.amountPaise, 100000);
      expect(tester.takeException(), isNull);
    });
  });

  group('launch → resume → confirm lifecycle', () {
    testWidgets('checkbox appears only after launch followed by resume', (
      tester,
    ) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'PhonePe');

      // Launched but not yet returned: waiting hint, no checkbox.
      await tapVisible(tester, find.text('Open UPI app'));
      expect(upi.launches.single.packageName, 'com.phonepe.app');
      expect(upi.launches.single.amountRupees, '1000.00');
      expect(upi.launches.single.currency, 'INR');
      expect(find.textContaining('Complete the payment there'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isFalse);

      resumeApp(tester);
      await tester.pumpAndSettle();
      final checkbox = find.byType(CheckboxListTile);
      expect(checkbox, findsOneWidget);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      // Still unchecked: Record stays disabled.
      expect(recordEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a resume without confirmation records nothing', (
      tester,
    ) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'Google Pay');
      await tapVisible(tester, find.text('Open UPI app'));

      // Returning is not paying: three resumes, zero rows.
      resumeApp(tester);
      await tester.pump();
      resumeApp(tester);
      await tester.pump();
      resumeApp(tester);
      await tester.pumpAndSettle();

      expect(expenses.storedPayablePayments, isEmpty);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(recordEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('checked confirmation records method, amount, note and time', (
      tester,
    ) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await tester.enterText(find.byType(TextFormField).first, '250.50');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).last, 'Milk bill');
      await tester.pumpAndSettle();
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'Paytm');

      final beforeLaunch = DateTime.now().toUtc();
      await tapVisible(tester, find.text('Open UPI app'));
      // The launch carries the URI hint but writes no payment row.
      expect(upi.launches.single.amountRupees, '250.50');
      expect(upi.launches.single.note, 'Milk bill');
      expect(expenses.storedPayablePayments, isEmpty);

      resumeApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(recordEnabled(tester), isTrue);

      await tapVisible(tester, recordButton());
      final payment = expenses.storedPayablePayments.single;
      expect(payment.paymentMethod, PaymentMethod.upi);
      expect(payment.amountPaise, 25050);
      expect(payment.note, 'Milk bill');
      // Timestamped at the confirmation submit, never at launch.
      expect(payment.paidAt.isUtc, isTrue);
      expect(payment.paidAt.isBefore(beforeLaunch), isFalse);
      expect(
        payment.paidAt.difference(DateTime.now().toUtc()).abs() <
            const Duration(minutes: 1),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('relaunch resets confirmation until the next return', (
      tester,
    ) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'PhonePe');
      await tapVisible(tester, find.text('Open UPI app'));
      resumeApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(recordEnabled(tester), isTrue);

      // Opening the app again supersedes the earlier return.
      await tapVisible(tester, find.text('Open UPI app'));
      expect(upi.launches, hasLength(2));
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isFalse);

      resumeApp(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('duplicate launches are disabled while one is in flight', (
      tester,
    ) async {
      upi.launchGate = Completer<void>();
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'PhonePe');

      await tester.ensureVisible(find.text('Open UPI app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open UPI app'));
      await tester.pump();
      // Second tap while launching records no second launch.
      await tester.tap(find.text('Opening…'));
      await tester.pump();
      expect(upi.launches, isEmpty);

      upi.launchGate!.complete();
      await tester.pumpAndSettle();
      expect(upi.launches, hasLength(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching method or editing amount resets the handoff', (
      tester,
    ) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');
      await selectUpiApp(tester, 'PhonePe');
      await tapVisible(tester, find.text('Open UPI app'));
      resumeApp(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);

      // Cash needs no handoff and no checkbox.
      await selectMethod(tester, 'Cash');
      expect(find.text('Select a UPI app'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isTrue);

      // Back to UPI: discovery re-runs, confirmation starts over.
      await selectMethod(tester, 'UPI');
      expect(find.text('Select a UPI app'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isFalse);

      // An amount edit after a launch also restarts confirmation.
      await selectUpiApp(tester, 'PhonePe');
      await tapVisible(tester, find.text('Open UPI app'));
      resumeApp(tester);
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).first, '500.00');
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('resuming after the sheet closes is safe', (tester) async {
      await pumpSheet(tester);
      await openPaySheet(tester);
      await tapVisible(tester, find.text('Cancel'));
      expect(find.text('Pay Naren'), findsNothing);

      resumeApp(tester);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('cash flow is unchanged', () {
    testWidgets('cash records directly with no UPI UI', (tester) async {
      await pumpSheet(tester);
      await openPaySheet(tester);

      expect(find.text('Select a UPI app'), findsNothing);
      expect(find.text('Open UPI app'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isTrue);

      final before = DateTime.now().toUtc();
      await tapVisible(tester, recordButton());
      final payment = expenses.storedPayablePayments.single;
      expect(payment.paymentMethod, PaymentMethod.cash);
      expect(payment.amountPaise, 100000);
      expect(payment.paidAt.isUtc, isTrue);
      expect(payment.paidAt.isBefore(before), isFalse);
      expect(tester.takeException(), isNull);
    });
  });

  group('launcher seam', () {
    testWidgets('discovery failure shows an error and keeps manual record', (
      tester,
    ) async {
      upi.listError = const UpiLauncherException('Dart side broke.');
      await pumpSheet(tester);
      await openPaySheet(tester);
      await selectMethod(tester, 'UPI');

      expect(find.textContaining('Dart side broke.'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(recordEnabled(tester), isTrue);
      expect(tester.takeException(), isNull);
    });

    test('method-channel mapping skips malformed entries', () async {
      const channel = MethodChannel('brewflow_pos/upi-test-seam');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'getInstalledUpiApps');
            return [
              {'packageName': 'com.phonepe.app', 'displayName': 'PhonePe'},
              {'packageName': '', 'displayName': 'Nameless'},
              {'packageName': 'net.one97.paytm'},
              'not-a-map',
              null,
            ];
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final launcher = MethodChannelUpiAppLauncher(channel: channel);
      final apps = await launcher.installedUpiApps();
      expect(apps.map((a) => a.packageName).toList(), ['com.phonepe.app']);
    });

    test('method-channel launch errors surface as launcher failures', () async {
      const channel = MethodChannel('brewflow_pos/upi-test-launch');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'launchUpiApp');
            expect((call.arguments as Map)['packageName'], 'com.phonepe.app');
            throw PlatformException(code: 'APP_NOT_FOUND', message: 'Gone.');
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final launcher = MethodChannelUpiAppLauncher(channel: channel);
      await expectLater(
        launcher.launchUpiApp(
          packageName: 'com.phonepe.app',
          amountRupees: '100.00',
        ),
        throwsA(
          isA<UpiLauncherException>().having(
            (e) => e.message,
            'message',
            'Gone.',
          ),
        ),
      );
    });
  });
}
