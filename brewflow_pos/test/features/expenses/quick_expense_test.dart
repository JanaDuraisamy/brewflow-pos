import 'package:brewflow_pos/features/expenses/data/quick_expense_store.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_preferences_storage.dart';

/// ---------------------------------------------------------------------------
/// P0 FIX 8 — Quick Expenses templates.
///
/// Templates are device-local pins; the DAILY EXPENSE itself always flows
/// through the existing ExpensesRepository.create path (covered by the
/// expenses suite). Here we verify pin/unpin persistence, identity dedupe,
/// default-amount refresh and controller round-trips.
/// ---------------------------------------------------------------------------

void main() {
  late FakePreferencesStorage storage;
  late ProviderContainer container;

  setUp(() {
    storage = FakePreferencesStorage();
    container = ProviderContainer(
      overrides: [
        quickExpenseStoreProvider.overrideWithValue(
          QuickExpenseStore(storage: storage),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  QuickExpensesController controller() =>
      container.read(quickExpensesProvider.notifier);

  Future<List<QuickExpenseTemplate>> templates() async {
    await container.read(quickExpensesProvider.future);
    return container.read(quickExpensesProvider).value ?? const [];
  }

  test('pins persist to preferences and reload', () async {
    await controller().pin(
      const QuickExpenseTemplate(
        name: 'Milk',
        category: ExpenseCategory.supplies,
        defaultAmountPaise: 50000,
      ),
    );
    final afterPin = await templates();
    expect(afterPin.single.name, 'Milk');
    expect(afterPin.single.category, ExpenseCategory.supplies);
    expect(afterPin.single.defaultAmountPaise, 50000);

    // Fresh store over the SAME storage simulates an app restart.
    final reloaded = await QuickExpenseStore(storage: storage).load();
    expect(reloaded.single.id, afterPin.single.id);
  });

  test('identity is (category, lowercase name) — no duplicate pins', () async {
    await controller().pin(
      const QuickExpenseTemplate(
        name: 'Milk',
        category: ExpenseCategory.supplies,
        defaultAmountPaise: 50000,
      ),
    );
    // Same item, different casing/amount → refresh, not a second row.
    await controller().pin(
      const QuickExpenseTemplate(
        name: 'milk',
        category: ExpenseCategory.supplies,
        defaultAmountPaise: 55000,
      ),
    );
    // Same name, different category IS a distinct template.
    await controller().pin(
      const QuickExpenseTemplate(name: 'Milk', category: ExpenseCategory.misc),
    );

    final all = await templates();
    expect(all.length, 2);
    expect(
      all
          .firstWhere((t) => t.category == ExpenseCategory.supplies)
          .defaultAmountPaise,
      55000,
      reason: 're-pin refreshes the default amount',
    );
  });

  test('unpin removes only the targeted template', () async {
    await controller().pin(
      const QuickExpenseTemplate(
        name: 'Milk',
        category: ExpenseCategory.supplies,
      ),
    );
    await controller().pin(
      const QuickExpenseTemplate(
        name: 'Sugar',
        category: ExpenseCategory.supplies,
      ),
    );
    await controller().unpin(
      const QuickExpenseTemplate(
        name: 'MILK',
        category: ExpenseCategory.supplies,
      ),
    );

    final names = (await templates()).map((t) => t.name);
    expect(names, ['Sugar']);
  });

  test('unpin on an unknown template is a no-op', () async {
    await controller().unpin(
      const QuickExpenseTemplate(name: 'Ghost', category: ExpenseCategory.misc),
    );
    expect(await templates(), isEmpty);
  });
}
