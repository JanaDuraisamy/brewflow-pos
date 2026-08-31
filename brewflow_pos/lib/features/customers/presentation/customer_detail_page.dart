import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/utils/dates.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/features/billing/domain/billing_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_models.dart';
import 'package:brewflow_pos/features/customers/domain/customer_ledger_repository.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/presentation/customer_ledger_controller.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Detail Page
///
/// Full profile view: identity, contact details, activity state and the live
/// financial ledger — outstanding dues, purchase history with derived payment
/// status, payment history and a Record Payment flow. Every figure comes from
/// the customer-ledger repository aggregation; nothing is fabricated or
/// cached client-side. Pushed from the customers page, so it carries its own
/// scaffold.
/// ---------------------------------------------------------------------------

final class CustomerDetailPage extends ConsumerStatefulWidget {
  const CustomerDetailPage({super.key, this.customer});

  final Customer? customer;

  @override
  ConsumerState<CustomerDetailPage> createState() => CustomerDetailPageState();
}

final class CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  bool _busy = false;

  /// The freshest copy of the customer: the route extra may be stale after an
  /// edit, so the live list from the provider wins when available.
  Customer? _liveCustomer() {
    final stored = widget.customer;
    if (stored == null) {
      return null;
    }
    final live = ref.watch(customersProvider).value;
    if (live != null) {
      for (final customer in live) {
        if (customer.id == stored.id) {
          return customer;
        }
      }
    }
    return stored;
  }

  Future<void> _toggleActive(Customer customer) async {
    if (_busy) {
      return;
    }

    final activating = !customer.isActive;
    if (!activating) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Deactivate customer'),
          content: Text(
            'Hide "${customer.name}" from active customer lists? '
            'Existing ledger history is preserved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Deactivate'),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(customersProvider.notifier)
          .setActive(customer.id, !customer.isActive);
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(customersErrorMessage(error))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Opens the Record Payment dialog; on success shows a confirmation.
  Future<void> _recordPayment(
    String customerId,
    CustomerLedgerData ledger,
  ) async {
    final duePurchases = [
      for (final purchase in ledger.purchases)
        if (purchase.duePaise > 0) purchase,
    ];
    if (duePurchases.isEmpty) {
      return;
    }
    final payment = await showDialog<CustomerPayment>(
      context: context,
      builder: (context) => _RecordPaymentDialog(
        customerId: customerId,
        duePurchases: duePurchases,
      ),
    );
    if (payment == null || !mounted) {
      return;
    }
    ref.invalidate(dashboardControllerProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Payment recorded.')));
  }

  @override
  Widget build(BuildContext context) {
    final customer = _liveCustomer();
    if (customer == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Customer')),
        body: EmptyState(
          icon: Icons.person_off_outlined,
          title: 'Customer not found',
          message: 'Open a customer from the list to see their profile.',
          action: SecondaryButton(
            label: 'Back to Customers',
            icon: Icons.arrow_back,
            onPressed: () => context.pop(),
          ),
        ),
      );
    }
    final ledger = ref.watch(customerLedgerProvider(customer.id));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Details'),
        actions: [
          IconButton(
            tooltip: 'Edit customer',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push(AppRoutes.customerEdit, extra: customer),
          ),
        ],
      ),
      body: ListView(
        padding: AppInsets.screen,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppAvatar(name: customer.name, size: 56),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  color: context.appColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            'Customer since ${formatDate(customer.createdAt)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: context.appColors.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(isActive: customer.isActive),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Contact details',
            subtitle: 'Phone is unique when present.',
            child: _ContactList(customer: customer),
          ),
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            title: 'Activity',
            child: SwitchListTile(
              contentPadding: AppInsets.zero,
              title: const Text('Active customer'),
              subtitle: Text(
                customer.isActive
                    ? 'This customer is visible on active lists.'
                    : 'This customer is hidden from active lists.',
              ),
              value: customer.isActive,
              onChanged: _busy ? null : (_) => _toggleActive(customer),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          ledger.when(
            skipLoadingOnRefresh: true,
            loading: () => SectionCard(
              title: 'Financial summary',
              child: LoadingState(message: 'Loading the ledger…'),
            ),
            error: (error, stackTrace) => SectionCard(
              title: 'Financial summary',
              child: ErrorState(
                message: customerLedgerErrorMessage(error),
                onRetry: () =>
                    ref.invalidate(customerLedgerProvider(customer.id)),
              ),
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FinancialSummaryCard(
                  ledger: data,
                  onRecordPayment: () => _recordPayment(customer.id, data),
                ),
                const SizedBox(height: AppSpacing.lg),
                _PurchasesSection(purchases: data.purchases),
                const SizedBox(height: AppSpacing.lg),
                _PaymentsSection(payments: data.payments),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Outstanding dues + lifetime totals, with the Record Payment action.
final class _FinancialSummaryCard extends StatelessWidget {
  const _FinancialSummaryCard({
    required this.ledger,
    required this.onRecordPayment,
  });

  final CustomerLedgerData ledger;
  final VoidCallback onRecordPayment;

  @override
  Widget build(BuildContext context) {
    final summary = ledger.summary;
    final hasDue = summary.outstandingPaise > 0;
    final billCount = ledger.purchases.length;
    final paymentCount = ledger.payments.length;
    return SectionCard(
      title: 'Financial summary',
      subtitle: 'Sales, payments and what is still owed.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KpiCard(
                  label: 'Outstanding',
                  value: Money.formatPaise(summary.outstandingPaise),
                  icon: Icons.account_balance_wallet_outlined,
                  accent: hasDue ? AppColors.error : AppColors.success,
                  caption: '$billCount bill${billCount == 1 ? '' : 's'}',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: KpiCard(
                  label: 'Total purchases',
                  value: Money.formatPaise(summary.totalPurchasesPaise),
                  icon: Icons.receipt_long_outlined,
                  accent: AppColors.primary,
                  caption: 'All customer bills',
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: KpiCard(
                  label: 'Total paid',
                  value: Money.formatPaise(summary.totalPaidPaise),
                  icon: Icons.payments_outlined,
                  accent: AppColors.info,
                  caption:
                      '$paymentCount payment${paymentCount == 1 ? '' : 's'}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: 'Record Payment',
            icon: Icons.payments_outlined,
            expanded: true,
            minHeight: 44,
            onPressed: hasDue ? onRecordPayment : null,
          ),
        ],
      ),
    );
  }
}

/// Bills linked to this customer with their derived payment status.
final class _PurchasesSection extends StatelessWidget {
  const _PurchasesSection({required this.purchases});

  final List<CustomerPurchase> purchases;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Purchase history',
      subtitle: 'Customer-linked bills and their payment status.',
      child: purchases.isEmpty
          ? const EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No purchases yet',
              message: 'Bills linked to this customer will appear here.',
            )
          : Column(
              children: [
                for (final purchase in purchases) ...[
                  _PurchaseRow(purchase: purchase),
                  if (purchase != purchases.last)
                    const Divider(height: AppSpacing.xl),
                ],
              ],
            ),
    );
  }
}

