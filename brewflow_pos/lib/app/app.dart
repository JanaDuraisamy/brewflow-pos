import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/theme/app_theme.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/sync/presentation/sync_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Application Widget
///
/// The root widget owns:
/// - the [ProviderScope] (application dependency-injection boundary),
/// - the stable GoRouter instance (via [appRouterProvider]),
/// - the locked BrewFlow theme (appearance preference from settings),
/// - the sync session lifecycle (device registration; Phase 6).
///
/// Bootstrap initialization (environment, storage, Supabase) completes before
/// this widget is mounted and is NOT duplicated here.
/// ---------------------------------------------------------------------------

class BrewFlowApp extends StatelessWidget {
  const BrewFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(child: const _AppView());
  }
}

class _AppView extends ConsumerWidget {
  const _AppView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the sync session alive for the app lifetime. Signed-out sessions
    // stay idle: no database or cloud traffic happens without a profile.
    ref.watch(syncSessionProvider);

    return MaterialApp.router(
      title: 'BrewFlow POS',
      debugShowCheckedModeBanner: false,

      themeMode: ref.watch(appThemeModeProvider),

      theme: AppTheme.light,
      darkTheme: AppTheme.dark,

      routerConfig: ref.watch(appRouterProvider),
    );
  }
}
