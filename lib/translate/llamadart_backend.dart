import '../core/errors/app_exception.dart';

import 'dart:io';
import 'dart:math' as math;

import 'package:llamadart/llamadart.dart';

import '../tts/models/cancellation_token.dart';
import 'translation_engine.dart';

/// Genuine on-device GGUF translation through llama.cpp (llamadart).
///
/// The model file must already exist in app storage. Nothing here talks to the
/// network: after the download finishes, translation is fully offline.
class LlamadartTranslationBackend implements TranslationBackend {
  LlamadartTranslationBackend({
    required this.modelPath,
    required this.modelName,
    required this.contextLength,
    required this.supportedArchitectures,
    this.architecture,
  });

  final String modelPath;
  final String modelName;
  final int contextLength;
  final Set<String> supportedArchitectures;
  final String? architecture;

  LlamaEngine? _engine;

  @override
  String get name => 'llamadart · $modelName';

  @override
  TranslationMode get mode => TranslationMode.offline;

  @override
  bool get isReady => File(modelPath).existsSync();

  @override
  String? get unavailableReason =>
      isReady ? null : 'The selected model file is not downloaded.';

  @override
  Future<void> prepare({
    required String sourceLanguage,
    required String targetLanguage,
    required int maxChunkChars,
  }) async {
    if (_engine != null) return;
    if (!await File(modelPath).exists()) {
      throw const TranslationException(
        'The model file is missing.',
        detail: 'Download it again from Translation models.',
      );
    }
    if (architecture != null &&
        !supportedArchitectures.contains(architecture)) {
      throw TranslationException(
        'This runtime does not support the ${architecture!} architecture.',
      );
    }
    try {
      _engine = await LlamaEngine.load(
        LlamaModel(ModelSource.path(modelPath)),
        params: ModelParams(
          contextSize: math.min(contextLength, 8192),
          device: ComputeDevice.cpu,
        ),
      );
    } catch (error) {
      throw TranslationException(
        'Could not load the model on this device.',
        detail: '$error',
      );
    }
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken cancel,
  }) async {
    final engine = _engine;
    if (engine == null) {
      throw const TranslationException('The model is not loaded.');
    }
    final prompt = _prompt(
      text: text,
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
    );
    final buffer = StringBuffer();
    final session = ChatSession(engine);
    try {
      final stream = session.create(
        [LlamaTextContent(prompt)],
        params: const GenerationParams(
          maxTokens: 768,
          temp: 0.2,
          topP: 0.9,
          topK: 40,
        ),
      );
      await for (final chunk in stream) {
        if (cancel.isCancelled) throw const CancelledException();
        buffer.write(chunk.text);
      }
    } on CancelledException {
      rethrow;
    } catch (error) {
      throw TranslationException(
        'The model failed while translating.',
        detail: '$error',
      );
    }
    final cleaned = _cleanOutput(buffer.toString());
    if (cleaned.trim().isEmpty) {
      throw const TranslationException(
        'The model returned an empty translation.',
      );
    }
    return cleaned;
  }

  String _prompt({
    required String text,
    required String sourceLanguage,
    required String targetLanguage,
  }) {
    return 'You are a professional subtitle translator.\n'
        'Translate the text from ${_languageName(sourceLanguage)} to '
        '${_languageName(targetLanguage)}.\n'
        'Rules:\n'
        '1. Reply with the translation only. No explanations, no notes.\n'
        '2. Keep the same line breaks and the same number of lines.\n'
        '3. Keep HTML tags (for example <i>, <b>), speaker labels such as '
        '"NAME:", numbers and music symbols unchanged.\n'
        '4. If a line is already in the target language, keep it.\n'
        'TEXT:\n<<<\n$text\n>>>\nTRANSLATION:\n';
  }

  String _languageName(String code) {
    const names = {
      'auto': 'the detected language',
      'en': 'English',
      'my': 'Burmese (မြန်မာ)',
      'zh': 'Chinese',
      'ja': 'Japanese',
      'ko': 'Korean',
      'th': 'Thai',
      'vi': 'Vietnamese',
      'hi': 'Hindi',
      'fr': 'French',
      'de': 'German',
      'es': 'Spanish',
      'pt': 'Portuguese',
      'ru': 'Russian',
      'ar': 'Arabic',
      'id': 'Indonesian',
      'ms': 'Malay',
      'bn': 'Bengali',
      'ne': 'Nepali',
      'si': 'Sinhala',
      'km': 'Khmer',
      'lo': 'Lao',
    };
    return names[code] ?? code;
  }

  String _cleanOutput(String raw) {
    var value = raw.trim();
    const prefixes = ['TRANSLATION:', 'Translation:', 'translation:'];
    for (final prefix in prefixes) {
      if (value.startsWith(prefix)) {
        value = value.substring(prefix.length).trim();
      }
    }
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith('“') && value.endsWith('”')))) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  @override
  Future<void> dispose() async {
    await _engine?.dispose();
    _engine = null;
  }
}
