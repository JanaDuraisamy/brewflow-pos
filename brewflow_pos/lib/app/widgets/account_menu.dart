import 'package:brewflow_pos/app/widgets/app_avatar.dart';
import 'package:brewflow_pos/core/authorization/authorization.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/domain/staff_models.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow Design System — Account Menu
///
/// The avatar's tap surface. Opens an identity sheet showing the signed-in
/// account, role and shop. Sign-out lives in the shell (mobile header logout
/// icon / sidebar footer) so there is exactly one logout action per screen.
///
/// The menu is a modal bottom sheet so it works identically on phone and
/// tablet without a device check.
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
          ],
        ),
      ),
    );
  }
}
