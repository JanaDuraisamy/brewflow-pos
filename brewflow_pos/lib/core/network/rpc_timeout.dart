import 'dart:async';

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
Future<T> rpcWithTimeout<T>(
  Future<T> Function() call, {
  Duration timeout = kRpcTimeout,
}) => call().timeout(timeout);
