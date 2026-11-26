import 'package:flutter/foundation.dart';

/// Debug logging with secret redaction.
///
/// Nothing in the app logs request headers or full request bodies. This helper
/// additionally scrubs credential-shaped strings as a second line of defence.
class AppLog {
  const AppLog._();

  static final RegExp _googleKey = RegExp(r'AIza[0-9A-Za-z_\-]{20,}');
  static final RegExp _queryKey = RegExp(r'(key=)[^&\s]+');
  static final RegExp _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._\-]+');

  static String redact(String message) => message
      .replaceAll(_googleKey, 'AIza****')
      .replaceAll(_queryKey, 'key=****')
      .replaceAll(_bearer, 'Bearer ****');

  static void debug(String message) {
    if (kDebugMode) debugPrint('[TTS] ${redact(message)}');
  }

  static void error(String message, [Object? error]) {
    if (!kDebugMode) return;
    final suffix = error == null ? '' : ': ${redact(error.toString())}';
    debugPrint('[TTS][error] ${redact(message)}$suffix');
  }
}
