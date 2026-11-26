import '../core/errors/app_exception.dart';

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../gguf/gguf_catalog.dart';
import '../gguf/gguf_download_manager.dart';
import '../providers/app_providers.dart';
import '../services/storage_service.dart';
import '../translate/llamadart_backend.dart';
import '../translate/subtitle_document.dart';
import '../translate/translation_engine.dart';
import '../tts/models/cancellation_token.dart';

/// Architectures the bundled llama.cpp runtime (llamadart) can load.
const Set<String> translationRuntimeArchitectures = {
  'llama',
  'qwen2',
  'qwen3',
  'gemma3',
  'mistral',
  'phi3',
};

final ggufDownloadsProvider =
    NotifierProvider<GgufDownloadsController, Map<String, GgufDownloadState>>(
      GgufDownloadsController.new,
    );

class GgufDownloadsController extends Notifier<Map<String, GgufDownloadState>> {
  GgufDownloadManager? _manager;
  StreamSubscription<Map<String, GgufDownloadState>>? _subscription;

  GgufDownloadManager? get manager => _manager;

  @override
  Map<String, GgufDownloadState> build() {
    final deps = ref.read(depsProvider);
    final manager = GgufDownloadManager(
      storage: deps.storage,
      store: deps.keyValueStore,
    );
    _manager = manager;
    _subscription = manager.updates.listen((states) => state = states);
    ref.onDispose(() {
      _subscription?.cancel();
      manager.dispose();
    });
    Future.microtask(() async {
      await manager.initialize();
      if (ref.mounted) state = manager.snapshot;
    });
    return const {};
  }

  Future<void> start(GgufTranslationModel model) async {
    await _manager?.start(model);
  }

  void pause() => _manager?.pause();

  Future<void> cancel(GgufTranslationModel model) async {
    await _manager?.cancel(model);
  }

  Future<void> delete(GgufTranslationModel model) async {
    await _manager?.delete(model);
  }

  Future<void> refresh() async {
    await _manager?.initialize();
    final manager = _manager;
    if (manager != null && ref.mounted) state = manager.snapshot;
  }
}

class TranslationState {
  const TranslationState({
    this.fileName,
    this.format = SubtitleFormat.plainText,
    this.encoding = 'UTF-8',
    this.document,
    this.sourceLanguage = 'auto',
    this.targetLanguage = 'my',
    this.stage = TranslationStage.idle,
    this.progress,
    this.outputText,
    this.outputPath,
    this.error,
    this.notice,
    this.usingOnlineBackend = false,
  });

  final String? fileName;
  final SubtitleFormat format;
  final String encoding;
  final SubtitleDocument? document;
  final String sourceLanguage;
  final String targetLanguage;
  final TranslationStage stage;
  final TranslationProgress? progress;
  final String? outputText;
  final String? outputPath;
  final String? error;
  final String? notice;

  /// Always false in this build: no online translation backend is configured.
  final bool usingOnlineBackend;

  bool get hasInput => document != null;

  bool get isRunning =>
      stage == TranslationStage.loadingModel ||
      stage == TranslationStage.preparing ||
      stage == TranslationStage.translating ||
      stage == TranslationStage.saving;

  bool get hasOutput => outputText != null && outputText!.trim().isNotEmpty;

  TranslationState copyWith({
    String? fileName,
    SubtitleFormat? format,
    String? encoding,
    SubtitleDocument? document,
    String? sourceLanguage,
    String? targetLanguage,
    TranslationStage? stage,
    TranslationProgress? progress,
    String? outputText,
    String? outputPath,
    String? error,
    String? notice,
    bool clearOutput = false,
    bool clearError = false,
    bool clearNotice = false,
    bool clearProgress = false,
  }) {
    return TranslationState(
      fileName: fileName ?? this.fileName,
      format: format ?? this.format,
      encoding: encoding ?? this.encoding,
      document: document ?? this.document,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      stage: stage ?? this.stage,
      progress: clearProgress ? null : (progress ?? this.progress),
      outputText: clearOutput ? null : (outputText ?? this.outputText),
      outputPath: outputPath ?? this.outputPath,
      error: clearError ? null : (error ?? this.error),
      notice: clearNotice ? null : (notice ?? this.notice),
      usingOnlineBackend: usingOnlineBackend,
    );
  }
}

final translationProvider =
    NotifierProvider<TranslationController, TranslationState>(
      TranslationController.new,
    );

class TranslationController extends Notifier<TranslationState> {
  CancellationToken? _token;
  TranslationBackend? _backend;

  @override
  TranslationState build() {
    ref.onDispose(() {
      _token?.cancel();
      _backend?.dispose();
    });
    return const TranslationState();
  }

  void loadBytes({
    required Uint8List bytes,
    required String fileName,
    SubtitleFormat? format,
  }) {
    final decoded = decodeTextBytes(bytes);
    final document = SubtitleDocument.parse(
      decoded.text,
      filename: fileName,
      format: format,
    );
    final notes = <String>[];
    if (decoded.lossy) {
      notes.add(
        'Decoded as ${decoded.encoding}; Burmese text may be damaged. '
        'Save the file as UTF-8 and reload.',
      );
    }
    state = TranslationState(
      fileName: fileName,
      format: document.format,
      encoding: decoded.encoding,
      document: document,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      notice: notes.isEmpty ? null : notes.join(' '),
    );
  }

  void loadText({required String text, String fileName = 'pasted.txt'}) {
    final document = SubtitleDocument.parse(text, filename: fileName);
    state = TranslationState(
      fileName: fileName,
      format: document.format,
      encoding: 'UTF-8',
      document: document,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
    );
  }

