import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/utils/money.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/customers/domain/customers_models.dart';
import 'package:brewflow_pos/features/customers/domain/whatsapp_verification.dart';
import 'package:brewflow_pos/features/customers/presentation/customers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Customer Form Page
///
/// Create or edit a customer profile. The name is required; phone, email and
/// address are optional. The phone is unique when present (case-insensitive,
/// enforced by the repository) — empty input never stores a value. Pushed
/// from the customers page, so it carries its own scaffold.
/// ---------------------------------------------------------------------------

final class CustomerFormPage extends ConsumerStatefulWidget {
  const CustomerFormPage({super.key, this.customer});

  /// The customer being edited; null when creating a new one.
  final Customer? customer;

  @override
  ConsumerState<CustomerFormPage> createState() => CustomerFormPageState();
}

final class CustomerFormPageState extends ConsumerState<CustomerFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.customer?.name ?? '',
  );

  late final TextEditingController _phone = TextEditingController(
    text: widget.customer?.phone ?? '',
  );

  late final TextEditingController _email = TextEditingController(
    text: widget.customer?.email ?? '',
  );

  late final TextEditingController _address = TextEditingController(
    text: widget.customer?.address ?? '',
  );

  late bool _isActive = widget.customer?.isActive ?? true;
  late bool _membershipActive = widget.customer?.membershipActive ?? false;

  /// Honest WhatsApp status: carried from the existing profile; a new
  /// customer starts UNKNOWN until a real provider verifies the number.
  late final WhatsAppStatus _whatsappStatus =
      widget.customer?.whatsappStatus ?? WhatsAppStatus.unknown;

  late final TextEditingController _membershipFee = TextEditingController(
    text: widget.customer?.membershipFeePaise == null
        ? ''
        : Money.paiseToRupeesInput(widget.customer!.membershipFeePaise!),
  );
  String? _phoneError;
  bool _saving = false;

  bool get _editing => widget.customer != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _membershipFee.dispose();
    super.dispose();
  }

  /// Parses the membership fee input (rupees, e.g. '50' or '50.50') into
  /// integer paise; null when blank. Invalid input keeps the form open with
  /// a validator message instead of saving a wrong value.
  int? _parsedFeePaise() {
    final text = _membershipFee.text.trim().replaceAll('₹', '');
    if (text.isEmpty) return null;
    return Money.parseRupeesToPaise(text);
  }

  Future<void> _submit() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _phoneError = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final phone = _phone.text.trim();
    if (phone.isNotEmpty) {
      try {
        final exists = await ref
            .read(customersProvider.notifier)
            .phoneExists(phone, exceptId: widget.customer?.id);
        if (exists) {
          setState(
            () => _phoneError = 'A customer with this phone already exists.',
          );
          return;
        }
      } on Object catch (error) {
        _showMessage(customersErrorMessage(error));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(customersProvider.notifier);
      if (_editing) {
        await controller.updateCustomer(
          id: widget.customer!.id,
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          isActive: _isActive,
          membershipActive: _membershipActive,
          membershipFeePaise: _parsedFeePaise(),
          whatsappStatus: _whatsappStatus,
        );
      } else {
        await controller.create(
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          isActive: _isActive,
          membershipActive: _membershipActive,
          membershipFeePaise: _parsedFeePaise(),
          whatsappStatus: _whatsappStatus,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Customer updated.' : 'Customer added.'),
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
        SnackBar(content: Text(customersErrorMessage(error))),
      );
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'Edit Customer' : 'New Customer')),
      body: SingleChildScrollView(
        padding: AppInsets.screen,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing
                    ? 'Update the profile details below.'
                    : 'Fill in the customer details below.',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Customer name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Customer name is required.'
                    : null,
              ),
              SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                ],
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  hintText: 'Optional',
                  errorText: _phoneError,
                  border: const OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppBorderRadius.md,
                    borderSide: BorderSide(color: context.appColors.divider),
                  ),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  if (text.length < 7) {
                    return 'Enter a valid phone number.';
                  }
                  return null;
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  children: [
                    Icon(
                      _whatsappStatus == WhatsAppStatus.verified
                          ? Icons.check_circle
                          : Icons.info_outline,
                      size: 16,
                      color: _whatsappStatus == WhatsAppStatus.verified
                          ? AppColors.success
                          : context.appColors.textSecondary,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text(
                      // Honest wording: only a real provider can ever mark a
                      // number verified; format validity proves nothing.
                      _whatsappStatus.label,
                      style: textTheme.bodySmall?.copyWith(
                        color: _whatsappStatus == WhatsAppStatus.verified
                            ? AppColors.success
                            : context.appColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'Enter a valid email address.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: AppInsets.zero,
                title: const Text('Active customer'),
                subtitle: const Text(
                  'Hides the customer from active lists when off.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              SwitchListTile(
                contentPadding: AppInsets.zero,
                secondary: const Icon(Icons.workspace_premium_outlined),
                title: const Text('Membership'),
                subtitle: const Text(
                  'Member customers are charged member prices at the '
                  'counter when membership is enabled in Settings.',
                ),
                value: _membershipActive,
                onChanged: (value) => setState(() => _membershipActive = value),
              ),
              if (_membershipActive) ...[
                TextFormField(
                  controller: _membershipFee,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Membership fee (₹)',
                    hintText: 'Optional — e.g. 50',
                    prefixText: '₹ ',
                    border: OutlineInputBorder(
                      borderRadius: AppBorderRadius.md,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: AppBorderRadius.md,
                      borderSide: BorderSide(color: context.appColors.divider),
                    ),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim().replaceAll('₹', '');
                    if (text.isEmpty) return null;
                    return Money.parseRupeesToPaise(text) == null
                        ? 'Enter a valid amount, e.g. 50 or 50.50.'
                        : null;
                  },
                ),
              ],
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_editing ? 'Save Changes' : 'Save Customer'),
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
