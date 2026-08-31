import 'dart:async';

import 'package:brewflow_pos/features/auth/domain/auth_repository.dart';

/// In-memory [AuthRepository] for tests. Drive authentication events manually
/// with [emit]; probe results configure sign-in behavior.
final class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.user}) {
    _controller = StreamController<AuthUser?>.broadcast(
      onListen: () => listenCount++,
    );
  }

  /// Current user returned synchronously by [currentUser].
  AuthUser? user;

  /// Failure thrown by the next sign-in attempt.
  AuthFailure? signInError;

  /// Any other error thrown by the next sign-in attempt.
  Object? signInRawError;

  /// When set, sign-in waits for this before completing (loading tests).
  Completer<void>? signInGate;

  /// Records of every sign-in call: (email, password).
  final List<(String, String)> signIns = [];

  /// Number of [signOut] calls.
  int signOutCalls = 0;

  /// Number of times the state stream was listened to.
  int listenCount = 0;

  late final StreamController<AuthUser?> _controller;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  /// Emits an authentication event to listeners.
  void emit(AuthUser? next) => _controller.add(next);

  /// Emits an error event to listeners (broken auth stream simulations).
  void emitError(Object error) => _controller.addError(error);

  @override
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    signIns.add((email, password));
    final gate = signInGate;
    if (gate != null) {
      await gate.future;
    }
    final rawError = signInRawError;
    if (rawError != null) {
      throw rawError;
    }
    final failure = signInError;
    if (failure != null) {
      throw failure;
    }
    user = AuthUser(id: 'user-1', email: email);
    _controller.add(user);
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
    user = null;
    _controller.add(null);
  }
}
