import 'package:flutter/foundation.dart';

/// Logger centralizado de BiPenc.
/// En modo release no emite nada. En debug imprime con nivel y emoji.
/// Soporta 5 niveles: debug, info, warning, error, critical
class AppLogger {
  AppLogger._();

  static void debug(String message, {String? tag}) {
    if (kDebugMode) {
      _log('🔵 DEBUG', tag, message);
    }
  }

  static void info(String message, {String? tag}) {
    if (kDebugMode) {
      _log('✅ INFO', tag, message);
    }
  }

  static void warning(String message, {String? tag}) {
    if (kDebugMode) {
      _log('🟡 WARN', tag, message);
    }
  }

  static void error(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _log('🔴 ERROR', tag, message);
      if (error != null) debugPrint('   ↳ Error: $error');
      if (stackTrace != null) {
        debugPrint('   ↳ Stack:');
        debugPrint(stackTrace.toString());
      }
    }
  }

  static void warn(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    // Alias para warning con soporte a error/stackTrace
    warning(message, tag: tag);
    if (error != null) {
      if (kDebugMode) {
        debugPrint('   ↳ Error: $error');
        if (stackTrace != null) debugPrint(stackTrace.toString());
      }
    }
  }

  /// Nivel CRÍTICO: Para errores no manejados que pueden causar crash
  static void critical(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      _log('🔴🔴 CRITICAL', tag, message);
      if (error != null) debugPrint('   ↳ Error: $error');
      if (stackTrace != null) {
        debugPrint('   ↳ Stack Trace:');
        final lines = stackTrace.toString().split('\n');
        for (final line in lines.take(15)) {
          // Primeras 15 líneas del stack
          if (line.isNotEmpty) debugPrint('      $line');
        }
      }
    }
  }

  static void _log(String level, String? tag, String message) {
    final tagStr = tag != null ? ' [$tag]' : '';
    debugPrint('$level$tagStr $message');
  }
}
