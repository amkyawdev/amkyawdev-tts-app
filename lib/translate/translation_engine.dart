import '../core/errors/app_exception.dart';
import '../tts/models/cancellation_token.dart';

/// Splits text into chunks that fit a model context window.
///
/// Splitting happens on paragraph, then line, then sentence boundaries and
/// finally on a hard character boundary. Text is never dropped or truncated:
/// concatenating the chunks returns the original string.
List<String> chunkText(String text, {required int maxChars}) {
  if (text.isEmpty) return const [];
  if (maxChars < 64) {
    throw ArgumentError.value(maxChars, 'maxChars', 'must be at least 64');
  }
  final chunks = <String>[];
  var start = 0;
  final breakPatterns = [
    RegExp(r'\n\s*\n'),
    RegExp(r'\n'),
    RegExp(r'(?<=[.!?။…])\s'),
    RegExp(r'\s'),
  ];
  while (start < text.length) {
    if (text.length - start <= maxChars) {
      chunks.add(text.substring(start));
      break;
    }
    final limit = start + maxChars;
    var cut = -1;
    final window = text.substring(start, limit);
    for (final pattern in breakPatterns) {
      final matches = pattern.allMatches(window);
      if (matches.isNotEmpty) {
        cut = start + matches.last.end;
        break;
      }
    }
    // A single long token is hard-split rather than truncated.
    if (cut <= start) cut = limit;
    chunks.add(text.substring(start, cut));
    start = cut;
  }
  return chunks;
}

enum TranslationMode { offline, online }

enum TranslationStage {
  idle,
  loadingModel,
  preparing,
  translating,
  saving,
  completed,
  failed,
  cancelled,
}

class TranslationProgress {
  const TranslationProgress({
    required this.stage,
    required this.completedChunks,
    required this.totalChunks,
    required this.message,
  });

  final TranslationStage stage;
  final int completedChunks;
  final int totalChunks;
  final String message;

  /// True progress only. Null while the total is unknown.
  double? get fraction =>
      totalChunks <= 0 ? null : (completedChunks / totalChunks).clamp(0, 1);

  bool get isTerminal =>
      stage == TranslationStage.completed ||
      stage == TranslationStage.failed ||
      stage == TranslationStage.cancelled;
}

class TranslationException implements Exception {
  const TranslationException(this.message, {this.detail});

  final String message;
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Backend contract. Implementations must never return the input unchanged as
/// a fake "translation": if the model/runtime is missing they throw
/// [TranslationException].
abstract class TranslationBackend {
  String get name;

  TranslationMode get mode;

  bool get isReady;

  /// Human-readable reason when [isReady] is false.
  String? get unavailableReason;

  Future<void> prepare({
    required String sourceLanguage,
    required String targetLanguage,
    required int maxChunkChars,
  });

  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken cancel,
  });

  Future<void> dispose();
}

/// Used when no model is installed or no runtime is available.
class UnavailableTranslationBackend implements TranslationBackend {
  const UnavailableTranslationBackend(
    this.unavailableReason, {
    this.name = 'No model',
  });

  @override
  final String name;

  @override
  TranslationMode get mode => TranslationMode.offline;

  @override
  final String? unavailableReason;

  @override
  bool get isReady => false;

  @override
  Future<void> prepare({
    required String sourceLanguage,
    required String targetLanguage,
    required int maxChunkChars,
  }) async {
    throw TranslationException(
      unavailableReason ?? 'Translation is not available.',
    );
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken cancel,
  }) async {
    throw TranslationException(
      unavailableReason ?? 'Translation is not available.',
    );
  }

  @override
  Future<void> dispose() async {}
}

class TranslationResult {
  const TranslationResult({
    required this.chunks,
    required this.translations,
    required this.elapsed,
  });

  final List<String> chunks;
  final List<String> translations;
  final Duration elapsed;
}

/// Runs a backend over ordered chunks with real per-chunk progress, retry and
/// cancellation. No timer-based fake progress exists anywhere in this pipeline.
class TranslationRunner {
  TranslationRunner({
    required this.backend,
    required this.chunks,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.onProgress,
    this.cancel,
    this.retries = 1,
  });

  final TranslationBackend backend;
  final List<String> chunks;
  final String sourceLanguage;
  final String targetLanguage;
  final void Function(TranslationProgress) onProgress;
  final CancellationToken? cancel;
  final int retries;

  Future<TranslationResult> run() async {
    final watch = Stopwatch()..start();
    final total = chunks.length;
    void emit(TranslationStage stage, int completed, String message) {
      onProgress(
        TranslationProgress(
          stage: stage,
          completedChunks: completed,
          totalChunks: total,
          message: message,
        ),
      );
    }

    if (!backend.isReady) {
      emit(
        TranslationStage.failed,
        0,
        backend.unavailableReason ?? 'No translation model is ready.',
      );
      throw TranslationException(
        backend.unavailableReason ?? 'No translation model is ready.',
      );
    }
    emit(TranslationStage.loadingModel, 0, 'Loading ${backend.name}');
    await backend.prepare(
      sourceLanguage: sourceLanguage,
      targetLanguage: targetLanguage,
      maxChunkChars: chunks.isEmpty ? 1 : _maxChunkLength(),
    );
    cancel?.throwIfCancelled();

    final translations = <String>[];
    emit(TranslationStage.translating, 0, 'Translating $total chunks');
    for (var i = 0; i < total; i++) {
      cancel?.throwIfCancelled();
      TranslationException? lastError;
      for (var attempt = 0; attempt <= retries; attempt++) {
        try {
          final translated = await backend.translate(
            chunks[i],
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            cancel: cancel ?? CancellationToken(),
          );
          if (translated.trim().isEmpty) {
            throw const TranslationException(
              'The model returned an empty translation for this chunk.',
            );
          }
          translations.add(translated);
          lastError = null;
          break;
        } on CancelledException {
          rethrow;
        } on TranslationException catch (error) {
          lastError = error;
        }
      }
      if (lastError != null) {
        emit(
          TranslationStage.failed,
          i,
          'Chunk ${i + 1} of $total failed: ${lastError.message}',
        );
        throw lastError;
      }
      emit(
        TranslationStage.translating,
        i + 1,
        'Translating ${i + 1} of $total',
      );
    }
    watch.stop();
    return TranslationResult(
      chunks: chunks,
      translations: translations,
      elapsed: watch.elapsed,
    );
  }

  int _maxChunkLength() =>
      chunks.map((chunk) => chunk.length).reduce((a, b) => a > b ? a : b);
}