final class _PurchaseRow extends StatelessWidget {
  const _PurchaseRow({required this.purchase});

  final CustomerPurchase purchase;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Receipt ${purchase.receiptNumber}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatDate(purchase.createdAt)} · '
                'Total ${Money.formatPaise(purchase.totalPaise)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _PaymentStatusChip(status: purchase.status),
            if (purchase.duePaise > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Due ${Money.formatPaise(purchase.duePaise)}',
                maxLines: 1,
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// Amounts received against this customer's bills.
final class _PaymentsSection extends StatelessWidget {
  const _PaymentsSection({required this.payments});

  final List<CustomerPayment> payments;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Payment history',
      subtitle: 'Amounts received against this customer’s bills.',
      child: payments.isEmpty
          ? const EmptyState(
              icon: Icons.payments_outlined,
              title: 'No payments yet',
              message:
                  'Payments recorded at the counter or from this page '
                  'will appear here.',
            )
          : Column(
              children: [
                for (final payment in payments) ...[
                  _PaymentRow(payment: payment),
                  if (payment != payments.last)
                    const Divider(height: AppSpacing.xl),
                ],
              ],
            ),
    );
  }
}

final class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment});

  final CustomerPayment payment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      if (payment.note != null && payment.note!.isNotEmpty) payment.note!,
      paymentMethodLabel(payment.paymentMethod),
      formatDateTime(payment.paidAt),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                details.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Text(
          Money.formatPaise(payment.amountPaise),
          maxLines: 1,
          style: textTheme.bodyMedium?.copyWith(
            color: context.appColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Derived sale payment status badge; colors mirror the status meaning.
final class _PaymentStatusChip extends StatelessWidget {
  const _PaymentStatusChip({required this.status});

  final SalePaymentStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      SalePaymentStatus.paid => ('Paid', AppColors.success),
      SalePaymentStatus.partial => ('Partial', AppColors.warning),
      SalePaymentStatus.unpaid => ('Unpaid', AppColors.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Records a payment against one due bill. Amount defaults to the bill's
/// remaining due and is re-anchored when the bill changes; every
/// [CustomerLedgerFailure] is shown inline without closing the dialog, so the
/// counter can correct the input and retry.
final class _RecordPaymentDialog extends ConsumerStatefulWidget {
  const _RecordPaymentDialog({
    required this.customerId,
    required this.duePurchases,
  });

  final String customerId;
  final List<CustomerPurchase> duePurchases;

  @override
  ConsumerState<_RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

final class _RecordPaymentDialogState
    extends ConsumerState<_RecordPaymentDialog> {
  late String _saleId = widget.duePurchases.first.saleId;
  late final TextEditingController _amount = TextEditingController(
    text: Money.paiseToRupeesInput(_dueOf(_saleId)),
  );
  final TextEditingController _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;
  String? _error;

  int _dueOf(String saleId) {
    for (final purchase in widget.duePurchases) {
      if (purchase.saleId == saleId) {
        return purchase.duePaise;
      }
    }
    return 0;
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final paise = Money.parseRupeesToPaise(_amount.text);
    String? error;
    if (paise == null) {
      error = 'Enter a valid amount (e.g. 149.50)';
    } else if (paise <= 0) {
      error = 'Enter an amount greater than zero.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payment = await ref
          .read(customerLedgerProvider(widget.customerId).notifier)
          .recordPayment(
            saleId: _saleId,
            amountPaise: paise!,
            paymentMethod: _method,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) {
        Navigator.of(context).pop(payment);
      }
    } on CustomerLedgerFailure catch (failure) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = failure.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final labelStyle = textTheme.titleSmall?.copyWith(
      color: context.appColors.textPrimary,
      fontWeight: FontWeight.w700,
    );
    return AlertDialog(
      title: const Text('Record Payment'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bill', style: labelStyle),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: _saleId,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  for (final purchase in widget.duePurchases)
                    DropdownMenuItem(
                      value: purchase.saleId,
                      child: Text(
                        'Receipt ${purchase.receiptNumber} · '
                        '${Money.formatPaise(purchase.duePaise)} due',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }
                  setState(() {
                    _saleId = value;
                    _amount.text = Money.paiseToRupeesInput(_dueOf(value));
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Amount (₹) *', style: labelStyle),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                decoration: const InputDecoration(
                  hintText: 'e.g. 149.50',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Payment method *', style: labelStyle),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<PaymentMethod>(
                  segments: const [
                    ButtonSegment(
                      value: PaymentMethod.cash,
                      label: Text('Cash'),
                    ),
                    ButtonSegment(value: PaymentMethod.upi, label: Text('UPI')),
                    ButtonSegment(
                      value: PaymentMethod.bank,
                      label: Text('Bank'),
                    ),
                  ],
                  selected: {_method},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _method = selection.first),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Note (optional)', style: labelStyle),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Part payment',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save Payment'),
        ),
      ],
    );
  }
}

/// Display label for a payment method.
String paymentMethodLabel(PaymentMethod method) => switch (method) {
  PaymentMethod.cash => 'Cash',
  PaymentMethod.upi => 'UPI',
  PaymentMethod.bank => 'Bank',
};

final class _ContactList extends StatelessWidget {
  const _ContactList({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final contacts = <(IconData, String)>[
      (Icons.phone_outlined, customer.phone ?? 'No phone number'),
      (Icons.mail_outline, customer.email ?? 'No email address'),
      (Icons.location_on_outlined, customer.address ?? 'No address'),
    ];
    return Column(
      children: [
        for (final (icon, value) in contacts)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: context.appColors.textSecondary),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    value,
                    style: textTheme.bodyMedium?.copyWith(
                      color: value.startsWith('No ')
                          ? context.appColors.textDisabled
                          : context.appColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

final class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? AppColors.success : context.appColors.textDisabled;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppBorderRadius.pill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs + 2),
          Text(
            isActive ? 'Active' : 'Inactive',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
