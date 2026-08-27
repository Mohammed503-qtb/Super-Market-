import 'package:flutter/foundation.dart';

/// نظام تسجيل الأحداث الداخلي
class AppLogger {
  static final List<LogEntry> _entries = [];
  static const int _maxEntries = 500;

  static List<LogEntry> get entries => List.unmodifiable(_entries);

  static void info(String message, {String? tag}) =>
      _log(LogLevel.info, message, tag);

  static void warning(String message, {String? tag}) =>
      _log(LogLevel.warning, message, tag);

  static void error(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    _log(LogLevel.error, message, tag);
    if (kDebugMode) {
      debugPrint('ERROR: $message');
      if (error != null) debugPrint('   Error: $error');
      if (stackTrace != null) debugPrint('   Stack: $stackTrace');
    }
  }

  static void database(String message) => _log(LogLevel.database, message, 'DB');

  static void auth(String message) => _log(LogLevel.auth, message, 'AUTH');

  static void accounting(String message) =>
      _log(LogLevel.accounting, message, 'ACCOUNTING');

  static void inventory(String message) =>
      _log(LogLevel.inventory, message, 'INVENTORY');

  static void _log(LogLevel level, String message, String? tag) {
    final entry = LogEntry(
      level: level,
      message: message,
      tag: tag,
      timestamp: DateTime.now(),
    );
    _entries.insert(0, entry);
    if (_entries.length > _maxEntries) {
      _entries.removeLast();
    }
    if (kDebugMode) {
      debugPrint('${entry.level.prefix} ${entry.tag ?? ''}: $message');
    }
  }

  static void clear() => _entries.clear();
}

enum LogLevel { info, warning, error, database, auth, accounting, inventory }

extension LogLevelX on LogLevel {
  String get prefix {
    switch (this) {
      case LogLevel.info:
        return 'ℹ️';
      case LogLevel.warning:
        return '⚠️';
      case LogLevel.error:
        return '❌';
      case LogLevel.database:
        return '🗄️';
      case LogLevel.auth:
        return '🔐';
      case LogLevel.accounting:
        return '💰';
      case LogLevel.inventory:
        return '📦';
    }
  }

  String get name {
    switch (this) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARNING';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.database:
        return 'DATABASE';
      case LogLevel.auth:
        return 'AUTH';
      case LogLevel.accounting:
        return 'ACCOUNTING';
      case LogLevel.inventory:
        return 'INVENTORY';
    }
  }
}

class LogEntry {
  final LogLevel level;
  final String message;
  final String? tag;
  final DateTime timestamp;

  LogEntry({
    required this.level,
    required this.message,
    this.tag,
    required this.timestamp,
  });
}
