import 'package:brewflow_pos/app/widgets/app_buttons.dart';
import 'package:brewflow_pos/app/widgets/app_card.dart';
import 'package:brewflow_pos/app/widgets/page_header.dart';
import 'package:brewflow_pos/app/widgets/responsive.dart';
import 'package:brewflow_pos/app/widgets/state_views.dart';
import 'package:brewflow_pos/config/constants.dart';
import 'package:brewflow_pos/config/flavor.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_radius.dart';
import 'package:brewflow_pos/core/theme/app_shadows.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/router/app_routes.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_section.dart';
import 'package:brewflow_pos/features/printing/data/unverified_printer_service.dart';
import 'package:brewflow_pos/features/settings/domain/settings_models.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:brewflow_pos/features/inventory/data/drift_inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/data/jiggar_menu_seed.dart';
import 'package:brewflow_pos/features/inventory/domain/inventory_repository.dart';
import 'package:brewflow_pos/features/inventory/presentation/inventory_controller.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Settings Page
///
/// Business identity, preferences and app details. Values persist through
/// [shopSettingsProvider] and reload automatically on the next launch. The
/// theme preference is applied app-wide by the root [MaterialApp] via
/// [appThemeModeProvider].
///
/// The page presents every setting as a compact row (icon, label, current
/// value) inside section cards; tapping a row opens a small edit dialog with
/// the same validation as before. All values still commit through the single
/// "Save Settings" action.
/// ---------------------------------------------------------------------------

final class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(shopSettingsProvider);
    return Padding(
      padding: AppInsets.screen,
      child: settings.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingState(message: 'Loading settings…'),
        error: (error, stackTrace) => ErrorState(
          message: settingsErrorMessage(error),
          onRetry: () => ref.invalidate(shopSettingsProvider),
        ),
        data: (value) => _SettingsForm(settings: value),
      ),
    );
  }
}

final class _SettingsForm extends ConsumerStatefulWidget {
  const _SettingsForm({required this.settings});

  final ShopSettings settings;

  @override
  ConsumerState<_SettingsForm> createState() => _SettingsFormState();
}

final class _SettingsFormState extends ConsumerState<_SettingsForm> {
  late final TextEditingController _shopName = TextEditingController(
    text: widget.settings.shopName,
  );
  late final TextEditingController _appDisplayName = TextEditingController(
    text: widget.settings.appDisplayName,
  );
  late final TextEditingController _ownerName = TextEditingController(
    text: widget.settings.ownerName ?? '',
  );
  late final TextEditingController _phone = TextEditingController(
    text: widget.settings.phone ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.settings.email ?? '',
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.settings.address ?? '',
  );
  late final TextEditingController _threshold = TextEditingController(
    text: widget.settings.lowStockThreshold.toString(),
  );
  late ThemePreference _theme = widget.settings.theme;
  late bool _membership = widget.settings.membershipEnabled;
  bool _saving = false;
  bool _dirty = false;

  @override
  void dispose() {
    _shopName.dispose();
    _appDisplayName.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _threshold.dispose();
    super.dispose();
  }