  void clearInput() {
    _token?.cancel();
    state = TranslationState(
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
    );
  }

  void setSource(String code) {
    if (state.isRunning) return;
    state = state.copyWith(sourceLanguage: code);
  }

  void setTarget(String code) {
    if (state.isRunning) return;
    state = state.copyWith(targetLanguage: code);
  }

  void swapLanguages() {
    if (state.isRunning || state.sourceLanguage == 'auto') return;
    state = state.copyWith(
      sourceLanguage: state.targetLanguage,
      targetLanguage: state.sourceLanguage,
    );
  }

  void editOutput(String text) {
    state = state.copyWith(outputText: text, outputPath: null);
  }

  void cancel() {
    _token?.cancel();
  }

  Future<void> translate() async {
    final document = state.document;
    if (document == null || state.isRunning) return;
    final downloads = ref.read(ggufDownloadsProvider.notifier).manager;
    if (downloads == null) {
      state = state.copyWith(
        error: 'The model manager is still starting. Try again in a moment.',
      );
      return;
    }
    final model = _selectedModel();
    if (model == null) {
      state = state.copyWith(
        error:
            'No translation model is installed. Open Translation models and '
            'download one first.',
      );
      return;
    }
    if (!await downloads.isInstalled(model)) {
      state = state.copyWith(
        error:
            '${model.name} is not downloaded. Open Translation models to '
            'download it.',
      );
      return;
    }
    final file = await downloads.fileFor(model, model.primaryFile);
    final backend = LlamadartTranslationBackend(
      modelPath: file.path,
      modelName: model.name,
      contextLength: model.contextLength,
      supportedArchitectures: translationRuntimeArchitectures,
      architecture: model.architecture,
    );
    await _backend?.dispose();
    _backend = backend;
    final token = CancellationToken();
    _token = token;
    final chunks = _buildChunks(document, model);
    final runner = TranslationRunner(
      backend: backend,
      chunks: chunks,
      sourceLanguage: state.sourceLanguage,
      targetLanguage: state.targetLanguage,
      cancel: token,
      onProgress: (progress) {
        if (!ref.mounted) return;
        state = state.copyWith(progress: progress, stage: progress.stage);
      },
    );
    state = state.copyWith(
      stage: TranslationStage.loadingModel,
      clearOutput: true,
      clearError: true,
      clearNotice: true,
    );
    try {
      final result = await runner.run();
      if (!ref.mounted) return;
      final output = document.format == SubtitleFormat.plainText
          ? result.translations.join('')
          : document.withTranslatedTexts(result.translations).serialize();
      state = state.copyWith(
        stage: TranslationStage.saving,
        outputText: output,
        progress: TranslationProgress(
          stage: TranslationStage.saving,
          completedChunks: result.chunks.length,
          totalChunks: result.chunks.length,
          message: 'Saving the translated file',
        ),
      );
      final path = await _writeOutput(output, document.format);
      if (!ref.mounted) return;
      state = state.copyWith(
        stage: TranslationStage.completed,
        outputPath: path,
        progress: TranslationProgress(
          stage: TranslationStage.completed,
          completedChunks: result.chunks.length,
          totalChunks: result.chunks.length,
          message: 'Translation complete',
        ),
      );
    } on CancelledException {
      if (ref.mounted) {
        state = state.copyWith(
          stage: TranslationStage.cancelled,
          error: 'Translation cancelled. No file was written.',
        );
      }
    } on TranslationException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          stage: TranslationStage.failed,
          error: error.detail == null
              ? error.message
              : '${error.message} ${error.detail}',
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          stage: TranslationStage.failed,
          error: 'Translation failed: $error',
        );
      }
    } finally {
      if (_token == token) _token = null;
    }
  }

  List<String> _buildChunks(
    SubtitleDocument document,
    GgufTranslationModel model,
  ) {
    if (document.format == SubtitleFormat.plainText) {
      return chunkText(
        document.toPlainText(),
        maxChars: model.recommendedChunkChars,
      );
    }
    final chunks = <String>[];
    for (final cue in document.cues) {
      if (!cue.hasTranslatableText) continue;
      chunks.addAll(chunkText(cue.text, maxChars: model.recommendedChunkChars));
    }
    return chunks;
  }

  GgufTranslationModel? _selectedModel() {
    final manager = ref.read(ggufDownloadsProvider.notifier).manager;
    if (manager == null) return null;
    final settings = ref.read(settingsProvider);
    final preferred = ggufTranslationModelById(settings.translationModelId);
    if (preferred != null) return preferred;
    for (final model in ggufTranslationCatalog) {
      final state = manager.stateFor(model.id);
      if (state.isComplete) return model;
    }
    return ggufTranslationCatalog.first;
  }

  Future<String> _writeOutput(String content, SubtitleFormat format) async {
    final deps = ref.read(depsProvider);
    final dir = await _translationDir(deps.storage);
    final baseName = state.fileName == null || state.fileName!.isEmpty
        ? 'translation'
        : p.basenameWithoutExtension(state.fileName!);
    final extension = switch (format) {
      SubtitleFormat.srt => 'my.srt',
      SubtitleFormat.vtt => 'my.vtt',
      SubtitleFormat.plainText => 'my.txt',
    };
    final safe = baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      p.join(dir.path, '${safe.isEmpty ? 'translation' : safe}.$extension'),
    );
    await file.writeAsString(content, flush: true);
    return file.path;
  }

  Future<Directory> _translationDir(StorageService storage) async {
    final support = await storage.supportDir();
    final dir = Directory(p.join(support.path, 'translations'));
    await dir.create(recursive: true);
    return dir;
  }
}
