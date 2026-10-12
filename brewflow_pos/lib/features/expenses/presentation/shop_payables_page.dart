import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/expenses/data/upi_app_launcher.dart';
import 'package:brewflow_pos/features/expenses/domain/expenses_models.dart';
import 'package:brewflow_pos/features/expenses/domain/shop_payables_models.dart';
import 'package:brewflow_pos/features/expenses/presentation/expenses_controller.dart';
import 'package:brewflow_pos/features/orders/presentation/orders_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          // The card is a summary: tapping its header opens the underlying
          // unpaid expenses of exactly this (shop, payee) row.
          InkWell(
            borderRadius: AppBorderRadius.md,
            onTap: () => _showExpenses(context, ref),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
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
                ],
              ),
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

  /// Opens the expense-detail drill-down: the underlying unpaid expenses of
  /// exactly this (shop, payee) row, so the summary card never has to carry
  /// them and same-name payees in two businesses never mix.
  Future<void> _showExpenses(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => _PayableExpensesSheet(payable: payable),
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

final class _PayPayableSheetState extends ConsumerState<_PayPayableSheet>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  /// Installed UPI apps; null until discovery finishes for the current UPI
  /// selection. The cache survives amount edits (the device set cannot
  /// change with the amount), but any edit resets the handoff below.
  List<UpiAppInfo>? _upiApps;
  bool _upiAppsLoading = false;
  String? _upiAppsError;
  String? _selectedUpiPackage;
  bool _launching = false;
  String? _upiLaunchError;

  /// Launch → return → confirm lifecycle. In-memory only: a killed process
  /// loses all of it, so a stale confirmation can never be restored.
  bool _upiLaunched = false;
  bool _upiReturned = false;
  bool _upiConfirmed = false;

  /// A failed launch falls back to the existing manual record workflow
  /// instead of blocking the payment.
  bool _upiManualFallback = false;

  /// Whether recording a UPI payment needs the manual checkbox: only when
  /// real apps were discovered and no fallback is active. An empty app list
  /// (or a failed launch) keeps the existing direct record flow.
  bool get _upiNeedsConfirmation =>
      _method == PaymentMethod.upi &&
      !_upiManualFallback &&
      _upiApps != null &&
      _upiApps!.isNotEmpty;

  /// The checkbox appears only after a launch followed by a resume — never
  /// on UPI selection alone, and never as proof of payment.
  bool get _upiShowCheckbox =>
      _upiNeedsConfirmation && _upiLaunched && _upiReturned;

  String? get _selectedUpiName {
    final apps = _upiApps;
    final package = _selectedUpiPackage;
    if (apps == null || package == null) return null;
    for (final app in apps) {
      if (app.packageName == package) return app.displayName;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    // Pre-fill the full remaining balance: paying a supplier in full is the
    // common case, and a partial amount is one edit away.
    _amount = TextEditingController(
      text: Money.paiseToRupeesInput(widget.payable.remainingPaise),
    );
    _amount.addListener(_onAmountChanged);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amount.removeListener(_onAmountChanged);
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The ONLY thing a resume proves is that the owner came back. It never
    // implies the payment succeeded — it merely reveals the checkbox so the
    // owner can attest manually. Repeated resumes change nothing further.
    if (state == AppLifecycleState.resumed &&
        _upiLaunched &&
        !_upiReturned &&
        mounted) {
      setState(() => _upiReturned = true);
    }
  }

  void _onAmountChanged() {
    // A new amount invalidates any in-flight UPI handoff (the launched app
    // saw the old amount): confirmation starts over. The discovered app
    // list is device state and stays cached.
    if (_upiLaunched ||
        _upiReturned ||
        _upiConfirmed ||
        _upiManualFallback ||
        _upiLaunchError != null) {
      setState(() {
        _upiLaunched = false;
        _upiReturned = false;
        _upiConfirmed = false;
        _upiManualFallback = false;
        _upiLaunchError = null;
      });
    }
  }

  void _onMethodChanged(PaymentMethod? value) {
    if (value == null || value == _method) return;
    setState(() {
      _method = value;
      _upiApps = null;
      _upiAppsLoading = false;
      _upiAppsError = null;
      _selectedUpiPackage = null;
      _launching = false;
      _upiLaunchError = null;
      _upiLaunched = false;
      _upiReturned = false;
      _upiConfirmed = false;
      _upiManualFallback = false;
    });
    if (value == PaymentMethod.upi) _loadUpiApps();
  }

  Future<void> _loadUpiApps() async {
    setState(() {
      _upiAppsLoading = true;
      _upiAppsError = null;
    });
    try {
      final apps = await ref.read(upiAppLauncherProvider).installedUpiApps();
      if (!mounted || _method != PaymentMethod.upi) return;
      setState(() {
        _upiAppsLoading = false;
        _upiApps = apps;
      });
    } on UpiLauncherException catch (error) {
      if (!mounted || _method != PaymentMethod.upi) return;
      setState(() {
        _upiAppsLoading = false;
        _upiAppsError = error.message;
        _upiApps = const [];
      });
    }
  }

  Future<void> _launchUpiApp() async {
    if (!_formKey.currentState!.validate()) return;
    final package = _selectedUpiPackage;
    if (package == null || _launching || _saving) return;
    setState(() {
      _launching = true;
      _upiLaunchError = null;
    });
    try {
      final note = _note.text.trim();
      await ref
          .read(upiAppLauncherProvider)
          .launchUpiApp(
            packageName: package,
            amountRupees: _amount.text.trim(),
            note: note.isEmpty ? widget.payable.payeeName : note,
          );
      if (!mounted) return;
      setState(() {
        _launching = false;
        // A fresh launch supersedes any earlier return or fallback: the
        // owner must come back again and confirm again.
        _upiLaunched = true;
        _upiReturned = false;
        _upiConfirmed = false;
        _upiManualFallback = false;
      });
    } on UpiLauncherException catch (error) {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _upiLaunchError = error.message;
        // The app could not be opened, so no return can follow: keep the
        // existing manual record workflow instead of blocking.
        _upiManualFallback = true;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _launching = false;
        _upiLaunchError = 'Could not open the selected UPI app.';
        _upiManualFallback = true;
      });
    }
  }

  void _onUpiAppChanged(String? package) {
    setState(() {
      _selectedUpiPackage = package;
      // A different app means a different handoff: start over.
      _upiLaunched = false;
      _upiReturned = false;
      _upiConfirmed = false;
      _upiManualFallback = false;
      _upiLaunchError = null;
    });
  }

  bool get _canLaunch => _selectedUpiPackage != null && !_launching && !_saving;

  /// Record is available immediately for Cash (and for the UPI manual
  /// fallback); a launched UPI handoff additionally requires the owner's
  /// manual confirmation.
  bool get _recordEnabled {
    if (_saving) return false;
    if (_upiNeedsConfirmation && !_upiConfirmed) return false;
    return true;
  }

  Widget _buildUpiSection() {
    final textTheme = Theme.of(context).textTheme;
    if (_upiAppsLoading) {
      return Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Finding UPI apps…',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    if (_upiAppsError != null) {
      return Text(
        '${_upiAppsError!} Pay in your UPI app, then record the payment '
        'here manually.',
        style: textTheme.bodySmall?.copyWith(color: AppColors.error),
      );
    }
    final apps = _upiApps ?? const <UpiAppInfo>[];
    if (apps.isEmpty) {
      return Text(
        'No UPI apps found on this device. Pay in your UPI app, then record '
        'the payment here manually.',
        style: textTheme.bodySmall?.copyWith(
          color: context.appColors.textSecondary,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _selectedUpiPackage,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'UPI app *',
            border: OutlineInputBorder(),
          ),
          hint: const Text('Select a UPI app'),
          items: [
            for (final app in apps)
              DropdownMenuItem(
                value: app.packageName,
                child: Text(app.displayName),
              ),
          ],
          onChanged: _saving ? null : _onUpiAppChanged,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _canLaunch ? _launchUpiApp : null,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: Text(_launching ? 'Opening…' : 'Open UPI app'),
          ),
        ),
        if (_upiLaunchError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_upiLaunchError!} You can still record the payment manually '
            'after paying.',
            style: textTheme.bodySmall?.copyWith(color: AppColors.error),
          ),
        ],
        if (_upiLaunched && !_upiReturned) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: context.appColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Opened ${_selectedUpiName ?? 'the UPI app'}. Complete the '
                  'payment there, then return to BrewFlow to confirm and '
                  'record it here.',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (_upiShowCheckbox) ...[
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'I confirm I completed this payment in the UPI app. BrewFlow '
              'has not verified the payment.',
              style: textTheme.bodySmall?.copyWith(
                color: context.appColors.textPrimary,
              ),
            ),
            value: _upiConfirmed,
            onChanged: _saving
                ? null
                : (value) => setState(() => _upiConfirmed = value ?? false),
          ),
        ],
      ],
    );
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
        // Scrollable (not just inset-padded): on a short landscape viewport
        // with the keyboard open the Record Payment button stays reachable.
        child: SingleChildScrollView(
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
                // Fill the sheet width like every other form dropdown.
                isExpanded: true,
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
                onChanged: _saving ? null : _onMethodChanged,
              ),
              if (_method == PaymentMethod.upi) ...[
                const SizedBox(height: AppSpacing.lg),
                _buildUpiSection(),
              ],
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
                    // Navigator pop (not the router): this sheet is a plain
                    // modal route and must close without a GoRouter ancestor.
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _recordEnabled ? _submit : null,
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