  /// Opens a compact edit dialog for one text setting. The dialog edits the
  /// page's controller directly; Cancel restores the previous text so a
  /// dismissed dialog never changes a value. Save commits the typed value
  /// into the page state (the single Save Settings action persists
  /// everything).
  Future<void> _editText({
    required String title,
    required IconData icon,
    required TextEditingController controller,
    String? helperText,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    TextCapitalization? textCapitalization,
  }) async {
    final original = controller.text;
    final formKey = GlobalKey<FormState>();
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final textTheme = Theme.of(dialogContext).textTheme;
        return AlertDialog(
          title: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    color: context.appColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: textCapitalization ?? TextCapitalization.none,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              decoration: InputDecoration(
                labelText: title,
                helperText: helperText,
                border: const OutlineInputBorder(),
              ),
              validator: validator,
              onFieldSubmitted: (_) {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
            ),
          ),
          actions: [
            SecondaryButton(
              label: 'Cancel',
              minHeight: 40,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            PrimaryButton(
              label: 'Save',
              minHeight: 40,
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
            ),
          ],
        );
      },
    );
    if (saved != true) {
      controller.text = original;
    } else {
      if (controller.text.trim() != original.trim()) {
        _dirty = true;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final next = ShopSettings(
        shopName: _shopName.text.trim(),
        appDisplayName: _appDisplayName.text.trim().isEmpty
            ? AppConstants.defaultAppDisplayName
            : _appDisplayName.text.trim(),
        ownerName: _ownerName.text.trim().isEmpty
            ? null
            : _ownerName.text.trim(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        lowStockThreshold: int.parse(_threshold.text.trim()),
        theme: _theme,
        membershipEnabled: _membership,
      );
      await ref.read(shopSettingsProvider.notifier).save(next);
      if (mounted) setState(() => _dirty = false);
      messenger.showSnackBar(const SnackBar(content: Text('Settings saved.')));
    } on Object catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(settingsErrorMessage(error))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: ResponsiveBuilder(
        builder: (context, breakpoint) {
          return breakpoint.isCompact
              ? _buildCompactBody(context)
              : _buildExpandedBody(context);
        },
      ),
    );
  }

  /// Tablet / desktop layout. The dense titled section cards are kept for
  /// wider screens where there is room to breathe.
  Widget _buildExpandedBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: const PageHeader(
                    title: 'Settings',
                    subtitle: 'Business identity, preferences and app details.',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionCard(
                        title: 'Business identity',
                        subtitle:
                            'Manage your shop name, contact details and address.',
                        child: Column(
                          children: [
                            _SettingRow(
                              icon: Icons.store_outlined,
                              label: 'Business Name',
                              value: _shopName.text,
                              onTap: () => _editText(
                                title: 'Business Name',
                                icon: Icons.store_outlined,
                                controller: _shopName,
                                textCapitalization: TextCapitalization.words,
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'Shop name is required.'
                                    : null,
                              ),
                            ),
                            const _RowDivider(),
                            _SettingRow(
                              icon: Icons.badge_outlined,
                              label: 'App Display Name',
                              value: _appDisplayName.text,
                              onTap: () => _editText(
                                title: 'App Display Name',
                                icon: Icons.badge_outlined,
                                controller: _appDisplayName,
                                helperText:
                                    'Shown as the app header brand name.',
                                textCapitalization: TextCapitalization.words,
                                validator: (value) =>
                                    (value == null || value.trim().isEmpty)
                                    ? 'App display name is required.'
                                    : null,
                              ),
                            ),
                            const _RowDivider(),
                            _SettingRow(
                              icon: Icons.person_outline,
                              label: 'Owner Name',
                              value: _ownerName.text,
                              onTap: () => _editText(
                                title: 'Owner Name',
                                icon: Icons.person_outline,
                                controller: _ownerName,
                                textCapitalization: TextCapitalization.words,
                              ),
                            ),
                            const _RowDivider(),
                            _SettingRow(
                              icon: Icons.phone_outlined,
                              label: 'Phone',
                              value: _phone.text,
                              onTap: () => _editText(
                                title: 'Phone',
                                icon: Icons.phone_outlined,
                                controller: _phone,
                                keyboardType: TextInputType.phone,
                              ),
                            ),
                            const _RowDivider(),
                            _SettingRow(
                              icon: Icons.mail_outline,
                              label: 'Email',
                              value: _email.text,
                              onTap: () => _editText(
                                title: 'Email',
                                icon: Icons.mail_outline,
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                validator: (value) {
                                  final text = value?.trim() ?? '';
                                  if (text.isEmpty) {
                                    return null;
                                  }
                                  return text.contains('@')
                                      ? null
                                      : 'Enter a valid email address.';
                                },
                              ),
                            ),
                            const _RowDivider(),
                            _SettingRow(
                              icon: Icons.location_on_outlined,
                              label: 'Address',
                              value: _address.text,
                              onTap: () => _editText(
                                title: 'Address',
                                icon: Icons.location_on_outlined,
                                controller: _address,
                                textCapitalization:
                                    TextCapitalization.sentences,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SectionCard(
                        title: 'Preferences',
                        subtitle: 'Appearance and stock alert preferences.',
                        child: Column(
                          children: [
                            _SettingRow(
                              icon: Icons.inventory_2_outlined,
                              label: 'Low Stock Alert',
                              value: _threshold.text,
                              onTap: () => _editText(
                                title: 'Low Stock Alert',
                                icon: Icons.inventory_2_outlined,
                                controller: _threshold,
                                helperText:
                                    'Products at or below this stock level are '
                                    'flagged as running low.',
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (value) {
                                  final parsed = int.tryParse(
                                    value?.trim() ?? '',
                                  );
                                  if (parsed == null || parsed <= 0) {
                                    return 'Enter a number above 0.';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const _RowDivider(),
                            _MobileMembershipRow(
                              membership: _membership,
                              onChanged: (value) => setState(() {
                                _membership = value;
                                _dirty = true;
                              }),
                            ),
                            const _RowDivider(),
                            _MobileAppearanceRow(
                              theme: _theme,
                              onChanged: (value) => setState(() {
                                _theme = value;
                                _dirty = true;
                              }),
                            ),
                            const _RowDivider(),
                            const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              child: _CurrencyRow(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const BackupSectionCard(),
                      const SizedBox(height: AppSpacing.lg),
                      const SectionCard(
                        title: 'Printer',
                        subtitle: 'Receipt printing status and diagnostics.',
                        child: _PrinterRow(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const _StaffAccessCard(),
                      const SizedBox(height: AppSpacing.lg),
                      const _AboutCard(),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: AppInsets.screen,
              child: PrimaryButton(
                label: 'Save Settings',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Phone (<600dp) layout: a premium, airier settings experience. Settings
  /// are grouped into soft cards under small section labels, each row shows
  /// its label, current value and an edit affordance, and rows are separated
  /// by subtle hairlines. Everything persists through the same Save action.
  Widget _buildCompactBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const PageHeader(
                      title: 'Settings',
                      subtitle:
                          'Business identity, preferences and app details.',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _MobileSection(
                      label: 'Business identity',
                      children: [
                        _SettingRow(
                          icon: Icons.store_outlined,
                          label: 'Business Name',
                          value: _shopName.text,
                          onTap: () => _editText(
                            title: 'Business Name',
                            icon: Icons.store_outlined,
                            controller: _shopName,
                            textCapitalization: TextCapitalization.words,
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'Shop name is required.'
                                : null,
                          ),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.badge_outlined,
                          label: 'App Display Name',
                          value: _appDisplayName.text,
                          onTap: () => _editText(
                            title: 'App Display Name',
                            icon: Icons.badge_outlined,
                            controller: _appDisplayName,
                            helperText: 'Shown as the app header brand name.',
                            textCapitalization: TextCapitalization.words,
                            validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                ? 'App display name is required.'
                                : null,
                          ),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.person_outline,
                          label: 'Owner Name',
                          value: _ownerName.text,
                          onTap: () => _editText(
                            title: 'Owner Name',
                            icon: Icons.person_outline,
                            controller: _ownerName,
                            textCapitalization: TextCapitalization.words,
                          ),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.phone_outlined,
                          label: 'Phone',
                          value: _phone.text,
                          onTap: () => _editText(
                            title: 'Phone',
                            icon: Icons.phone_outlined,
                            controller: _phone,
                            keyboardType: TextInputType.phone,
                          ),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.mail_outline,
                          label: 'Email',
                          value: _email.text,
                          onTap: () => _editText(
                            title: 'Email',
                            icon: Icons.mail_outline,
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              final text = value?.trim() ?? '';
                              if (text.isEmpty) {
                                return null;
                              }
                              return text.contains('@')
                                  ? null
                                  : 'Enter a valid email address.';
                            },
                          ),
                        ),
                        const _RowDivider(),
                        _SettingRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: _address.text,
                          onTap: () => _editText(
                            title: 'Address',
                            icon: Icons.location_on_outlined,
                            controller: _address,
                            textCapitalization: TextCapitalization.sentences,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _MobileSection(
                      label: 'Preferences',
                      children: [
                        _SettingRow(
                          icon: Icons.inventory_2_outlined,
                          label: 'Low Stock Alert',
                          value: _threshold.text,
                          onTap: () => _editText(
                            title: 'Low Stock Alert',
                            icon: Icons.inventory_2_outlined,
                            controller: _threshold,
                            helperText:
                                'Products at or below this stock level are '
                                'flagged as running low.',
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            validator: (value) {
                              final parsed = int.tryParse(value?.trim() ?? '');
                              if (parsed == null || parsed <= 0) {
                                return 'Enter a number above 0.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const _RowDivider(),
                        _MobileMembershipRow(
                          membership: _membership,
                          onChanged: (value) => setState(() {
                            _membership = value;
                            _dirty = true;
                          }),
                        ),
                        const _RowDivider(),
                        _MobileAppearanceRow(
                          theme: _theme,
                          onChanged: (value) => setState(() {
                            _theme = value;
                            _dirty = true;
                          }),
                        ),
                        const _RowDivider(),
                        const _MobileCurrencyRow(),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    const MobileBackupSection(),
                    const SizedBox(height: AppSpacing.xl),
                    const _MobilePrinterSection(),
                    const SizedBox(height: AppSpacing.xl),
                    const _MobileStaffAccessCard(),
                    const SizedBox(height: AppSpacing.xl),
                    const _MobileAboutCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: AppInsets.screen,
          child: PrimaryButton(
            label: 'Save Settings',
            icon: Icons.save_outlined,
            loading: _saving,
            onPressed: _saving ? null : _save,
          ),
        ),
      ],
    );
  }
}

/// One tappable settings row: leading icon, label + current value, chevron.
/// Empty values render as 'Not set' — no placeholder text is ever invented.
final class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final isEmpty = value.trim().isEmpty;
    return InkWell(
      onTap: onTap,
      borderRadius: AppBorderRadius.sm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.primary),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.titleSmall?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    isEmpty ? 'Not set' : value,
                    style: isEmpty
                        ? textTheme.bodySmall?.copyWith(
                            color: context.appColors.textSecondary,
                          )
                        : textTheme.bodyMedium?.copyWith(
                            color: context.appColors.textPrimary,
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: context.appColors.textDisabled,
            ),
          ],
        ),
      ),
    );
  }
}

/// Subtle hairline between settings rows.
final class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, color: context.appColors.divider);
  }
}

/// Phone-only group: a small uppercase section label above a soft card that
/// holds its child rows. Gives a clean "grouped list" feel without every
/// section becoming a heavy full-bleed container.
final class _MobileSection extends StatelessWidget {
  const _MobileSection({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            label.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        AppCard(
          padding: AppInsets.sm,
          borderRadius: AppBorderRadius.md,
          shadows: const [AppShadows.xs],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// Phone-only membership toggle row.
final class _MobileMembershipRow extends StatelessWidget {
  const _MobileMembershipRow({
    required this.membership,
    required this.onChanged,
  });

  final bool membership;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!membership),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Membership',
                    style: textTheme.titleSmall?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    membership
                        ? 'Member customers pay member prices at the counter.'
                        : 'Membership pricing is disabled.',
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Switch(value: membership, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// Phone-only appearance row: label and a full-width theme segmented control.
final class _MobileAppearanceRow extends StatelessWidget {
  const _MobileAppearanceRow({required this.theme, required this.onChanged});

  final ThemePreference theme;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.palette_outlined,
                size: 20,
                color: AppColors.primary,
              ),
              SizedBox(width: AppSpacing.md),
              Text(
                'Appearance',
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemePreference>(
              segments: [
                for (final preference in ThemePreference.values)
                  ButtonSegment(
                    value: preference,
                    label: Text(preference.label),
                  ),
              ],
              selected: {theme},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => onChanged(selection.first),
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone-only currency info row.
final class _MobileCurrencyRow extends StatelessWidget {
  const _MobileCurrencyRow();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.currency_rupee, size: 20, color: AppColors.primary),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Currency',
                  style: textTheme.titleSmall?.copyWith(
                    color: context.appColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Indian Rupees (₹) — BrewFlow bills in paise precision.',
                  style: textTheme.bodySmall?.copyWith(
                    color: context.appColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Phone-only printer section.
final class _MobilePrinterSection extends ConsumerWidget {
  const _MobilePrinterSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            'Printer'.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: context.appColors.textSecondary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
        AppCard(
          padding: AppInsets.sm,
          borderRadius: AppBorderRadius.md,
          shadows: const [AppShadows.xs],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PrinterRow(),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Receipt printing status and diagnostics.',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Phone-only owner entry into Staff Management.
final class _MobileStaffAccessCard extends ConsumerWidget {
  const _MobileStaffAccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canProvider(Permission.manageStaff));
    if (!canManage) {
      return const SizedBox.shrink();
    }
    return _MobileSection(
      label: 'Staff & Permissions',
      children: [
        _SettingRow(
          icon: Icons.group_outlined,
          label: 'Staff Management',
          value: 'Add staff and control their permissions',
          onTap: () {
            context.go(AppRoutes.staff);
          },
        ),
      ],
    );
  }
}

/// Phone-only About section.
final class _MobileAboutCard extends ConsumerWidget {
  const _MobileAboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final isDevelopment = !AppFlavor.current.isProduction;
    return _MobileSection(
      label: 'About',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${AppConstants.appName} v${AppConstants.appVersion}',
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textPrimary,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Local-first billing. All data stays on this device.',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              if (isDevelopment) ...[
                SizedBox(height: AppSpacing.md),
                SecondaryButton(
                  label: 'Import JIGGAR Tea House menu',
                  icon: Icons.local_cafe_outlined,
                  onPressed: () => _importJiggarMenu(context, ref),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Printer diagnostics row: current adapter status plus a safe test print.
/// Uses the printing abstraction only — no hardware-specific code here.
final class _PrinterRow extends ConsumerWidget {
  const _PrinterRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final service = ref.watch(printerServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.print_outlined,
              size: 20,
              color: AppColors.primary,
            ),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Printer',
                    style: textTheme.titleSmall?.copyWith(
                      color: context.appColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppSpacing.xs),
                  Text(
                    service.statusLabel,
                    style: textTheme.bodySmall?.copyWith(
                      color: context.appColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SecondaryButton(
              label: 'Test Print',
              minHeight: 36,
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final result = await service.testPrint();
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(result.toString())));
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Owner-only entry into the dedicated Staff Management page. Visibility is
/// driven by the single authorization source; the /staff route and the page
/// itself enforce the same permission, so hiding alone is never the guard.
final class _StaffAccessCard extends ConsumerWidget {
  const _StaffAccessCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canManage = ref.watch(canProvider(Permission.manageStaff));
    if (!canManage) {
      return const SizedBox.shrink();
    }
    return SectionCard(
      title: 'Staff & Permissions',
      subtitle: 'Team access to shop features.',
      child: _SettingRow(
        icon: Icons.group_outlined,
        label: 'Staff Management',
        value: 'Add staff and control their permissions',
        onTap: () {
          context.go(AppRoutes.staff);
        },
      ),
    );
  }
}

/// Read-only currency information row.
///
/// BrewFlow bills in Indian Rupees (paise-precision integers) everywhere;
/// currency display is therefore locked to INR rather than offering a
/// setting that would have no effect.
final class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.currency_rupee, size: 20, color: AppColors.primary),
        SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Currency',
                style: textTheme.titleSmall?.copyWith(
                  color: context.appColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Indian Rupees (₹) — BrewFlow bills in paise precision. '
                'Other currencies are not supported.',
                style: textTheme.bodySmall?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

final class _AboutCard extends ConsumerWidget {
  const _AboutCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final isDevelopment = !AppFlavor.current.isProduction;
    return SectionCard(
      title: 'About',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${AppConstants.appName} v${AppConstants.appVersion}',
            style: textTheme.bodyMedium?.copyWith(
              color: context.appColors.textPrimary,
            ),
          ),
          SizedBox(height: AppSpacing.xs),
          Text(
            'Local-first billing. All data stays on this device.',
            style: textTheme.bodySmall?.copyWith(
              color: context.appColors.textSecondary,
            ),
          ),
          // Development-only bulk import of the shop menu. Uses the normal
          // inventory repository (and therefore the normal sync outbox);
          // idempotent — safe to run repeatedly.
          if (isDevelopment) ...[
            SizedBox(height: AppSpacing.md),
            SecondaryButton(
              label: 'Import JIGGAR Tea House menu',
              icon: Icons.local_cafe_outlined,
              onPressed: () => _importJiggarMenu(context, ref),
            ),
          ],
        ],
      ),
    );
  }
}

/// Development-only bulk import of the shop menu. Uses the normal inventory
/// repository (and therefore the normal sync outbox); idempotent — safe to run
/// repeatedly.
Future<void> _importJiggarMenu(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await JiggarMenuSeeder(
      ref.read(inventoryRepositoryProvider) as DriftInventoryRepository,
    ).run();
    ref.invalidate(productsProvider);
    ref.invalidate(categoriesProvider);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Menu import done. $result')));
  } on InventoryFailure catch (error) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(error.message)));
  } on Exception {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Menu import failed.')));
  }
}
