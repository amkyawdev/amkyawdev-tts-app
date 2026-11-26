import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../app_dependencies.dart';
import '../core/errors/app_exception.dart';
import '../services/history_repository.dart';
import '../services/settings_repository.dart';
import '../tts/audio/wav_codec.dart';
import '../tts/engine_registry.dart';
import '../tts/engines/gemini/gemini_engine.dart';
import '../tts/engines/piper/piper_engine.dart';
import '../tts/engines/piper/piper_model_manifest.dart';
import '../tts/engines/piper/piper_model_manager.dart';
import '../tts/engines/system/system_tts_engine.dart';
import '../tts/engines/vieneu/vieneu_engine.dart';
import '../tts/models/audio_format.dart';
import '../tts/models/cancellation_token.dart';
import '../tts/models/engine_capabilities.dart';
import '../tts/models/engine_id.dart';
import '../tts/models/generation_progress.dart';
import '../tts/models/synthesis.dart';
import '../tts/models/tts_language.dart';
import '../tts/models/tts_voice.dart';
import '../tts/tts_engine.dart';
import '../tts/voices/voice_catalog.dart';

final depsProvider = Provider<AppDependencies>(
  (ref) => throw UnimplementedError('AppDependencies must be overridden'),
);

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(
  SettingsController.new,
);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(depsProvider).settingsRepository.load();

  Future<void> update(AppSettings value) async {
    state = value;
    await ref.read(depsProvider).settingsRepository.save(value);
  }
}

final engineRegistryProvider = Provider<EngineRegistry>((ref) {
  final deps = ref.read(depsProvider);
  // Only these two settings change how an engine is constructed. Watching the
  // whole settings object would recreate every engine when the user merely
  // picks a voice or a language.
  final piperModelId = ref.watch(
    settingsProvider.select((settings) => settings.piperModelId),
  );
  final vieneuBaseUrl = ref.watch(
    settingsProvider.select((settings) => settings.vieneuBaseUrl),
  );
  final engines = <TtsEngine>[
    PiperTtsEngine(deps.piperModels, piperModelId),
    GeminiTtsEngine(deps.geminiClient, deps.secureKeys),
    VieNeuTtsEngine(vieneuBaseUrl, deps.secureKeys),
    SystemTtsEngine(),
  ];
  ref.onDispose(() {
    for (final engine in engines) {
      unawaited(engine.dispose().catchError((Object _) {}));
    }
  });
  return EngineRegistry(engines);
});

class StudioState {
  const StudioState({
    required this.text,
    required this.engineId,
    required this.voiceId,
    required this.speed,
    this.languageCode = '',
    this.generating = false,
    this.progress,
    this.result,
    this.error,
    this.statuses = const {},
    this.voices = const [],
    this.loadingVoices = true,
    this.voicesError,
  });

  final String text;
  final TtsEngineId engineId;
  final String voiceId;

  /// Language the picker is filtered by; always derived from real voice metadata.
  final String languageCode;
  final double speed;
  final bool generating;
  final GenerationProgress? progress;
  final SynthesisResult? result;
  final String? error;
  final Map<TtsEngineId, EngineStatus> statuses;
  final List<TtsVoice> voices;
  final bool loadingVoices;

  /// Non-null when the engine failed to enumerate voices. Shown instead of a
  /// silent "no voices" state.
  final String? voicesError;

  VoiceCatalog get catalog => VoiceCatalog(voices);

  LanguageOption? get selectedLanguage => catalog.optionForCode(languageCode);

  List<TtsVoice> get visibleVoices => catalog.voicesForCode(languageCode);

