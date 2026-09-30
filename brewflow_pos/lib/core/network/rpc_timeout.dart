import 'dart:async';

import 'package:brewflow_pos/core/services/app_trace.dart';

/// Default ceiling for a single Supabase RPC call in seconds.
///
/// The Supabase client (`PostgrestClient.rpc`) attaches no default timeout of
/// its own, so when a connection is left hanging the awaited future never
/// completes (QA: `create_sale_atomic` and `adjust_stock_atomic` blocked the
/// caller indefinitely). Every atomic RPC gateway in this app runs through
/// [rpcWithTimeout] so the UI/controller gets a clean [TimeoutException] the
/// repositories translate into a user-safe failure.
const Duration kRpcTimeout = Duration(seconds: 30);

/// Runs a single RPC [call] under a bounded [timeout].
///
/// A Dart timeout does NOT cancel the underlying HTTP socket — the server-side
/// statement/lock timeouts (migration 0015) are what actually release the
/// FOR UPDATE row locks a wedged call holds. The client timeout exists to free
/// the caller, never to replace the server guard.
///
/// Every Supabase call in the app funnels through here, which makes this the
/// one place worth tracing for network behaviour. Pass [name] as the RPC name
/// to get `rpc.begin` / `rpc.ok` / `rpc.fail` lines including the round-trip
/// duration — the only reliable way to tell a slow server from a wedged lock.
///
/// Tracing is observation-only: the returned future, the timeout and the
/// rethrown error are exactly what they were without it.
Future<T> rpcWithTimeout<T>(
  Future<T> Function() call, {
  Duration timeout = kRpcTimeout,
  String? name,
}) {
  if (name == null) return call().timeout(timeout);

  final stopwatch = Stopwatch()..start();
  AppTrace.event('rpc.begin', {
    'rpc': name,
    'timeoutMs': timeout.inMilliseconds,
  });
  return call()
      .timeout(timeout)
      .then(
        (value) {
          stopwatch.stop();
          AppTrace.event('rpc.ok', {
            'rpc': name,
            'ms': stopwatch.elapsedMilliseconds,
          });
          return value;
        },
        onError: (Object error, StackTrace stackTrace) {
          stopwatch.stop();
          final fields = {'rpc': name, 'ms': stopwatch.elapsedMilliseconds};
          // Branch rather than pick a tear-off: `warn` and `fail` have
          // different signatures, so a `(cond ? AppTrace.warn : AppTrace.fail)`
          // conditional silently resolves to `warn` and then blows up with a
          // NoSuchMethodError on the 3rd argument — replacing the real error
          // the caller is waiting to handle.
          if (error is TimeoutException) {
            AppTrace.warn('rpc.timeout', fields);
          } else {
            AppTrace.fail('rpc.fail', error, stackTrace, fields);
          }
          throw error;
        },
      );
}
