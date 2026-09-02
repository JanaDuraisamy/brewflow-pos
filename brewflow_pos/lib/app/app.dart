import 'dart:async';

import 'package:brewflow_pos/core/router/app_router.dart';
import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/core/theme/app_theme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:brewflow_pos/features/backup/domain/backup_scheduler.dart';
import 'package:brewflow_pos/features/backup/presentation/backup_providers.dart';
import 'package:brewflow_pos/features/settings/presentation/settings_controller.dart';
import 'package:brewflow_pos/features/staff/presentation/staff_controller.dart';
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

class _AppView extends ConsumerStatefulWidget {
  const _AppView();

  @override
  ConsumerState<_AppView> createState() => _AppViewState();
}

class _AppViewState extends ConsumerState<_AppView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Tablet sign-out investigation: when the OS kills the process and the
      // user reopens it, Supabase restores the session from storage during
      // bootstrap. If the JWT expired while the app was closed, the SDK must
      // refresh it. Auto-refresh relies on foreground timers that were not
      // running while closed, so trigger an explicit refresh best-effort.
      // Never sign the user out on a transient network failure — the next
      // periodic cycle or connectivity restore will retry.
      unawaited(_refreshSessionIfNeeded());
    }
  }

  Future<void> _refreshSessionIfNeeded() async {
    try {
      final client = await _supabaseClientIfReady();
      if (client == null) return;
      final session = client.auth.currentSession;
      if (session == null) return;
      // Session exists — trigger a best-effort refresh. The SDK is idempotent;
      // if the JWT is still valid the call is cheap, if expired it rotates.
      // Offline or transient failures are logged and retried on next resume
      // or periodic sync; the user is never signed out on a network blip.
      await client.auth.refreshSession();
      AppLog.info('Auth session refreshed on resume', tag: 'Auth');
    } catch (error, stackTrace) {
      AppLog.warning(
        'Auth refresh on resume skipped (will retry)',
        tag: 'Auth',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<dynamic> _supabaseClientIfReady() async {
    try {
      // Supabase may not be initialized in tests; guard via try/catch.
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Keeps the sync session alive for the app lifetime. Signed-out sessions
    // stay idle: no database or cloud traffic happens without a profile.
    ref.watch(syncSessionProvider);

    return _AutoBackupGate(
      child: MaterialApp.router(
        title: 'BrewFlow POS',
        debugShowCheckedModeBanner: false,

        themeMode: ref.watch(appThemeModeProvider),

        theme: AppTheme.light,
        darkTheme: AppTheme.dark,

        routerConfig: ref.watch(appRouterProvider),
      ),
    );
  }
}

/// Fires the once-per-day automatic backup as soon as a shop profile is
/// available. Runs silently and never blocks or interrupts the UI: the
/// scheduler never throws, provider reads resolve lazily, and the run is
/// triggered exactly once per shop profile.
final class _AutoBackupGate extends ConsumerWidget {
  const _AutoBackupGate({required this.child});

  /// Shops for which a backup run has already been scheduled this process.
  static final Set<String> _scheduledShops = <String>{};

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    if (profile != null && profile.shopId != null) {
      _scheduleOnce(ref, profile.shopId!);
    }
    return child;
  }

  void _scheduleOnce(WidgetRef ref, String shopId) {
    if (!_scheduledShops.add(shopId)) return;
    unawaited(() async {
      try {
        final scheduler = await ref.read(dailyBackupSchedulerProvider.future);
        final result = await scheduler.run();
        if (result is AutoBackupCreated) {
          AppLog.info('Automatic daily backup created', tag: 'Backup');
        }
      } on Object {
        // Auto-backup is best-effort: never let it interrupt startup.
      }
    }());
  }
}
