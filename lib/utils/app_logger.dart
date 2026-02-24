import 'package:flutter/foundation.dart';

/// Logger centralizado de BiPenc.
/// En modo release no emite nada. En debug imprime con nivel y emoji.
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

  static void error(String message, {String? tag, Object? error}) {
    if (kDebugMode) {
      _log('🔴 ERROR', tag, message);
      if (error != null) debugPrint('   ↳ $error');
    }
  }

  static void _log(String level, String? tag, String message) {
    final tagStr = tag != null ? ' [$tag]' : '';
    debugPrint('$level$tagStr $message');
  }
}
