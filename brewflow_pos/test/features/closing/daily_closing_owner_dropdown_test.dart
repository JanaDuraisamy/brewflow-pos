import 'package:brewflow_pos/core/database/app_database.dart' hide Expense;
import 'package:brewflow_pos/core/theme/app_theme.dart';
import 'package:brewflow_pos/features/closing/data/drift_daily_closing_repository.dart';
import 'package:brewflow_pos/features/closing/domain/daily_closing_models.dart';
import 'package:brewflow_pos/features/closing/presentation/closing_controller.dart';
import 'package:brewflow_pos/features/closing/presentation/daily_closing_page.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_expenses_repository.dart';
import '../../helpers/fake_orders_repository.dart';
import '../../helpers/fake_staff_repository.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Daily Closing "Taken out by" dropdown
///
/// Locks the owner field contract: the four fixed owners are offered in a
/// fixed order, free text is impossible, the selection round-trips through
/// the existing nullable String column, it is required exactly when cash was
/// taken out, and the control survives narrow phones, both themes and a 1.15
/// system text scale.
/// ---------------------------------------------------------------------------

/// The fixed owner options, in the order the menu must present them.
const List<String> owners = ['Sudharsan', 'Narendar', 'Sathish', 'Jana'];

void main() {
  late AppDatabase database;
  late DriftDailyClosingRepository closings;
  late FakeOrdersRepository orders;
  late FakeExpensesRepository expenses;

  DateTime businessDate() {
    final local = DateTime.now();
    return DateTime.utc(local.year, local.month, local.day);
  }

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    closings = DriftDailyClosingRepository(database);
    orders = FakeOrdersRepository();
    expenses = FakeExpensesRepository();
    // Saving resolves a writable shop id through the business switcher, and the
    // closing row carries a foreign key to `shops`. FakeStaffRepository hands
    // back `shop-1`, so that is the row that must exist.
    await database
        .into(database.shops)
        .insert(ShopsCompanion.insert(id: const Value('shop-1'), name: 'Cafe'));
  });

  tearDown(() async {
    await database.close();
  });

  Future<List<DailyClosingRecord>> savedRecords() {
    final day = businessDate();
    return closings.closingsFor(
      startDate: day,
      endExclusiveDate: day.add(const Duration(days: 1)),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester, {
    ThemeData? theme,
    Size size = const Size(420, 2400),
    double textScale = 1.0,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dailyClosingRepositoryProvider.overrideWithValue(closings),
          ordersRepositoryProvider.overrideWithValue(orders),
          expensesRepositoryProvider.overrideWithValue(expenses),
          staffRepositoryProvider.overrideWithValue(FakeStaffRepository()),
          // Unscoped read-all, same as the autofill regression.
          closingShopScopeProvider.overrideWithValue(
            const AsyncValue.data(null),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.light,
          home: const DailyClosingPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder ownerDropdown() => find.byType(DropdownButtonFormField<String>);

  /// Amount/text fields render in form order: cash, UPI, sales, expenses,
  /// cash in box, cash taken out, tallied by, note.
  String fieldText(WidgetTester tester, int index) =>
      tester
          .widget<TextField>(find.byType(TextField).at(index))
          .controller
          ?.text ??
      '';

  const cashTakenOutIndex = 5;

  Future<void> openMenu(WidgetTester tester) async {
    await tester.ensureVisible(ownerDropdown());
    await tester.pumpAndSettle();
    await tester.tap(ownerDropdown());
    await tester.pumpAndSettle();
  }

  /// Menu labels in the exact order the overlay presents them.
  List<String> menuLabels(WidgetTester tester) => tester
      .widgetList<DropdownMenuItem<String>>(
        find.byType(DropdownMenuItem<String>),
      )
      .map((item) => (item.child as Text).data!)
      .toList();

  Future<void> selectOwner(WidgetTester tester, String owner) async {
    await openMenu(tester);
    await tester.tap(find.text(owner).last);
    await tester.pumpAndSettle();
  }

  /// The owner shown in the collapsed control, read from the widget tree
  /// rather than from page state.
  String? selectedOwner(WidgetTester tester) {
    final items = tester.widgetList<DropdownMenuItem<String>>(
      find.byType(DropdownMenuItem<String>),
    );
    if (items.isEmpty) return null;
    return (items.first.child as Text).data;
  }

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Save Closing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Closing'));
    await tester.pumpAndSettle();
  }

  group('options', () {
    testWidgets('offers exactly the four owners in a fixed order', (
      tester,
    ) async {
      await pumpPage(tester);
      expect(ownerDropdown(), findsOneWidget);

      await openMenu(tester);
      expect(menuLabels(tester), owners);
      expect(tester.takeException(), isNull);
    });

    testWidgets('free text is no longer possible', (tester) async {
      await pumpPage(tester);

      // The old free-text label is gone and the field is a dropdown.
      expect(find.text('Taken out by (optional)'), findsNothing);
      expect(ownerDropdown(), findsOneWidget);

      // No TextField anywhere carries the owner label.
      final ownerTextFields = tester
          .widgetList<TextField>(find.byType(TextField))
          .where(
            (field) =>
                field.decoration?.labelText?.contains('Taken out by') ?? false,
          );
      expect(ownerTextFields, isEmpty);

      // The dropdown adds no hidden TextField of its own.
      expect(find.byType(TextField), findsNWidgets(8));
    });
  });

  group('persistence', () {
    for (final owner in owners) {
      testWidgets('selecting $owner persists it as takenOutBy', (tester) async {
        await pumpPage(tester);
        await tester.enterText(
          find.byType(TextField).at(cashTakenOutIndex),
          '1000',
        );
        await tester.pumpAndSettle();
        // The dropdown contributes no TextField, so the amount fields keep the
        // render order the autofill regression indexes by position.
        expect(fieldText(tester, cashTakenOutIndex), '1000');

        await selectOwner(tester, owner);
        expect(selectedOwner(tester), owner);

        await tapSave(tester);
        expect(tester.takeException(), isNull);

        final saved = await savedRecords();
        expect(saved, hasLength(1));
        expect(saved.single.takenOutBy, owner);
        expect(saved.single.cashTakenOutPaise, 100000);
      });
    }

    testWidgets('reopening a saved closing preselects its owner', (
      tester,
    ) async {
      await closings.recordDailyClosing(
        businessDate: businessDate(),
        totalCashPaise: 100000,
        totalUpiPaise: 0,
        totalSalesPaise: 100000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 0,
        cashTakenOutPaise: 250000,
        takenOutBy: 'Sathish',
      );

      await pumpPage(tester);
      expect(selectedOwner(tester), 'Sathish');
    });

    testWidgets('a saved closing without an owner starts unselected', (
      tester,
    ) async {
      await closings.recordDailyClosing(
        businessDate: businessDate(),
        totalCashPaise: 100000,
        totalUpiPaise: 0,
        totalSalesPaise: 100000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 0,
        cashTakenOutPaise: 0,
      );

      await pumpPage(tester);
      expect(selectedOwner(tester), isNull);
    });

    testWidgets('an unknown saved owner never becomes an option', (
      tester,
    ) async {
      await closings.recordDailyClosing(
        businessDate: businessDate(),
        totalCashPaise: 100000,
        totalUpiPaise: 0,
        totalSalesPaise: 100000,
        totalExpensePaise: 0,
        cashLeftInBoxPaise: 0,
        cashTakenOutPaise: 250000,
        takenOutBy: 'Ravi',
      );

      await pumpPage(tester);
      expect(selectedOwner(tester), isNull);
      await openMenu(tester);
      expect(menuLabels(tester), owners);
    });
  });

  group('validation', () {
    testWidgets('saves without an owner when no cash was taken out', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.enterText(find.byType(TextField).at(cashTakenOutIndex), '0');
      await tester.pumpAndSettle();

      await tapSave(tester);
      expect(find.text('Select who took the cash out.'), findsNothing);

      final saved = await savedRecords();
      expect(saved, hasLength(1));
      expect(saved.single.takenOutBy, isNull);
      // Clearing the form must not leave the owner selected on the reloaded
      // revision, since that revision stored no owner.
      expect(selectedOwner(tester), isNull);
    });

    testWidgets('blocks the save when cash was taken out without an owner', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.enterText(
        find.byType(TextField).at(cashTakenOutIndex),
        '500',
      );
      await tester.pumpAndSettle();

      await tapSave(tester);

      expect(find.text('Select who took the cash out.'), findsOneWidget);
      expect(await savedRecords(), isEmpty);
    });

    testWidgets('saves once an owner is chosen for taken-out cash', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.enterText(
        find.byType(TextField).at(cashTakenOutIndex),
        '500',
      );
      await tester.pumpAndSettle();

      await tapSave(tester);
      expect(await savedRecords(), isEmpty);

      await selectOwner(tester, 'Narendar');
      await tapSave(tester);

      expect(find.text('Select who took the cash out.'), findsNothing);
      final saved = await savedRecords();
      expect(saved, hasLength(1));
      expect(saved.single.takenOutBy, 'Narendar');
    });

    testWidgets('a successful save persists the owner and reloads the revision', (
      tester,
    ) async {
      await pumpPage(tester);
      await tester.enterText(
        find.byType(TextField).at(cashTakenOutIndex),
        '750',
      );
      await tester.pumpAndSettle();
      await selectOwner(tester, 'Jana');
      expect(selectedOwner(tester), 'Jana');

      await tapSave(tester);

      expect(find.text('Closing saved.'), findsOneWidget);
      expect((await savedRecords()).single.takenOutBy, 'Jana');

      // Saving clears the form, but this page has always re-sourced it from the
      // saved revision straight afterwards — every amount field refills the same
      // way — so the dropdown is preselected with the saved owner instead of
      // being left pinned to a stale selection.
      expect(selectedOwner(tester), 'Jana');
      expect(find.text('Taken out by · Jana'), findsOneWidget);
    });
  });

  group('layout', () {
    final themeCases = <(String, ThemeData)>[
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ];

    for (final (name, theme) in themeCases) {
      testWidgets('renders and opens in the $name theme', (tester) async {
        await pumpPage(tester, theme: theme);
        expect(ownerDropdown(), findsOneWidget);

        await openMenu(tester);
        expect(menuLabels(tester), owners);
        expect(tester.takeException(), isNull);
      });
    }

    for (final width in [360.0, 390.0, 411.0, 480.0]) {
      testWidgets('lays out on a ${width.toInt()}dp phone', (tester) async {
        await pumpPage(tester, size: Size(width, 2400));
        await tester.ensureVisible(ownerDropdown());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        expect(tester.getSize(ownerDropdown()).width, lessThanOrEqualTo(width));

        await openMenu(tester);
        expect(menuLabels(tester), owners);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (name, theme) in themeCases) {
      testWidgets('survives a 1.15 text scale in the $name theme', (
        tester,
      ) async {
        await pumpPage(
          tester,
          theme: theme,
          size: const Size(360, 3200),
          textScale: 1.15,
        );
        await tester.ensureVisible(ownerDropdown());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await openMenu(tester);
        expect(menuLabels(tester), owners);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
