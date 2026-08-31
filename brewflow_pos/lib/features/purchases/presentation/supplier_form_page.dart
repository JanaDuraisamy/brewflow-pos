import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/purchases/domain/purchases_models.dart';
import 'package:brewflow_pos/features/purchases/presentation/suppliers_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Supplier Form Page
///
/// Create or edit a supplier profile. The name is required; phone, email,
/// address and notes are optional. The phone is unique when present
/// (case-insensitive, enforced by the repository) — empty input never stores
/// a value. Editing preserves the id and createdAt; only the profile fields
/// and status change. Pushed from the suppliers page, so it carries its own
/// scaffold.
/// ---------------------------------------------------------------------------

final class SupplierFormPage extends ConsumerStatefulWidget {
  const SupplierFormPage({super.key, this.supplier});

  /// The supplier being edited; null when creating a new one.
  final Supplier? supplier;

  @override
  ConsumerState<SupplierFormPage> createState() => SupplierFormPageState();
}

final class SupplierFormPageState extends ConsumerState<SupplierFormPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name = TextEditingController(
    text: widget.supplier?.name ?? '',
  );

  late final TextEditingController _phone = TextEditingController(
    text: widget.supplier?.phone ?? '',
  );

  late final TextEditingController _email = TextEditingController(
    text: widget.supplier?.email ?? '',
  );

  late final TextEditingController _address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );

  late final TextEditingController _notes = TextEditingController(
    text: widget.supplier?.notes ?? '',
  );

  late bool _isActive = widget.supplier?.isActive ?? true;
  String? _phoneError;
  bool _saving = false;

  bool get _editing => widget.supplier != null;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _notes.dispose();
    super.dispose();
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
            .read(suppliersProvider.notifier)
            .phoneExists(phone, exceptId: widget.supplier?.id);
        if (exists) {
          setState(
            () => _phoneError = 'A supplier with this phone already exists.',
          );
          return;
        }
      } on Object catch (error) {
        _showMessage(suppliersErrorMessage(error));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final controller = ref.read(suppliersProvider.notifier);
      if (_editing) {
        await controller.updateSupplier(
          id: widget.supplier!.id,
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          isActive: _isActive,
        );
      } else {
        await controller.create(
          name: _name.text.trim(),
          phone: phone.isEmpty ? null : phone,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          address: _address.text.trim().isEmpty ? null : _address.text.trim(),
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          isActive: _isActive,
        );
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(_editing ? 'Supplier updated.' : 'Supplier added.'),
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
        SnackBar(content: Text(suppliersErrorMessage(error))),
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
      appBar: AppBar(title: Text(_editing ? 'Edit Supplier' : 'New Supplier')),
      body: SingleChildScrollView(
        padding: AppInsets.screen,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _editing
                    ? 'Update the supplier details below.'
                    : 'Fill in the supplier details below.',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Supplier name *',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value == null || value.trim().isEmpty)
                    ? 'Supplier name is required.'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
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
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notes,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                contentPadding: AppInsets.zero,
                title: const Text('Active supplier'),
                subtitle: const Text(
                  'Hides the supplier from active lists when off. '
                  'Purchase history is never removed.',
                ),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_editing ? 'Save Changes' : 'Save Supplier'),
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
