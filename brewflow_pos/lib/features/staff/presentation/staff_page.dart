import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/staff/data/supabase_staff_provisioning.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Staff Management (OWNER only)
///
/// The route guard already rejects non-owners; this page additionally refuses
/// to render without [Permission.manageStaff] so the boundary holds even if
/// routing changes. The owner creates staff through the secure provisioning
/// boundary, then manages activation and permissions locally.
/// ---------------------------------------------------------------------------

final class StaffPage extends ConsumerStatefulWidget {
  const StaffPage({super.key});

  @override
  ConsumerState<StaffPage> createState() => _StaffPageState();
}

final class _StaffPageState extends ConsumerState<StaffPage> {
  List<UserProfile>? _staff;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final staff = await ref.read(staffRepositoryProvider).staffMembers();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _error = null;
      });
    } on StaffFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addStaff() async {
    if (!mounted) return;
    if (!ref.read(canProvider(Permission.manageStaff))) {
      _showMessage(const PermissionDeniedFailure().message);
      return;
    }
    final input = await showDialog<StaffCreateInput>(
      context: context,
      builder: (context) => const _StaffFormDialog(),
    );
    if (input == null || !mounted) return;
    try {
      final identity = await ref
          .read(staffProvisioningServiceProvider)
          .createStaffAuthUser(input);
      final shop = await ref.read(staffRepositoryProvider).ensureShop();
      await ref
          .read(staffRepositoryProvider)
          .createStaffProfile(
            identity: identity,
            shopId: shop.id,
            permissions: input.permissions,
            displayName: input.displayName,
          );
      _showMessage('Staff member added.');
      await _reload();
    } on StaffFailure catch (failure) {
      _showMessage(failure.message);
    }
  }

  Future<void> _editPermissions(UserProfile member) async {
    if (!mounted) return;
    if (!ref.read(canProvider(Permission.manageStaff))) {
      _showMessage(const PermissionDeniedFailure().message);
      return;
    }
    final updated = await showDialog<Set<Permission>>(
      context: context,
      builder: (context) =>
          _PermissionEditorDialog(current: member.permissions),
    );
    if (updated == null || !mounted) return;
    try {
      await ref
          .read(staffRepositoryProvider)
          .updateStaff(StaffUpdateInput(id: member.id, permissions: updated));
      _showMessage('Permissions saved.');
      await _reload();
    } on StaffFailure catch (failure) {
      _showMessage(failure.message);
    }
  }

  Future<void> _toggleActive(UserProfile member) async {
    if (!mounted) return;
    if (!ref.read(canProvider(Permission.manageStaff))) {
      _showMessage(const PermissionDeniedFailure().message);
      return;
    }
    try {
      await ref
          .read(staffRepositoryProvider)
          .updateStaff(
            StaffUpdateInput(id: member.id, isActive: !member.isActive),
          );
      await _reload();
    } on StaffFailure catch (failure) {
      _showMessage(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final allowed = ref.watch(canProvider(Permission.manageStaff));
    if (!allowed) {
      // Hard boundary mirror of the route guard.
      return const Scaffold(body: Center(child: Text('No access')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Staff Management')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addStaff,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Staff'),
      ),
      body: Padding(
        padding: AppInsets.screen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Manage who can use the shop and what they may do.',
              style: textTheme.bodyMedium?.copyWith(
                color: context.appColors.textSecondary,
              ),
            ),
            SizedBox(height: AppSpacing.lg),
            if (_error != null)
              ErrorState(message: _error!, onRetry: _reload)
            else if (_staff == null)
              const LoadingState(message: 'Loading staff…')
            else if (_staff!.isEmpty)
              EmptyState(
                icon: Icons.group_outlined,
                title: 'No staff yet',
                message:
                    'Add staff to give your team their own login with the '
                    'permissions you choose.',
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _staff!.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = _staff![index];
                    return ListTile(
                      leading: Icon(
                        member.isActive
                            ? Icons.person_outline
                            : Icons.person_off_outlined,
                        color: member.isActive
                            ? context.appColors.textSecondary
                            : AppColors.outOfStock,
                      ),
                      title: Text(
                        member.displayName ?? member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${member.email} · '
                        '${member.isActive ? 'Active' : 'Disabled'} · '
                        '${member.permissions.length} permissions',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit permissions',
                            icon: const Icon(Icons.tune),
                            onPressed: () => _editPermissions(member),
                          ),
                          Switch(
                            value: member.isActive,
                            onChanged: (_) => _toggleActive(member),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Create-staff dialog: email/password/display name plus the grouped
/// permission editor. Nothing persists until both the secure provisioning
/// call and the local profile write succeed.
final class _StaffFormDialog extends ConsumerStatefulWidget {
  const _StaffFormDialog();

  @override
  ConsumerState<_StaffFormDialog> createState() => _StaffFormDialogState();
}

final class _StaffFormDialogState extends ConsumerState<_StaffFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  Set<Permission> _permissions = defaultStaffPermissions;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add Staff'),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || !value.contains('@'))
                      ? 'Enter a valid email.'
                      : null,
                ),
                SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Temporary password *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value == null || value.length < 6)
                      ? 'Use at least 6 characters.'
                      : null,
                ),
                SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    hintText: 'Optional',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: AppSpacing.md),
                _PermissionGroups(
                  selected: _permissions,
                  onChanged: (next) => setState(() => _permissions = next),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          label: 'Create',
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(
                StaffCreateInput(
                  email: _email.text.trim(),
                  password: _password.text,
                  displayName: _name.text.trim().isEmpty
                      ? null
                      : _name.text.trim(),
                  permissions: _permissions,
                ),
              );
            }
          },
        ),
      ],
    );
  }
}

