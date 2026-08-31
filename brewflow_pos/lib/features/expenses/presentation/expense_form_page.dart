import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Expense Form Page
///
/// Create or edit an expense. The name and amount are required (amount > 0,
/// entered in rupees and converted to exact paise), category and payment
/// method come from fixed choices, the expense date is picked in local time,
/// and a blank note is never stored (NULL). Pushed from the expenses page,
/// so it carries its own scaffold.
/// ---------------------------------------------------------------------------

final class ExpenseFormPage extends ConsumerStatefulWidget {
  const ExpenseFormPage({super.key, this.expense});

  /// The expense being edited; null when creating a new one.
  final Expense? expense;

  @override
  ConsumerState<ExpenseFormPage> createState() => ExpenseFormPageState();
}

final class ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.expense?.name ?? '',
  );

  late final TextEditingController _amount = TextEditingController(
    text: widget.expense == null
        ? ''
        : Money.paiseToRupeesInput(widget.expense!.amountPaise),
  );

  late final TextEditingController _note = TextEditingController(
    text: widget.expense?.note ?? '',
  );

  late ExpenseCategory? _category = widget.expense?.category;
  late PaymentMethod? _paymentMethod = widget.expense?.paymentMethod;
  late ExpensePaymentStatus _paymentStatus =
      widget.expense?.paymentStatus ?? ExpensePaymentStatus.paid;
  late DateTime? _expenseDate = widget.expense?.expenseDate;
  late bool _isActive = widget.expense?.isActive ?? true;
  bool _saving = false;
  bool _dirty = false;

  bool get _editing => widget.expense != null;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() => _dirty = true));
    _amount.addListener(() => setState(() => _dirty = true));
    _note.addListener(() => setState(() => _dirty = true));
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDate: _expenseDate == null
          ? now
          : DateTime(
              _expenseDate!.year,
              _expenseDate!.month,
              _expenseDate!.day,
            ),
    );
    if (picked == null) return;
    // Store the UTC instant at local midnight of the picked local day.
    setState(
      () => _expenseDate = DateTime(
        picked.year,
        picked.month,
        picked.day,
      ).toUtc(),
    );
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_expenseDate == null) {
      return;
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(expensesProvider.notifier);
      final note = _note.text.trim();
      if (_editing) {
        await controller.updateExpense(
          id: widget.expense!.id,
          name: _name.text.trim(),
          amountPaise: Money.parseRupeesToPaise(_amount.text)!,
          category: _category!,
          paymentMethod: _paymentMethod!,
          paymentStatus: _paymentStatus,
          expenseDate: _expenseDate!,
          note: note.isEmpty ? null : note,
          isActive: _isActive,
        );
      } else {
        await controller.create(
          name: _name.text.trim(),
          amountPaise: Money.parseRupeesToPaise(_amount.text)!,
          category: _category!,
          paymentMethod: _paymentMethod!,
          paymentStatus: _paymentStatus,
          expenseDate: _expenseDate!,
          note: note.isEmpty ? null : note,
          isActive: _isActive,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Expense updated.' : 'Expense added.'),
        ),
      );
      if (mounted) {
        context.pop();
      }
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(expensesErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('You have unsaved changes. Discard them?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit Expense' : 'New Expense')),
        body: SingleChildScrollView(
          padding: AppInsets.screen,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _editing
                      ? 'Update the expense details below.'
                      : 'Fill in the expense details below.',
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Expense name *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.trim().isEmpty)
                      ? 'Expense name is required.'
                      : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Amount (₹) *',
                    hintText: 'e.g. 149.50',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final paise = Money.parseRupeesToPaise(value ?? '');
                    if (paise == null) {
                      return 'Enter a valid amount (e.g. 149.50)';
                    }
                    if (paise <= 0) {
                      return 'Amount must be greater than zero.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<ExpenseCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select a category'),
                  items: [
                    for (final category in ExpenseCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _category = value;
                    _dirty = true;
                  }),
                  validator: (value) =>
                      value == null ? 'Select a category.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method *',
                    border: OutlineInputBorder(),
                  ),
                  hint: const Text('Select a payment method'),
                  items: [
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem(
                        value: method,
                        child: Text(paymentMethodLabel(method)),
                      ),
                  ],
                  onChanged: (value) => setState(() {
                    _paymentMethod = value;
                    _dirty = true;
                  }),
                  validator: (value) =>
                      value == null ? 'Select a payment method.' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<ExpensePaymentStatus>(
                  initialValue: _paymentStatus,
                  decoration: const InputDecoration(
                    labelText: 'Payment status *',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final status in ExpensePaymentStatus.values)
                      DropdownMenuItem(
                        value: status,
                        child: Text(status.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _paymentStatus = value;
                        _dirty = true;
                      });
                    }
                  },
                ),
                SizedBox(height: AppSpacing.lg),
                InkWell(
                  onTap: _saving ? null : _pickDate,
                  borderRadius: AppBorderRadius.md,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Expense date *',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: context.appColors.textSecondary,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            _expenseDate == null
                                ? 'Select a date'
                                : formatDate(_expenseDate!),
                            style: textTheme.bodyMedium?.copyWith(
                              color: _expenseDate == null
                                  ? context.appColors.textDisabled
                                  : context.appColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_expenseDate == null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Expense date is required.',
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _note,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Optional',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SwitchListTile(
                  contentPadding: AppInsets.zero,
                  title: const Text('Active expense'),
                  subtitle: const Text(
                    'Hides the expense from active lists when off.',
                  ),
                  value: _isActive,
                  onChanged: (value) => setState(() {
                    _isActive = value;
                    _dirty = true;
                  }),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => context.pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_editing ? 'Save Changes' : 'Save Expense'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
