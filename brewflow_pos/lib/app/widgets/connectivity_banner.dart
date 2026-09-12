import 'package:brewflow_pos/core/theme/app_colors.dart';
import 'package:brewflow_pos/core/theme/app_spacing.dart';
import 'package:brewflow_pos/features/dashboard/presentation/dashboard_controller.dart'
    show connectivityStatusProvider;
import 'package:brewflow_pos/core/services/connectivity_service.dart'
    show ConnectivityStatus;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — No Internet Connection banner
///
/// A slim app-wide banner shown inside the authenticated shell whenever the
/// device is offline. It advertises that online-only actions are currently
/// unavailable and that the session stays signed in (a lost connection never
/// logs the user out), turning Internet-back-on automatically via the
/// [connectivityStatusProvider] stream.
///
/// Renders nothing while online or while connectivity is still undetermined,
/// so it never flashes on startup.
/// ---------------------------------------------------------------------------
final class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(connectivityStatusProvider);
    if (status != ConnectivityStatus.disconnected) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: AppColors.warning,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_outlined,
                size: 18,
                color: AppColors.charcoal,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No Internet Connection — online actions are unavailable '
                  'until you reconnect.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: AppColors.charcoal,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