/// Expense-detail drill-down for one shop-payable card: every underlying
/// unpaid expense of exactly one (shop, payee) row, oldest due first, with
/// its date, amount, status and note, plus the aggregate the card summarizes.
///
/// Phone-first: single-column, scrollable, no fixed widths — safe at
/// 360–480dp. Tablet behavior intentionally unchanged.
final class _PayableExpensesSheet extends ConsumerWidget {
  const _PayableExpensesSheet({required this.payable});

  final ShopPayable payable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final detail = ref.watch(
      payableDetailProvider((
        payeeKey: payable.payeeKey,
        shopId: payable.shopId,
      )),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: AppInsets.screen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${payable.payeeName} · Expenses',
                      style: textTheme.titleMedium?.copyWith(
                        color: context.appColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      payable.isSettled
                          ? 'Fully paid'
                          : '${Money.formatPaise(payable.remainingPaise)} outstanding',
                      style: textTheme.bodySmall?.copyWith(
                        color: context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: detail.when(
                  loading: () =>
                      const LoadingState(message: 'Loading expenses…'),
                  error: (error, _) => ErrorState(
                    message: expensesErrorMessage(error),
                    onRetry: () => ref.invalidate(
                      payableDetailProvider((
                        payeeKey: payable.payeeKey,
                        shopId: payable.shopId,
                      )),
                    ),
                  ),
                  data: (rows) {
                    if (rows.isEmpty) {
                      return Padding(
                        padding: AppInsets.screen,
                        child: Text(
                          'No unpaid expenses for this payee.',
                          style: textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          ),
                        ),
                      );
                    }
                    final total = rows.fold<int>(
                      0,
                      (sum, expense) => sum + expense.amountPaise,
                    );
                    return ListView.separated(
                      controller: scrollController,
                      padding: AppInsets.screen,
                      itemCount: rows.length + 1,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: Text(
                              '${payable.payeeName} · Expenses (${rows.length}) · Total ${Money.formatPaise(total)}',
                              style: textTheme.bodySmall?.copyWith(
                                color: context.appColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }
                        return _PayableExpenseRow(expense: rows[index - 1]);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One underlying unpaid expense: name and amount on the first line, the due
/// date with its unpaid status on the second, and the recorded note when the
/// expense carries one.
final class _PayableExpenseRow extends StatelessWidget {
  const _PayableExpenseRow({required this.expense});

  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    expense.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  Money.formatPaise(expense.amountPaise),
                  style: textTheme.bodyMedium?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatDate(expense.expenseDate),
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'Unpaid',
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (expense.note != null) ...[
              const SizedBox(height: 2),
              Text(
                expense.note!,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
