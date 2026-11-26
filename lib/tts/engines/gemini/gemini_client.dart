import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/app_log.dart';
import '../../audio/wav_codec.dart';

class GeminiConfig {
  const GeminiConfig({required this.baseUri, required this.model});

  static const String defaultBaseUrl =
      'https://generativelanguage.googleapis.com';
  static const String defaultModel = 'gemini-3.8-flash-tts';

  final Uri baseUri;
  final String model;

  bool get isBackendProxy =>
      baseUri.host != 'generativelanguage.googleapis.com';

  factory GeminiConfig.fromEnvironment() {
    const base = String.fromEnvironment(
      'GEMINI_API_BASE_URL',
      defaultValue: defaultBaseUrl,
    );
    const model = String.fromEnvironment(
      'GEMINI_TTS_MODEL',
      defaultValue: defaultModel,
    );
    return GeminiConfig(baseUri: Uri.parse(base), model: model);
  }
}

/// Thin REST client for the Gemini Interactions API speech-generation endpoint.
///
/// Request/response shapes follow the current official TTS guide:
/// `POST /v1beta/interactions` with `response_format: audio/wav`.
class GeminiTtsClient {
  GeminiTtsClient({
    http.Client? httpClient,
    GeminiConfig? config,
    this.timeout = const Duration(seconds: 120),
  }) : _http = httpClient ?? http.Client(),
       config = config ?? GeminiConfig.fromEnvironment();

  final http.Client _http;
  final GeminiConfig config;
  final Duration timeout;

  Uri _uri(String path, [Map<String, String>? query]) =>
      config.baseUri.replace(path: path, queryParameters: query);

  Future<void> validateKey(String apiKey) async {
    if (apiKey.trim().isEmpty && !config.isBackendProxy) {
      throw const AppException(
        AppErrorKind.unauthorized,
        'Enter a Gemini API key first.',
      );
    }
    final uri = _uri('/v1beta/models', {'pageSize': '1'});
    try {
      final response = await _http
          .get(uri, headers: _headers(apiKey))
          .timeout(timeout);
      _throwForStatus(response);
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'Unexpected response from the Gemini API.',
        );
      }
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException(
        AppErrorKind.network,
        'Gemini did not respond in time.',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'Cannot reach the Gemini API.',
        detail: error.message,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'Network request failed.',
        detail: error.message,
        retryable: true,
      );
    }
  }

  Future<Uint8List> synthesize({
    required String apiKey,
    required String text,
    required String voice,
    String? style,
  }) async {
    if (text.trim().isEmpty) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'The script is empty.',
      );
    }
    if (apiKey.trim().isEmpty && !config.isBackendProxy) {
      throw const AppException(
        AppErrorKind.unauthorized,
        'Enter a Gemini API key in Settings.',
      );
    }

    final annotations = <String, Object>{
      'type': 'speech_metadata',
      if (style != null && style.trim().isNotEmpty) 'style': style.trim(),
    };
    final body = <String, Object>{
      'model': config.model,
      'input': [
        {
          'type': 'user_input',
          'content': [
            {
              'type': 'text',
              'text': text,
              'annotations': [annotations],
            },
          ],
        },
      ],
      'response_format': {
        'type': 'audio',
        'mime_type': 'audio/wav',
        'sample_rate': 24000,
      },
      'generation_config': {
        'speech_config': [
          {'voice': voice},
        ],
      },
    };

    try {
      final response = await _http
          .post(
            _uri('/v1beta/interactions'),
            headers: {..._headers(apiKey), 'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
      _throwForStatus(response);

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'Gemini returned an unexpected response.',
        );
      }
      final base64Audio = _extractAudio(decoded);
      if (base64Audio == null) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'Gemini returned no audio block.',
        );
      }
      final bytes = base64Decode(base64Audio);
      if (!WavCodec.isWav(bytes)) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'Gemini returned audio that is not a WAV file.',
        );
      }
      return bytes;
    } on AppException {
      rethrow;
    } on FormatException catch (error) {
      throw AppException(
        AppErrorKind.malformedResponse,
        'Could not decode Gemini audio.',
        detail: error.message,
      );
    } on TimeoutException {
      throw const AppException(
        AppErrorKind.network,
        'Gemini speech generation timed out.',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'Cannot reach the Gemini API.',
        detail: error.message,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw AppException(
        AppErrorKind.network,
        'Network request failed.',
        detail: error.message,
        retryable: true,
      );
    }
  }

  Map<String, String> _headers(String apiKey) => {
    'Accept': 'application/json',
    if (apiKey.trim().isNotEmpty) 'x-goog-api-key': apiKey.trim(),
  };

  String? _extractAudio(Map<String, dynamic> json) {
    final steps = json['steps'];
    if (steps is List) {
      for (final step in steps.reversed) {
        if (step is! Map) continue;
        if (step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is! List) continue;
        for (final block in content.reversed) {
          if (block is Map && block['type'] == 'audio') {
            final data = block['data'];
            if (data is String && data.isNotEmpty) return data;
          }
        }
      }
    }
    // Defensive support for a convenience field used by some SDK wrappers.
    final output = json['output_audio'];
    if (output is Map && output['data'] is String) {
      return output['data'] as String;
    }
    return null;
  }

  void _throwForStatus(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final message = _errorMessage(response.body);
    String? detail;
    if (message != null) {
      final redacted = AppLog.redact(message);
      detail = redacted.length > 400 ? redacted.substring(0, 400) : redacted;
    }
    switch (response.statusCode) {
      case 400:
        throw AppException(
          AppErrorKind.invalidRequest,
          message ?? 'Gemini rejected the request.',
          detail: detail,
        );
      case 401:
      case 403:
        throw AppException(
          AppErrorKind.unauthorized,
          'Gemini rejected the API key or the key lacks access.',
          detail: detail,
        );
      case 404:
        throw AppException(
          AppErrorKind.modelUnavailable,
          'The configured Gemini TTS model is unavailable.',
          detail: detail,
        );
      case 429:
        final quota = (message ?? '').toLowerCase().contains('quota');
        throw AppException(
          quota ? AppErrorKind.quotaExceeded : AppErrorKind.rateLimited,
          quota
              ? 'Gemini quota exceeded for this key.'
              : 'Gemini rate limit reached. Try again shortly.',
          detail: detail,
          retryable: true,
        );
      default:
        if (response.statusCode >= 500) {
          throw AppException(
            AppErrorKind.server,
            'Gemini is temporarily unavailable.',
            detail: detail,
            retryable: true,
          );
        }
        throw AppException(
          AppErrorKind.unknown,
          'Gemini request failed (${response.statusCode}).',
          detail: detail,
        );
    }
  }

  String? _errorMessage(String body) {
    if (body.isEmpty) return null;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {
      // Fall through to a truncated plain-text body.
    }
    return body.length > 400 ? body.substring(0, 400) : body;
  }

  void close() => _http.close();
}
