/// ---------------------------------------------------------------------------
/// BrewFlow POS — Structured Runtime Tracing
///
/// A thin, debug-oriented trace layer over the existing [AppLog]. This is NOT a
/// second logger: every line is emitted through `AppLog`, so it inherits the
/// level gating, the custom printer and the secret redactor. One marker is used
/// for all of it, so a single Logcat filter captures the whole story:
///
///   `adb logcat flutter:I *:S | grep BREWFLOW`
///
/// Shape: `event key=value key=value`
///
/// ```text
/// BREWFLOW boot.step step=supabase
/// BREWFLOW sale.ok shop=<uuid> receipt=BF-000042 totalPaise=27800 ms=412
/// ```
///
/// Design rules:
/// - TRACE MEANINGFUL EVENTS, NOT RENDER CYCLES. A widget rebuild, a keystroke
///   or a provider read is never traced. Call sites are placed at state
///   transitions and I/O boundaries, where a log line is the difference
///   between a reproducible bug and a guess.
/// - NEVER LOG SECRETS OR PERSONAL DATA. [fields] keys are screened against a
///   credential/PII denylist before formatting, values are truncated, and the
///   whole line then passes through `AppLog`'s own redactor. Passing a raw
///   password or token is a defect in the call site, but the denylist is the
///   backstop that keeps a mistake from reaching a device log.
/// - Behaviour-neutral. Tracing only observes; it never changes a return value,
///   an ordering, or a failure path.
/// ---------------------------------------------------------------------------
library;

import 'dart:convert';

import 'package:brewflow_pos/core/services/app_log.dart';
import 'package:crypto/crypto.dart';

/// The single Logcat marker for every trace line.
const String kAppTraceTag = 'BREWFLOW';

final class AppTrace {
  AppTrace._();

  /// Compile-time kill switch, e.g. `--dart-define=BREWFLOW_TRACE=false`.
  ///
  /// Defaults to ON in every flavor, including production. That is deliberate:
  /// the failures this exists to diagnose only reproduce on real devices in
  /// real shops, where a debug-only level would be compiled out by
  /// [AppLog.minLevel]. Volume is kept low by the event-selection rule above,
  /// not by hiding the output.
  static const bool _enabled = bool.fromEnvironment(
    'BREWFLOW_TRACE',
    defaultValue: true,
  );

  /// Whether tracing would emit anything. Callers may use this to skip work
  /// that exists only to build a trace payload.
  static bool get enabled => _enabled;

  /// Longest single field value kept in a line.
  static const int _maxValueLength = 120;

  /// Field keys whose values are never printed. Compared after normalization
  /// (lowercased, `_`/`-` removed): an exact match, or a substring match for
  /// keys of four characters or more so short keys cannot over-match.
  static const Set<String> _deniedKeys = {
    // Credentials / tokens.
    'password',
    'passwd',
    'pwd',
    'pass',
    'token',
    'accesstoken',
    'refreshtoken',
    'idtoken',
    'bearertoken',
    'secret',
    'clientsecret',
    'apikey',
    'apisecret',
    'anonkey',
    'publishablekey',
    'authorization',
    'auth',
    'credential',
    'credentials',
    'privatekey',
    'jwt',
    'cookie',
    'signature',
    // Personal data.
    'email',
    'phone',
    'address',
    'otp',
    'cvv',
    'pin',
    'ssn',
  };

  /// A short, non-reversible stand-in for a user identity.
  ///
  /// Signing in needs a correlation handle — without one, `auth.sign_in` and
  /// the `shop.switch` that follows it cannot be tied to the same operator —
  /// but the identity itself (an email address) must never reach a device log.
  /// A truncated SHA-256 gives a stable handle within and across runs that
  /// cannot be walked back to the address: 32 bits of a digest over a
  /// high-entropy-unique value, not a reversible encoding.
  ///
  /// Also applied to the Supabase user id, so no call site can leak either by
  /// reaching for `.id`/`.email` directly.
  static String userRef(String? identity) {
    if (identity == null || identity.isEmpty) return '<none>';
    final digest = sha256.convert(utf8.encode(identity));
    return digest.toString().substring(0, 8);
  }

  /// Records a meaningful application event.
  ///
  /// [name] is a stable dotted identifier such as `sale.ok` or
  /// `shop.switch`; grep for it directly. [fields] carries the context needed
  /// to reproduce the flow. Null values are omitted, so an absent value never
  /// prints as the string "null".
  static void event(String name, [Map<String, Object?> fields = const {}]) {
    if (!_enabled) return;
    AppLog.info(_format(name, fields), tag: kAppTraceTag);
  }

  /// Records a recoverable problem: a retry, a degraded path, or an operation
  /// that completed but not the way it normally does.
  static void warn(String name, [Map<String, Object?> fields = const {}]) {
    if (!_enabled) return;
    AppLog.warning(_format(name, fields), tag: kAppTraceTag);
  }

  /// Records a failure that aborted an operation.
  ///
  /// The error and stack trace are handed to [AppLog], which redacts them
  /// before printing, so an exception carrying a credential is still masked.
  static void fail(
    String name,
    Object error, [
    StackTrace? stackTrace,
    Map<String, Object?> fields = const {},
  ]) {
    if (!_enabled) return;
    AppLog.error(
      _format(name, {...fields, 'err': error.runtimeType.toString()}),
      tag: kAppTraceTag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Renders `name key=value …`.
  ///
  /// Public so the field-screening and truncation rules — the security
  /// relevant part of this file — can be asserted directly by tests.
  static String format(String name, Map<String, Object?> fields) =>
      _format(name, fields);

  static String _format(String name, Map<String, Object?> fields) {
    if (fields.isEmpty) return name;
    final buffer = StringBuffer(name);
    for (final entry in fields.entries) {
      final value = entry.value;
      if (value == null) continue;
      buffer
        ..write(' ')
        ..write(_fieldName(entry.key))
        ..write('=')
        ..write(_fieldValue(entry.key, value));
    }
    return buffer.toString();
  }

  static String _fieldName(String key) {
    final screened = _isDenied(key) ? '<denied>' : key;
    return screened.replaceAll(RegExp(r'\s+'), '_');
  }

  static String _fieldValue(String key, Object value) {
    if (_isDenied(key)) return '<redacted>';
    final text = value is Duration
        ? '${value.inMilliseconds}ms'
        : value.toString();
    // Newlines would break the one-event-per-line shape that makes the output
    // greppable, so they are folded rather than printed.
    final flattened = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flattened.isEmpty) return '""';
    if (flattened.length <= _maxValueLength) return flattened;
    return '${flattened.substring(0, _maxValueLength)}…';
  }

  static bool _isDenied(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\-.\s]'), '');
    if (normalized.isEmpty) return true;
    if (_deniedKeys.contains(normalized)) return true;
    return _deniedKeys.any(
      (denied) => denied.length >= 4 && normalized.contains(denied),
    );
  }
}
