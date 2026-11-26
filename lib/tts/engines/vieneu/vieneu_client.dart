import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_log.dart';
import '../../audio/wav_codec.dart';

/// Adapter for the OpenAI-compatible `POST /v1/audio/speech` endpoint exposed
/// by the official VieNeu v3 Turbo server.
class VieNeuTtsClient {
  VieNeuTtsClient({
    required String baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 120),
  }) : baseUrl = _normalize(baseUrl),
       _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;
  final Duration timeout;

  static String _normalize(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Uri? get _speechUri {
    if (baseUrl.isEmpty) return null;
    final base = Uri.parse(baseUrl);
    final path = base.path.endsWith('/v1')
        ? '${base.path}/audio/speech'
        : '${base.path}/v1/audio/speech';
    return base.replace(path: path);
  }

  Future<bool> health({String? token}) async {
    if (baseUrl.isEmpty) return false;
    final base = Uri.parse(baseUrl);
    final path = base.path.endsWith('/v1')
        ? '${base.path}/health'
        : '${base.path}/health';
    try {
      final response = await _http
          .get(base.replace(path: path), headers: _headers(token ?? ""))
          .timeout(const Duration(seconds: 5));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  Future<List<String>> voices({String? token}) async {
    if (baseUrl.isEmpty) return const [];
    final base = Uri.parse(baseUrl);
    final path = base.path.endsWith('/v1')
        ? '${base.path}/voices'
        : '${base.path}/v1/voices';
    try {
      final response = await _http
          .get(base.replace(path: path), headers: _headers(token ?? ""))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const [];
      }
      final decoded = jsonDecode(response.body);
      return _extractVoiceNames(decoded);
    } catch (_) {
      return const [];
    }
  }

  List<String> _extractVoiceNames(Object? decoded) {
    final names = <String>[];
    void add(Object? value) {
      if (value is String && value.trim().isNotEmpty) {
        names.add(value.trim());
      }
    }

    void walk(Object? node) {
      if (node is List) {
        for (final item in node) {
          walk(item);
        }
      } else if (node is Map) {
        for (final key in const ['name', 'id', 'voice']) {
          add(node[key]);
        }
        for (final key in const ['voices', 'data', 'items']) {
          if (node[key] is List) walk(node[key]);
        }
      }
    }

    walk(decoded);
    return names.toSet().toList(growable: false);
  }

  Future<Uint8List> synthesize({
    required String text,
    required String voice,
    required String token,
  }) async {
    final uri = _speechUri;
    if (uri == null) {
      throw const AppException(
        AppErrorKind.unsupported,
        'Set your VieNeu server URL in Settings.',
      );
    }
    if (text.trim().isEmpty) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'Enter some text to synthesize.',
      );
    }
    try {
      final response = await _http
          .post(
            uri,
            headers: {
              ..._headers(token),
              'Content-Type': 'application/json',
              'Accept': 'audio/wav',
            },
            body: jsonEncode({
              'model': 'vieneu-v3-turbo',
              'input': text,
              'voice': voice,
              'response_format': 'wav',
            }),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw _mapError(response);
      }
      final bytes = response.bodyBytes;
      if (!WavCodec.isWav(bytes)) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'VieNeu did not return a WAV file. Check the server response format.',
        );
      }
      return bytes;
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException(
        AppErrorKind.network,
        'VieNeu server timed out.',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'Cannot reach the VieNeu server.',
        detail: error.message,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'VieNeu network request failed.',
        detail: error.message,
        retryable: true,
      );
    }
  }

  Map<String, String> _headers(String token) => {
    'Accept': 'application/json',
    if (token.trim().isNotEmpty) 'Authorization': 'Bearer ${token.trim()}',
  };

  AppException _mapError(http.Response response) {
    var message = response.body;
    if (message.length > 300) message = message.substring(0, 300);
    message = AppLog.redact(message);
    switch (response.statusCode) {
      case 401:
      case 403:
        return AppException(
          AppErrorKind.unauthorized,
          'VieNeu server rejected the token.',
          detail: message,
        );
      case 404:
        return AppException(
          AppErrorKind.unsupported,
          'VieNeu speech endpoint not found. Check the server URL.',
          detail: message,
        );
      case 429:
        return AppException(
          AppErrorKind.rateLimited,
          'VieNeu server is busy. Try again shortly.',
          detail: message,
          retryable: true,
        );
      default:
        return AppException(
          response.statusCode >= 500
              ? AppErrorKind.server
              : AppErrorKind.invalidRequest,
          'VieNeu request failed (${response.statusCode}).',
          detail: message,
          retryable: response.statusCode >= 500,
        );
    }
  }

  void close() => _http.close();
}
