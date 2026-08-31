import 'package:brewflow_pos/app/widgets/app_avatar.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Account Menu
///
/// The avatar's tap surface. Instead of jumping straight to Settings, it opens
/// an account menu with Profile / Change Account / Sign out. "Change Account"
/// signs out so a different account can sign in; "Sign out" signs out too.
/// Profile shows the signed-in account and role.
///
/// The menu is a modal bottom sheet so it works identically on phone and
/// tablet without a device check. Sign-out reuses the single existing
/// [AuthController] flow (the router then returns to the auth screen).
/// ---------------------------------------------------------------------------

/// Opening/tap callback builder so callers keep their own layout. Renders an
/// [AppAvatar] whose tap opens the account menu.
final class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({
    super.key,
    required this.name,
    this.size = 36,
    this.onOpen,
  });

  /// The display identity (usually the email); its initial seeds the avatar.
  final String name;
  final double size;

  /// Optional post-open hook (e.g. closing a drawer/dialog). Runs after the
  /// menu closes.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppAvatar(
      name: name,
      size: size,
      onTap: () async {
        await showAccountMenu(context, email: name);
        onOpen?.call();
      },
    );
  }
}

/// Opens the account menu bottom sheet.
Future<void> showAccountMenu(BuildContext context, {required String email}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (sheetContext) => _AccountMenuSheet(email: email),
  );
}

final class _AccountMenuSheet extends ConsumerWidget {
  const _AccountMenuSheet({required this.email});

  final String email;

  String _roleLabel(UserProfile? profile) {
    if (profile == null) return 'Signed in';
    return switch (profile.role) {
      UserRole.owner => 'Owner',
      UserRole.staff => 'Staff',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    final profile = ref.read(userProfileProvider).value;
    final shopSettings = ref.read(shopSettingsProvider).value;
    final shopName = shopSettings?.shopName;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.xs,
          AppSpacing.screenPadding,
          AppSpacing.massive,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(name: email, size: 44),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _roleLabel(profile),
                        style: textTheme.titleMedium?.copyWith(
                          color: appColors.charcoal,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: appColors.textSecondary,
                        ),
                      ),
                      if (shopName != null && shopName.trim().isNotEmpty)
                        Text(
                          shopName.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _MenuAction(
              icon: Icons.account_circle_outlined,
              label: 'Profile',
              onTap: () {
                Navigator.of(context).pop();
                _showProfile(context, email: email, role: _roleLabel(profile));
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _MenuAction(
              icon: Icons.swap_horiz_outlined,
              label: 'Change Account',
              onTap: () {
                Navigator.of(context).pop();
                _confirmAndSignOut(context, ref, 'Change Account');
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            _MenuAction(
              icon: Icons.logout_outlined,
              label: 'Sign out',
              destructive: true,
              onTap: () {
                Navigator.of(context).pop();
                _confirmAndSignOut(context, ref, 'Sign out');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showProfile(
    BuildContext context, {
    required String email,
    required String role,
  }) async {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProfileLine(label: 'Role', value: role),
            const SizedBox(height: AppSpacing.sm),
            _ProfileLine(label: 'Email', value: email),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndSignOut(
    BuildContext context,
    WidgetRef ref,
    String action,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(action),
        content: const Text(
          'Are you sure you want to sign out? '
          'Any unsynced data will remain on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      ref.read(authControllerProvider.notifier).signOut();
    }
  }
}

final class _MenuAction extends StatelessWidget {
  const _MenuAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final color = destructive ? AppColors.error : appColors.charcoal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;
    return Row(
      children: [
        Text(
          '$label: ',
          style: textTheme.bodyMedium?.copyWith(
            color: appColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium?.copyWith(color: appColors.textPrimary),
          ),
        ),
      ],
    );
  }
}
