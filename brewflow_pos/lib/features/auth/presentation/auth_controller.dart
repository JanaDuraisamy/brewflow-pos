import 'dart:async';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:brewflow_pos/features/auth/data/supabase_auth_repository.dart';
import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';
import 'package:brewflow_pos/features/billing/presentation/billing_controller.dart';
import 'package:brewflow_pos/features/purchases/presentation/purchase_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Authentication State (Riverpod)
///
/// Owns the single authentication subscription for the app: the repository's
/// state stream is listened exactly once, here, and disposed with the scope —
/// no duplicate listeners anywhere.
///
/// Initial resolution: the repository exposes the persisted session
/// synchronously (Supabase already recovered it during bootstrap), and its
/// stream replays the latest authentication event. Until then the state is
/// [AuthStatus.initializing], which lets the router keep the splash visible
/// without artificial delays.
/// ---------------------------------------------------------------------------

/// Application authentication status.
enum AuthStatus {
  /// Not resolved yet (startup).
  initializing,

  /// A user session is active.
  authenticated,

  /// No session.
  unauthenticated,

  /// The last authentication attempt failed.
  error,
}

/// Immutable authentication state exposed to the UI.
final class AuthState {
  const AuthState._({
    required this.status,
    this.userEmail,
    this.failure,
    this.signingIn = false,
  });

  final AuthStatus status;
  final String? userEmail;
  final AuthFailure? failure;

  /// True while a sign-in attempt is in flight (submission protection).
  final bool signingIn;

  static const AuthState initializing = AuthState._(
    status: AuthStatus.initializing,
  );

  static const AuthState unauthenticated = AuthState._(
    status: AuthStatus.unauthenticated,
  );

  static AuthState authenticated({required String email}) =>
      AuthState._(status: AuthStatus.authenticated, userEmail: email);

  static AuthState error(AuthFailure failure) =>
      AuthState._(status: AuthStatus.error, failure: failure);

  /// A copy of this state with a sign-in attempt in progress.
  AuthState asSigningIn() =>
      AuthState._(status: status, userEmail: userEmail, signingIn: true);
}

/// Composition root: the single repository wired to the bootstrap-initialized
/// Supabase client. Override in tests with a fake repository.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return SupabaseAuthRepository(client: Supabase.instance.client);
});

/// The application authentication state controller.
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

final class AuthController extends Notifier<AuthState> {
  static const String tag = 'Auth';

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);

    // Single subscription for the whole app; cancelled on scope disposal.
    // Stream errors are absorbed into a safe error state so a broken auth
    // stream can never surface as an unhandled exception.
    final subscription = repository.authStateChanges.listen(
      _applyAuthUser,
      onError: (Object error, StackTrace stackTrace) {
        AppLog.error(
          'Auth state stream failed',
          tag: tag,
          error: error,
          stackTrace: stackTrace,
        );
        state = AuthState.error(const UnexpectedAuthFailure());
      },
    );
    ref.onDispose(subscription.cancel);

    final current = repository.currentUser;
    if (current != null) {
      return AuthState.authenticated(email: current.email);
    }
    return AuthState.initializing;
  }

  /// Signs in with email and password.
  ///
  /// Duplicate submissions while a sign-in is in flight are ignored. On
  /// success the state follows the repository stream; on failure the state
  /// becomes [AuthStatus.error] with a safe [AuthFailure].
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    if (state.signingIn) {
      return;
    }
    state = state.asSigningIn();
    try {
      await ref
          .read(authRepositoryProvider)
          .signInWithEmailAndPassword(email: email, password: password);
      // Normally the stream event already switched the state; this is a
      // safety net if the event is delayed.
      final user = ref.read(authRepositoryProvider).currentUser;
      if (user != null) {
        _applyAuthUser(user);
      }
    } on AuthFailure catch (failure) {
      AppLog.error('Sign-in failed (${failure.runtimeType})', tag: tag);
      state = AuthState.error(failure);
    } catch (error, stackTrace) {
      AppLog.error(
        'Sign-in failed unexpectedly',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
      state = AuthState.error(const UnexpectedAuthFailure());
    }
  }

  /// Signs out the current session. Failures are logged and never surfaced
  /// through the UI (sign-out is best-effort); the stream event flips the
  /// state back to unauthenticated. On success the in-memory state that
  /// belongs to the signed-in user (POS cart, filters, purchase draft) is
  /// reset so the next session starts clean.
  Future<void> signOut() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (ref.read(authRepositoryProvider).currentUser == null) {
        _applyAuthUser(null);
      }
      ref.invalidate(cartProvider);
      ref.invalidate(heldBillsProvider);
      ref.invalidate(posFilterProvider);
      ref.invalidate(purchaseFormProvider);
    } catch (error, stackTrace) {
      AppLog.error(
        'Sign-out failed',
        tag: tag,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _applyAuthUser(AuthUser? user) {
    if (user == null) {
      if (state.status != AuthStatus.unauthenticated) {
        AppLog.info('Auth state: signed out', tag: tag);
        state = AuthState.unauthenticated;
      }
      return;
    }
    if (state.status != AuthStatus.authenticated ||
        state.userEmail != user.email) {
      AppLog.info('Auth state: signed in', tag: tag);
      state = AuthState.authenticated(email: user.email);
    }
  }
}
