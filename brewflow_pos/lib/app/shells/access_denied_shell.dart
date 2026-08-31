import 'package:brewflow_pos/app/widgets/widgets.dart';
import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_theme_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/auth/presentation/auth_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Access Denied Shell
///
/// Landing for authenticated accounts that tried to reach a route their
/// profile does not permit (or that has no provisioned profile yet). Offers
/// the single existing sign-out flow; no diagnostics leak.
/// ---------------------------------------------------------------------------

final class AccessDeniedShell extends ConsumerWidget {
  const AccessDeniedShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: AppInsets.screen,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 48,
                color: AppColors.primary,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(
                'No access to this area',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: AppSpacing.sm),
              Text(
                'Your account does not have permission for this feature. '
                'Ask the shop owner to grant access.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: context.appColors.textSecondary,
                ),
              ),
              SizedBox(height: AppSpacing.xl),
              SecondaryButton(
                label: 'Sign out',
                icon: Icons.logout_outlined,
                onPressed: () =>
                    ref.read(authControllerProvider.notifier).signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
