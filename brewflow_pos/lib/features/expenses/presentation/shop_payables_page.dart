import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Shop Payables Page
///
/// The detail behind the Expenses "Shop Payable" card. One row per payee, with
/// the outstanding balance derived from unpaid expenses minus payments, and an
/// owner action to record a partial payment against the selected payee.
///
/// Payments are append-only and never touch the original expense rows, so this
/// screen only ever adds a record; the balance moves because it is recomputed,
/// not because a row was edited.
/// ---------------------------------------------------------------------------
final class ShopPayablesPage extends ConsumerWidget {
  const ShopPayablesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payables = ref.watch(shopPayablesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Shop Payables')),
      body: payables.when(
        loading: () => const LoadingState(message: 'Loading payables…'),
        error: (error, _) => ErrorState(
          message: expensesErrorMessage(error),
          onRetry: () => ref.invalidate(shopPayablesProvider),
        ),
        data: (rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.check_circle_outline,
              title: 'Nothing payable',
              message: 'Unpaid expenses will show up here, grouped by payee.',
            );
          }
          return ListView.separated(
            padding: AppInsets.screen,
            itemCount: rows.length,
            separatorBuilder: (context, index) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PayableCard(payable: rows[index]),
          );
        },
      ),
    );
  }
}

/// One payee: total owed, what has been paid, what is left, and — for the
/// owner — the button that records a payment.
///
/// A fully-settled payee deliberately STAYS in this list. Its balance is zero
/// and the Pay action is disabled, but dropping the row would make its payment
/// history unreachable, which is the only remaining thing a user wants from a
/// payee they have finished paying off.
final class _PayableCard extends ConsumerWidget {
  const _PayableCard({required this.payable});

  final ShopPayable payable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    // Paying a payable moves money out of the shop, so the action is
    // owner-only — mirroring the `requireOwner` gate in the controller and the
    // owner-only RLS write policy. Staff still see the balance and the history.
    final isOwner = ref.watch(userProfileProvider).value?.isOwner ?? false;
    final isSettled = payable.remainingPaise <= 0;
    return AppCard(
      padding: AppInsets.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  payable.payeeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                isSettled
                    ? 'Settled'
                    : Money.formatPaise(payable.remainingPaise),
                style: textTheme.titleMedium?.copyWith(
                  color: isSettled
                      ? context.appColors.textSecondary
                      : AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _subtitle(),
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showHistory(context, ref),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('History'),
                ),
              ),
              // A staff member has no legitimate payment to make, and a settled
              // payee has nothing left to pay — so in neither case is a dead
              // "Pay" button the honest thing to render.
              if (isOwner && !isSettled) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _showPaySheet(context, ref),
                    icon: const Icon(Icons.payments_outlined, size: 18),
                    label: const Text('Pay'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Explains the balance in one line: what it covers, what was already paid
  /// and how long it has been outstanding.
  String _subtitle() {
    final count = payable.expenseCount;
    final noun = count == 1 ? 'expense' : 'expenses';
    final oldest = DateFormat(
      'd MMM yyyy',
    ).format(payable.oldestExpenseDate.toLocal());
    if (payable.remainingPaise <= 0) {
      return '$count $noun · since $oldest · fully paid';
    }
    if (payable.paidPaise == 0) {
      return '$count $noun · since $oldest · ${Money.formatPaise(payable.totalPaise)} unpaid';
    }
    return '$count $noun · since $oldest · ${Money.formatPaise(payable.paidPaise)} of ${Money.formatPaise(payable.totalPaise)} paid';
  }

  Future<void> _showPaySheet(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PayPayableSheet(payable: payable),
    );
  }

  Future<void> _showHistory(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _PaymentHistorySheet(payable: payable),
    );
  }
}

/// Owner-only payment entry. The remaining balance is the ceiling: the amount
/// field refuses more than is owed, and the repository re-checks the same
/// number before writing.
final class _PayPayableSheet extends ConsumerStatefulWidget {
  const _PayPayableSheet({required this.payable});

  final ShopPayable payable;

  @override
  ConsumerState<_PayPayableSheet> createState() => _PayPayableSheetState();
}

final class _PayPayableSheetState extends ConsumerState<_PayPayableSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill the full remaining balance: paying a supplier in full is the
    // common case, and a partial amount is one edit away.
    _amount = TextEditingController(
      text: Money.paiseToRupeesInput(widget.payable.remainingPaise),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(expensesProvider.notifier)
          .payPayable(
            payeeName: widget.payable.payeeName,
            amountPaise: Money.parseRupeesToPaise(_amount.text)!,
            paymentMethod: _method,
            paidAt: DateTime.now().toUtc(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Paid ${Money.formatPaise(Money.parseRupeesToPaise(_amount.text)!)} '
            'to ${widget.payable.payeeName}.',
          ),
        ),
      );
      navigator.pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(expensesErrorMessage(error))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final remaining = widget.payable.remainingPaise;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pay ${widget.payable.payeeName}',
              style: textTheme.titleMedium?.copyWith(
                color: context.appColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${Money.formatPaise(remaining)} outstanding',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount (₹) *',
                hintText: 'e.g. 1000.00',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                final paise = Money.parseRupeesToPaise(value ?? '');
                if (paise == null) {
                  return 'Enter a valid amount (e.g. 1000.00)';
                }
                if (paise <= 0) {
                  return 'Amount must be greater than zero.';
                }
                if (paise > remaining) {
                  return 'Cannot exceed ${Money.formatPaise(remaining)}.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Payment method *',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final method in PaymentMethod.values)
                  DropdownMenuItem(
                    value: method,
                    child: Text(paymentMethodLabel(method)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _method = value);
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note',
                hintText: 'Optional',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
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
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Record Payment'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Every payment recorded against one payee, newest first, so the owner can
/// reconcile what has already been handed over.
final class _PaymentHistorySheet extends ConsumerWidget {
  const _PaymentHistorySheet({required this.payable});

  final ShopPayable payable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final payments = ref.watch(payablePaymentsProvider(payable.payeeName));
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${payable.payeeName} · Payment history',
            style: textTheme.titleMedium?.copyWith(
              color: context.appColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          payments.when(
            loading: () => const LoadingState(message: 'Loading payments…'),
            error: (error, _) => ErrorState(
              message: expensesErrorMessage(error),
              onRetry: () =>
                  ref.invalidate(payablePaymentsProvider(payable.payeeName)),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return Text(
                  'No payments recorded yet.',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                );
              }
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) const Divider(height: AppSpacing.md),
                    _PaymentRow(payment: rows[i]),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

final class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final ExpensePayment payment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Money.formatPaise(payment.amountPaise),
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatDate(payment.paidAt)} · ${paymentMethodLabel(payment.paymentMethod)}',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              if (payment.note != null) ...[
                const SizedBox(height: 2),
                Text(
                  payment.note!,
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