  StudioState copyWith({
    String? text,
    TtsEngineId? engineId,
    String? voiceId,
    String? languageCode,
    double? speed,
    bool? generating,
    GenerationProgress? progress,
    SynthesisResult? result,
    String? error,
    Map<TtsEngineId, EngineStatus>? statuses,
    List<TtsVoice>? voices,
    bool? loadingVoices,
    String? voicesError,
    bool clearVoicesError = false,
    bool clearError = false,
    bool clearProgress = false,
    bool clearResult = false,
  }) {
    return StudioState(
      text: text ?? this.text,
      engineId: engineId ?? this.engineId,
      voiceId: voiceId ?? this.voiceId,
      languageCode: languageCode ?? this.languageCode,
      speed: speed ?? this.speed,
      generating: generating ?? this.generating,
      progress: clearProgress ? null : (progress ?? this.progress),
      result: clearResult ? null : (result ?? this.result),
      error: clearError ? null : (error ?? this.error),
      statuses: statuses ?? this.statuses,
      voices: voices ?? this.voices,
      loadingVoices: loadingVoices ?? this.loadingVoices,
      voicesError: clearVoicesError ? null : (voicesError ?? this.voicesError),
    );
  }
}

final studioProvider = NotifierProvider<StudioController, StudioState>(
  StudioController.new,
);

class _VoiceLoadResult {
  const _VoiceLoadResult(this.voices, this.error);

  final List<TtsVoice> voices;
  final String? error;
}

class StudioController extends Notifier<StudioState> {
  CancellationToken? _token;

  @override
  StudioState build() {
    final settings = ref.read(settingsProvider);
    Future.microtask(() {
      if (ref.mounted) _refresh();
    });
    ref.onDispose(() => _token?.cancel());
    return StudioState(
      text: '',
      engineId: settings.defaultEngine,
      voiceId: settings.voiceFor(settings.defaultEngine),
      speed: settings.speechRate,
    );
  }

  Future<void> _refresh() async {
    final registry = ref.read(engineRegistryProvider);
    final statuses = <TtsEngineId, EngineStatus>{};
    for (final engine in registry.all) {
      try {
        statuses[engine.descriptor.id] = await engine.status();
      } catch (error) {
        statuses[engine.descriptor.id] = EngineStatus.error('$error');
      }
    }
    if (!ref.mounted) return;
    final engineId = state.engineId;
    state = state.copyWith(
      statuses: statuses,
      loadingVoices: state.voices.isEmpty,
    );
    final result = await _voicesFor(engineId);
    if (!ref.mounted || state.engineId != engineId) return;
    _applyVoices(result);
  }

  Future<_VoiceLoadResult> _voicesFor(TtsEngineId id) async {
    try {
      final voices = await ref.read(engineRegistryProvider).byId(id).voices();
      return _VoiceLoadResult(voices, null);
    } on AppException catch (error) {
      return _VoiceLoadResult(const [], error.message);
    } catch (error) {
      return _VoiceLoadResult(const [], 'Could not load voices: $error');
    }
  }

  /// Rebuilds language/voice state from the voices an engine actually reported.
  void _applyVoices(_VoiceLoadResult result, {String? preferredLanguage}) {
    final catalog = VoiceCatalog(result.voices);
    if (catalog.isEmpty) {
      state = state.copyWith(
        voices: const [],
        voiceId: '',
        languageCode: '',
        loadingVoices: false,
        voicesError:
            result.error ??
            'This engine reported no voices. Check its setup in Settings.',
      );
      return;
    }
    final code =
        preferredLanguage ??
        catalog.optionForCode(state.languageCode)?.language.code ??
        catalog.codeForVoice(state.voiceId) ??
        catalog.options.first.language.code;
    final voiceId = catalog.resolveVoiceSelection(
      code: code,
      preferredVoiceId: state.voiceId,
    );
    state = state.copyWith(
      voices: result.voices,
      voiceId: voiceId,
      languageCode: code,
      loadingVoices: false,
      clearVoicesError: true,
    );
  }

  void setText(String text) => state = state.copyWith(text: text);

  void setSpeed(double speed) => state = state.copyWith(speed: speed);