/// Owner-only grouped permission editor; Cancel never persists.
final class _PermissionEditorDialog extends StatefulWidget {
  const _PermissionEditorDialog({required this.current});

  final Set<Permission> current;

  @override
  State<_PermissionEditorDialog> createState() =>
      _PermissionEditorDialogState();
}

final class _PermissionEditorDialogState
    extends State<_PermissionEditorDialog> {
  late Set<Permission> _selected = {...widget.current};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Permissions'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: _PermissionGroups(
            selected: _selected,
            onChanged: (next) => setState(() => _selected = next),
          ),
        ),
      ),
      actions: [
        SecondaryButton(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
        ),
        PrimaryButton(
          label: 'Save',
          onPressed: () => Navigator.of(context).pop(_selected),
        ),
      ],
    );
  }
}

/// Grouped switch sections matching the agreed permission layout.
final class _PermissionGroups extends StatelessWidget {
  const _PermissionGroups({required this.selected, required this.onChanged});

  final Set<Permission> selected;
  final ValueChanged<Set<Permission>> onChanged;

  static const Map<String, List<(Permission, String)>> _groups = {
    'Sales': [(Permission.billing, 'Billing'), (Permission.orders, 'Orders')],
    'Inventory': [
      (Permission.viewInventory, 'View Inventory'),
      (Permission.editInventory, 'Edit Inventory'),
      (Permission.stockAdjustment, 'Stock Adjustment'),
      (Permission.purchases, 'Purchases'),
      (Permission.suppliers, 'Suppliers'),
    ],
    'Customers': [
      (Permission.customers, 'Customers'),
      (Permission.customerLedger, 'Customer Ledger'),
    ],
    'Business': [
      (Permission.expenses, 'Expenses'),
      (Permission.reports, 'Reports'),
      (Permission.settings, 'Settings'),
    ],
    'Administration': [(Permission.manageStaff, 'Manage Staff')],
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in _groups.entries) ...[
          Text(
            entry.key,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          for (final (permission, label) in entry.value)
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: selected.contains(permission),
              onChanged: (enabled) {
                final next = {...selected};
                enabled ? next.add(permission) : next.remove(permission);
                onChanged(next);
              },
            ),
          SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
