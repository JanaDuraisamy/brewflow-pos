import 'dart:async';
import 'dart:io';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Supabase Authentication Repository
///
/// The only place in the app that talks to the Supabase auth client. Uses the
/// client already initialized during bootstrap — never initializes a second
/// one. Session persistence is left entirely to Supabase Auth; this layer
/// never stores or exposes tokens.
///
/// Failures are mapped to safe domain [AuthFailure]s; raw backend errors are
/// never surfaced to callers.
///
/// Connectivity resilience: GoTrue's auto token-refresh reports a lost
/// network as a STREAM ERROR on `onAuthStateChange` (via `notifyException`)
/// while the session itself stays valid. [authStateChanges] therefore absorbs
/// those errors and keeps emitting the live session, so a transient drop in
/// connectivity can never look like a sign-out. Only a genuinely cleared
/// session (user-initiated sign-out or a server-invalidated refresh token)
/// surfaces as `null`.
/// ---------------------------------------------------------------------------

final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required SupabaseClient client})
    : _auth = client.auth;

  static const String tag = 'Auth';

  final GoTrueClient _auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges {
    late final StreamController<AuthUser?> controller;
    late final StreamSubscription<AuthState> subscription;

    controller = StreamController<AuthUser?>.broadcast(
      onListen: () {
        AuthUser? last = _toUser(_auth.currentUser);
        controller.add(last);
        subscription = _auth.onAuthStateChange.listen(
          (event) {
            final user = _toUser(event.session?.user);
            if (user != null) {
              last = user;
              controller.add(user);
              return;
            }
            // signedOut / no-session event. Propagate a sign-out ONLY when
            // the SDK actually cleared the session. After a transiently
            // failed refresh the session is still alive, so keep reporting
            // the live user instead of a fake sign-out.
            final liveUser = _toUser(_auth.currentUser);
            if (liveUser == null) {
              last = null;
              controller.add(null);
            } else if (!_sameUser(last, liveUser)) {
              last = liveUser;
              controller.add(liveUser);
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            // A retryable platform/network failure during token refresh
            // arrives as a stream error while the session stays valid. Never
            // translate that into an unauthenticated state.
            AppLog.warning(
              'Auth stream transient failure; session retained',
              tag: tag,
              error: error,
              stackTrace: stackTrace,
            );
            final liveUser = _toUser(_auth.currentUser);
            if (liveUser != null && !_sameUser(last, liveUser)) {
              last = liveUser;
              controller.add(liveUser);
            }
          },
        );
      },
      onCancel: () => subscription.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on AuthException catch (error) {
      throw switch (error.code) {
        'invalid_credentials' => const InvalidCredentialsFailure(),
        _ => const UnexpectedAuthFailure(),
      };
    } on SocketException {
      throw const NetworkFailure();
    } on TimeoutException {
      throw const NetworkFailure();
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> recoverSession() async {
    try {
      await _auth.refreshSession();
    } on Exception catch (error, stackTrace) {
      // Best-effort: the SDK auto-refresh retries on its own timer, so a
      // failed explicit recovery is never a reason to surface anything.
      AppLog.warning(
        'Auth session recovery failed (auto-refresh will retry)',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email ?? '');

  static bool _sameUser(AuthUser? first, AuthUser? second) =>
      first?.id == second?.id && first?.email == second?.email;
}