  Future<void> selectEngine(TtsEngineId id) async {
    if (state.engineId == id && state.voices.isNotEmpty) return;
    _token?.cancel();
    final settings = ref.read(settingsProvider);
    state = state.copyWith(
      engineId: id,
      voiceId: settings.voiceFor(id),
      languageCode: '',
      voices: const [],
      loadingVoices: true,
      clearVoicesError: true,
      clearError: true,
      clearResult: true,
      clearProgress: true,
      generating: false,
    );
    unawaited(_persistEngine(id));
    final result = await _voicesFor(id);
    if (!ref.mounted || state.engineId != id) return;
    _applyVoices(result);
    final preferences = ref.read(settingsProvider);
    final preferred = preferences.voiceFor(id);
    if (preferred.isEmpty) return;
    final catalog = VoiceCatalog(state.voices);
    final option = catalog.optionForVoice(preferred);
    if (option == null) return;
    state = state.copyWith(
      languageCode: option.language.code,
      voiceId: catalog.resolveVoiceSelection(
        code: option.language.code,
        preferredVoiceId: preferred,
      ),
    );
  }

  /// Filters the voice list to [code] and keeps a valid voice selected.
  void selectLanguage(String code) {
    final catalog = VoiceCatalog(state.voices);
    final option = catalog.optionForCode(code);
    if (option == null) return;
    final voiceId = catalog.resolveVoiceSelection(
      code: option.language.code,
      preferredVoiceId: state.voiceId,
    );
    state = state.copyWith(
      languageCode: option.language.code,
      voiceId: voiceId,
    );
    _rememberLanguage(option.language.code);
    if (voiceId.isNotEmpty) unawaited(_persistVoice(state.engineId, voiceId));
  }

  void selectVoice(String voiceId) {
    final catalog = VoiceCatalog(state.voices);
    final option = catalog.optionForVoice(voiceId);
    state = state.copyWith(
      voiceId: voiceId,
      languageCode: option?.language.code ?? state.languageCode,
    );
    if (option != null) _rememberLanguage(option.language.code);
    unawaited(_persistVoice(state.engineId, voiceId));
  }

  void _rememberLanguage(String code) {
    final normalized = normalizeLanguageCode(code);
    if (normalized.isEmpty || normalized == 'und') return;
    final settings = ref.read(settingsProvider);
    final recent = [
      normalized,
      ...settings.recentLanguageCodes.where((item) => item != normalized),
    ].take(6).toList(growable: false);
    if (listEquals(recent, settings.recentLanguageCodes)) return;
    unawaited(
      ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(recentLanguageCodes: recent)),
    );
  }

  Future<void> _persistEngine(TtsEngineId id) async {
    final settings = ref.read(settingsProvider);
    if (settings.defaultEngine == id) return;
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(defaultEngine: id));
  }

  Future<void> _persistVoice(TtsEngineId engineId, String voiceId) async {
    final settings = ref.read(settingsProvider);
    if (settings.voiceFor(engineId) == voiceId) return;
    await ref
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(
            defaultVoiceIds: {...settings.defaultVoiceIds, engineId: voiceId},
          ),
        );
  }

  Future<void> refresh() => _refresh();

  void cancel() {
    _token?.cancel();
  }

  Future<void> generate() async {
    if (state.generating) return;
    final text = state.text.trim();
    if (text.isEmpty) {
      state = state.copyWith(error: 'Enter some text first.');
      return;
    }
    final engineId = state.engineId;
    final voiceId = state.voiceId;
    final speed = state.speed;
    if (voiceId.isEmpty) {
      state = state.copyWith(
        error:
            'This engine has no selectable voice yet. '
            'Check its setup and try again.',
      );
      return;
    }
    final registry = ref.read(engineRegistryProvider);
    final engine = registry.byId(engineId);
    final status = await engine.status();
    if (!ref.mounted) return;
    if (!status.isReady) {
      state = state.copyWith(
        error: status.detail == null
            ? status.message
            : '${status.message} · ${status.detail}',
      );
      return;
    }
    final deps = ref.read(depsProvider);
    final settings = ref.read(settingsProvider);
    final token = CancellationToken();
    _token = token;
    state = state.copyWith(
      generating: true,
      clearError: true,
      clearResult: true,
      progress: const GenerationProgress(
        phase: GenerationPhase.preparing,
        message: 'Preparing engine',
      ),
    );
    try {
      final outputPath = await deps.storage.newAudioPath(AudioFormat.wav);
      final result = await engine.synthesize(
        request: SynthesisRequest(text: text, voiceId: voiceId, speed: speed),
        outputPath: outputPath,
        cancel: token,
        onProgress: (progress) {
          if (ref.mounted) state = state.copyWith(progress: progress);
        },
      );
      final audio = await File(result.audioPath).length();
      if (audio <= 44) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'The engine returned an empty audio file.',
          detail: 'Nothing to play or save. Try a different voice or engine.',
        );
      }
      await deps.historyRepository.insert(
        HistoryEntry(
          id: const Uuid().v4(),
          text: text,
          engineId: engineId,
          voiceId: result.voiceId.isEmpty ? voiceId : result.voiceId,
          createdAt: DateTime.now(),
          audioPath: result.audioPath,
          durationMs: result.duration.inMilliseconds,
          format: result.format,
          sampleRate: result.sampleRate,
          charCount: result.charCount,
          chunkCount: result.chunkCount,
        ),
      );
      await ref.read(historyProvider.notifier).refresh();
      if (!ref.mounted) return;
      state = state.copyWith(
        generating: false,
        clearProgress: true,
        result: result,
      );
      await ref
          .read(playerProvider.notifier)
          .load(
            result.audioPath,
            title: text.length > 48 ? '${text.substring(0, 48)}…' : text,
            autoPlay: settings.autoPlay,
          );
    } on AppException catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          generating: false,
          clearProgress: true,
          error: error.message,
        );
      }
    } catch (error) {
      if (ref.mounted) {
        state = state.copyWith(
          generating: false,
          clearProgress: true,
          error: 'Generation failed: $error',
        );
      }
    } finally {
      if (_token == token) _token = null;
    }
  }
}

