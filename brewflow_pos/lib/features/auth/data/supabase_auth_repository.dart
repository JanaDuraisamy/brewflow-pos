import 'dart:async';
import 'dart:io';

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
/// ---------------------------------------------------------------------------

final class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository({required SupabaseClient client})
    : _auth = client.auth;

  final GoTrueClient _auth;

  @override
  AuthUser? get currentUser => _toUser(_auth.currentUser);

  @override
  Stream<AuthUser?> get authStateChanges => _auth.onAuthStateChange
      .map((event) => _toUser(event.session?.user))
      .distinct(_sameUser);

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

  static AuthUser? _toUser(User? user) =>
      user == null ? null : AuthUser(id: user.id, email: user.email ?? '');

  static bool _sameUser(AuthUser? first, AuthUser? second) =>
      first?.id == second?.id && first?.email == second?.email;
}
