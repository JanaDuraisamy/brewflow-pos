import 'package:brewflow_pos/config/flavor.dart';
import 'package:logger/logger.dart';

/// ---------------------------------------------------------------------------
/// BrewFlow POS — Centralized Application Logger
///
/// Single logging entry point for the whole app. All layers (database,
/// network, auth, sync, UI) log through [AppLog] — never via `print`.
///
/// Behavior:
/// - Verbosity is flavor-driven: development logs from `debug` upward,
///   production from `info` upward.
/// - Output is emitted through the `logger` package's [ConsoleOutput];
///   this file never calls `print` directly.
/// - Secrets are redacted from output: JWTs / Supabase keys, bearer tokens
///   and credential assignments are masked before anything is printed.
///
/// Rules:
/// - NEVER log passwords, tokens, Supabase keys, session data or other
///   sensitive values. If a sensitive value must be mentioned, pass it
///   through [AppLog.redact].
/// ---------------------------------------------------------------------------

final class AppLog {
  AppLog._();

  /// Minimum level that reaches the output for the active flavor.
  static final Level minLevel = AppFlavor.current.isProduction
      ? Level.info
      : Level.debug;

  static final Logger _logger = Logger(
    filter: ProductionFilter(),
    level: minLevel,
    printer: _AppLogPrinter(),
    output: ConsoleOutput(),
  );

  /// Whether events at [level] would reach the output.
  static bool isLevelEnabled(Level level) => level >= minLevel;

  /// Replaces a sensitive value with a fixed safe marker.
  static String redact(Object? value) => '<redacted>';

  static void debug(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(Level.debug, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void info(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(Level.info, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void warning(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(
      Level.warning,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(Level.error, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  /// Logs [message] at an arbitrary [level] (e.g. `Level.trace`).
  static void log(
    Level level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _log(level, message, tag: tag, error: error, stackTrace: stackTrace);
  }

  static void _log(
    Level level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level == Level.all || level == Level.off) {
      throw ArgumentError.value(
        level,
        'level',
        'Only event levels (trace..fatal) can be logged',
      );
    }
    final tagged = tag == null || tag.isEmpty ? message : '[$tag] $message';
    _logger.log(level, tagged, error: error, stackTrace: stackTrace);
  }
}

/// Formats log events and applies secret redaction.
final class _AppLogPrinter extends LogPrinter {
  _AppLogPrinter();

  @override
  List<String> log(LogEvent event) {
    final lines = <String>[
      '${_timestamp(event.time)} '
          '${_levelLabel(event.level)} '
          '${_SecretRedactor.apply(event.message.toString())}',
    ];

    final error = event.error;
    if (error != null) {
      lines.add('      ${_SecretRedactor.apply(error.toString())}');
    }

    final stackTrace = event.stackTrace;
    if (stackTrace != null) {
      lines.addAll(
        stackTrace.toString().split('\n').map((line) => '      $line'),
      );
    }

    return lines;
  }

  String _levelLabel(Level level) => switch (level) {
    Level.trace => 'TRACE',
    Level.debug => 'DEBUG',
    Level.info => 'INFO ',
    Level.warning => 'WARN ',
    Level.error => 'ERROR',
    Level.fatal => 'FATAL',
    _ => 'LOG  ',
  };

  String _timestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.'
        '${three(time.millisecond)}';
  }
}

/// Masks credential-like fragments before they reach the output.
final class _SecretRedactor {
  const _SecretRedactor._();

  static const String _jwtMarker = '<jwt-redacted>';
  static const String _bearerMarker = '<bearer-redacted>';
  static const String _assignmentMarker = '<redacted>';

  /// Supabase anon key and any other JWT (`eyJ...`).
  static final RegExp _jwt = RegExp(
    r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+',
  );

  /// `Bearer <token>` / `bearer <token>`.
  static final RegExp _bearer = RegExp(
    r'\bbearer\s+[A-Za-z0-9._~+/=\-]+',
    caseSensitive: false,
  );

  /// `key=value` / `key: value` for well-known credential keys.
  static final RegExp _assignment = RegExp(
    r'\b(password|passwd|pwd|token|api[-_]?key|apikey|secret|'
    r'authorization|refresh[-_]?token|session[-_]?key)\s*[=:]\s*\S+',
    caseSensitive: false,
  );

  static String apply(String input) {
    var result = input.replaceAll(_jwt, _jwtMarker);
    result = result.replaceAll(_bearer, _bearerMarker);
    result = result.replaceAllMapped(
      _assignment,
      (match) => '${match.group(1)}=$_assignmentMarker',
    );
    return result;
  }
}