final historyProvider =
    AsyncNotifierProvider<HistoryController, List<HistoryEntry>>(
      HistoryController.new,
    );

class HistoryController extends AsyncNotifier<List<HistoryEntry>> {
  @override
  Future<List<HistoryEntry>> build() =>
      ref.read(depsProvider).historyRepository.all();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(depsProvider).historyRepository.all(),
    );
  }

  Future<void> delete(HistoryEntry entry) async {
    final deps = ref.read(depsProvider);
    await deps.historyRepository.delete(entry.id);
    await deps.storage.deleteFile(entry.audioPath);
    await refresh();
  }

  Future<void> clear() async {
    final deps = ref.read(depsProvider);
    final paths = await deps.historyRepository.clear();
    for (final path in paths) {
      await deps.storage.deleteFile(path);
    }
    state = const AsyncData([]);
  }
}

class ModelsState {
  const ModelsState({
    required this.models,
    this.activeId,
    this.progress,
    this.error,
  });

  final List<PiperModelStatus> models;
  final String? activeId;
  final double? progress;
  final String? error;

  ModelsState copyWith({
    List<PiperModelStatus>? models,
    String? activeId,
    double? progress,
    String? error,
    bool clearActive = false,
    bool clearProgress = false,
    bool clearError = false,
  }) {
    return ModelsState(
      models: models ?? this.models,
      activeId: clearActive ? null : (activeId ?? this.activeId),
      progress: clearProgress ? null : (progress ?? this.progress),
      error: clearError ? null : (error ?? this.error),
    );
  }
}

final modelsProvider = AsyncNotifierProvider<ModelsController, ModelsState>(
  ModelsController.new,
);

class ModelsController extends AsyncNotifier<ModelsState> {
  CancellationToken? _token;

  @override
  Future<ModelsState> build() async {
    final models = await ref.read(depsProvider).piperModels.list();
    return ModelsState(models: models);
  }

