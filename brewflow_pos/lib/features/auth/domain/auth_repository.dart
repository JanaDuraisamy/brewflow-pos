/// ---------------------------------------------------------------------------
/// BrewFlow POS — Authentication Domain
///
/// Application-level authentication contract. No Supabase/Gotrue types leak
/// beyond this boundary: UI and state layers depend only on the models and
/// failures defined here.
/// ---------------------------------------------------------------------------
library;

/// An authenticated user as seen by the application (safe contact data only).
final class AuthUser {
  const AuthUser({required this.id, required this.email});

  final String id;
  final String email;
}

/// A safe, user-facing authentication failure.
///
/// Never carries backend messages, tokens or credentials.
sealed class AuthFailure {
  const AuthFailure();

  /// Message safe to show directly to the user.
  String get message;
}

/// Wrong email/password combination.
final class InvalidCredentialsFailure extends AuthFailure {
  const InvalidCredentialsFailure();

  @override
  String get message => 'Incorrect email or password. Please try again.';
}

/// The authentication server could not be reached.
final class NetworkFailure extends AuthFailure {
  const NetworkFailure();

  @override
  String get message =>
      'Cannot reach the server. Check your connection and try again.';
}

/// Any other failure that is safe to show generically.
final class UnexpectedAuthFailure extends AuthFailure {
  const UnexpectedAuthFailure();

  @override
  String get message => 'Sign-in failed. Please try again.';
}

/// Contract for authentication operations.
///
/// Implementations wrap a concrete provider (Supabase). The stream emits the
/// current user whenever authentication state changes (including the initial
/// persisted session), with `null` meaning signed out; identical states are
/// deduplicated.
abstract interface class AuthRepository {
  /// The currently authenticated user, or `null` when signed out.
  AuthUser? get currentUser;

  /// Stream of authentication state changes.
  Stream<AuthUser?> get authStateChanges;

  /// Signs in with email and password.
  ///
  /// Throws an [AuthFailure] mapped to a safe application-level failure on
  /// error. On success the state change is observable via [authStateChanges].
  Future<void> signInWithEmailAndPassword({
    required String email,
    required String password,
  });

  /// Signs out the current session.
  Future<void> signOut();
}
