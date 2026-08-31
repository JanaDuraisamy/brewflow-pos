import 'dart:convert';

import 'package:brewflow_pos/core/storage/app_storage.dart';
import 'package:brewflow_pos/core/storage/preferences_storage.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Quick Expense Templates
///
/// Pinned one-tap presets for recurring daily purchases (milk, sugar, …).
/// A template stores only what the counter re-uses every day: name, category
/// and an optional last/default amount. The DAILY EXPENSE ITSELF is still a
/// normal [Expense] created through the existing repository every time —
/// templates never hold money and never replace the ledger.
///
/// Storage: device-local preferences JSON (the app's established key-value
/// layer). Deliberately NOT part of cloud master-data sync in this phase:
/// templates are per-device counter conveniences, not financial records.
/// Losing them on reinstall costs nothing; re-pinning takes seconds.
/// ---------------------------------------------------------------------------

final class QuickExpenseTemplate {
  const QuickExpenseTemplate({
    required this.name,
    required this.category,
    this.defaultAmountPaise,
  });

  final String name;
  final ExpenseCategory category;

  /// Last amount used with this template, offered pre-filled next time.
  /// Optional and freely editable at save time.
  final int? defaultAmountPaise;

  /// Stable identity: same item name in the same category is ONE template.
  String get id => '${category.dbValue}:${name.toLowerCase()}';

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'category': category.dbValue,
    if (defaultAmountPaise != null) 'amount': defaultAmountPaise,
  };

  static QuickExpenseTemplate fromJson(Map<String, dynamic> json) =>
      QuickExpenseTemplate(
        name: json['name'] as String,
        category:
            ExpenseCategory.fromDbValue(json['category'] as String) ??
            ExpenseCategory.misc,
        defaultAmountPaise: json['amount'] as int?,
      );
}

/// Persistence boundary for pinned templates; injectable for tests.
final class QuickExpenseStore {
  QuickExpenseStore({PreferencesStorage? storage})
    : _storage = storage ?? AppStorage.preferences;

  static const String _key = 'quick_expense_templates_v1';

  final PreferencesStorage _storage;

  Future<List<QuickExpenseTemplate>> load() async {
    final raw = await _storage.readString(_key);
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List)
          .whereType<Map<String, dynamic>>()
          .map(QuickExpenseTemplate.fromJson)
          .toList();
      // Defensive dedupe by identity; oldest pin wins position.
      final seen = <String>{};
      return [
        for (final template in list)
          if (seen.add(template.id)) template,
      ];
    } on FormatException {
      // Corrupted payload: start clean rather than crash the page.
      return const [];
    }
  }

  /// Saves [templates] replacing the stored set.
  Future<void> save(List<QuickExpenseTemplate> templates) => _storage
      .writeString(_key, jsonEncode([for (final t in templates) t.toJson()]));
}
