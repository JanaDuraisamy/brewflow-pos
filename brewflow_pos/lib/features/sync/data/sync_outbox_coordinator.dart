import 'dart:convert';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/sync/data/drift_sync_repository.dart';
import 'package:brewflow_pos/features/sync/domain/master_data_models.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Sync Outbox Coordinator
///
/// Bridges business repositories and the durable outbox ATOMICALLY:
///
///   transaction {
///     business writes            ← unchanged repository logic
///     snapshots = describe rows  ← typed wire payloads from REAL state
///     outbox += appends          ← durable intent to push
///   }                            ← crash before here = nothing queued,
///                                 crash after = both present. Never split.
///
/// When no sync session context resolves (signed-out, legacy, or tests that
/// did not provide a resolver), [run] degrades to plain writes — the POS is
/// offline-first and NEVER depends on sync being available.
///
/// Deterministic outbox ids ('obx|shop|op|entity|id') make replays of the
/// SAME pending logical change collapse onto one row (identity index), while
/// a NEW change after completion enqueues freshly.
/// ---------------------------------------------------------------------------

/// One outbox append produced by a completed business write.
final class OutboxAppend {
  const OutboxAppend({
    required this.entity,
    required this.entityId,
    this.operation = 'UPSERT',
    required this.payload,
  });

  final MasterEntity entity;
  final String entityId;
  final String operation;

  /// Wire-model JSON map (see master_data_models.dart contract).
  final Map<String, dynamic> payload;
}

/// Resolves the active session triple, or null when sync cannot run.
typedef SyncContextResolver = Future<SyncSessionContext?> Function();

final class SyncSessionContext {
  const SyncSessionContext({
    required this.deviceId,
    required this.shopId,
    required this.userId,
  });

  final String deviceId;
  final String shopId;
  final String userId;
}

final class SyncOutboxCoordinator {
  SyncOutboxCoordinator(this._sync, this._resolveContext, {this.onEnqueue});

  final DriftSyncRepository _sync;
  final SyncContextResolver _resolveContext;

  /// Fired (fire-and-forget, after the transaction commits) whenever at
  /// least one outbox row was appended — the hook that makes FAST SYNC
  /// possible without repositories knowing anything about the engine.
  final void Function()? onEnqueue;

  /// Runs [write], asks [snapshots] to describe every affected row from the
  /// just-written state, and appends their outbox rows IN THE SAME
  /// TRANSACTION. Snapshot callbacks receive the resolved [context] so
  /// payloads can carry the session's shop scope; they may legitimately
  /// return an empty list (nothing to sync for that path).
  Future<T> run<T>({
    required Future<T> Function() write,
    required Future<List<OutboxAppend>> Function(
      T result,
      SyncSessionContext context,
    )
    snapshots,
  }) async {
    final context = await _safeResolveContext();
    if (context == null) {
      // Offline-first degradation: pure local write, no queue entry.
      return write();
    }
    return _sync
        .runInTransaction(() async {
          final result = await write();
          final appends = await snapshots(result, context);
          for (final append in appends) {
            await _sync.insertOutbox(
              SyncOutboxEntry(
                id: _deterministicId(context, append),
                deviceId: context.deviceId,
                shopId: context.shopId,
                entity: append.entity.wire,
                entityId: append.entityId,
                operation: append.operation,
                payload: jsonEncode(append.payload),
                status: 'PENDING',
                attemptCount: 0,
              ),
            );
          }
          return result;
        })
        .whenComplete(() {
          // Committed (or rolled back with nothing queued): nudge the engine.
          // Fire-and-forget — never blocks or fails the business write.
          if (onEnqueue != null) onEnqueue!();
        });
  }

  /// Deterministic per logical change; replays collapse while PENDING.
  static String _deterministicId(
    SyncSessionContext context,
    OutboxAppend append,
  ) => [
    'obx',
    context.shopId,
    append.operation,
    append.entity.wire,
    append.entityId,
  ].join('|');

  Future<SyncSessionContext?> _safeResolveContext() async {
    try {
      return await _resolveContext();
    } catch (error, stackTrace) {
      AppLog.warning(
        'Sync context unavailable — writing locally only',
        tag: 'Sync/Hook',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}