  Future<void> download(String id) async {
    final manifest = piperModelById(id);
    if (manifest == null) return;
    final token = CancellationToken();
    _token = token;
    final current = state.asData?.value ?? const ModelsState(models: []);
    state = AsyncData(
      current.copyWith(activeId: id, progress: 0, clearError: true),
    );
    try {
      await ref
          .read(depsProvider)
          .piperModels
          .download(
            manifest,
            cancel: token,
            onProgress: (received, total) {
              final value = total > 0 ? received / total : null;
              final latest = state.asData?.value;
              if (latest != null) {
                state = AsyncData(latest.copyWith(progress: value));
              }
            },
          );
      final models = await ref.read(depsProvider).piperModels.list();
      state = AsyncData(ModelsState(models: models));
      await ref.read(studioProvider.notifier).refresh();
    } on AppException catch (error) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            error: error.message,
            clearActive: true,
            clearProgress: true,
          ),
        );
      }
    } catch (error) {
      final latest = state.asData?.value;
      if (latest != null) {
        state = AsyncData(
          latest.copyWith(
            error: 'Download failed: $error',
            clearActive: true,
            clearProgress: true,
          ),
        );
      }
    }
  }

  void cancel() => _token?.cancel();

  Future<void> delete(String id) async {
    final manifest = piperModelById(id);
    if (manifest == null) return;
    await ref.read(depsProvider).piperModels.delete(manifest);
    final models = await ref.read(depsProvider).piperModels.list();
    state = AsyncData(ModelsState(models: models));
    await ref.read(studioProvider.notifier).refresh();
  }
}

class PlayerState {
  const PlayerState({
    this.path,
    this.title = '',
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.playing = false,
    this.waveform = const [],
    this.speed = 1.0,
    this.error,
    this.format = AudioFormat.wav,
  });

  final String? path;
  final String title;
  final Duration duration;
  final Duration position;
  final bool playing;
  final List<double> waveform;
  final double speed;
  final String? error;
  final AudioFormat format;

  PlayerState copyWith({
    String? path,
    String? title,
    Duration? duration,
    Duration? position,
    bool? playing,
    List<double>? waveform,
    double? speed,
    String? error,
    AudioFormat? format,
    bool clearError = false,
  }) {
    return PlayerState(
      path: path ?? this.path,
      title: title ?? this.title,
      duration: duration ?? this.duration,
      position: position ?? this.position,
      playing: playing ?? this.playing,
      waveform: waveform ?? this.waveform,
      speed: speed ?? this.speed,
      error: clearError ? null : (error ?? this.error),
      format: format ?? this.format,
    );
  }
}

final playerProvider = NotifierProvider<PlayerController, PlayerState>(
  PlayerController.new,
);

class PlayerController extends Notifier<PlayerState> {
  AudioPlayer? _player;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<bool>? _playingSub;

  @override
  PlayerState build() {
    ref.onDispose(() {
      _positionSub?.cancel();
      _playingSub?.cancel();
      _player?.dispose();
    });
    return const PlayerState();
  }

  Future<void> load(String path, {String? title, bool autoPlay = false}) async {
    final player = _player ??= AudioPlayer();
    try {
      final duration = await player.setFilePath(path);
      List<double> waveform = const [];
      var format = AudioFormat.wav;
      final bytes = await File(path).readAsBytes();
      if (WavCodec.isWav(bytes)) {
        waveform = WavCodec.waveform(bytes);
      } else {
        format = AudioFormat.caf;
      }
      await _positionSub?.cancel();
      await _playingSub?.cancel();
      _positionSub = player.positionStream.listen((position) {
        state = state.copyWith(position: position);
      });
      _playingSub = player.playingStream.listen((playing) {
        state = state.copyWith(playing: playing);
      });
      state = PlayerState(
        path: path,
        title: title ?? state.title,
        duration: duration ?? Duration.zero,
        waveform: waveform,
        speed: state.speed,
        format: format,
      );
      if (autoPlay) await player.play();
    } catch (error) {
      state = state.copyWith(error: 'Playback failed: $error');
    }
  }

  Future<void> toggle() async {
    final player = _player;
    if (player == null) return;
    if (player.playing) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  Future<void> setSpeed(double speed) async {
    state = state.copyWith(speed: speed);
    await _player?.setSpeed(speed);
  }

  Future<void> stop() async {
    await _player?.stop();
  }
}
