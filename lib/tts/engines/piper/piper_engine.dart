import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:piper_phonemize/piper_phonemize.dart' as piper;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../core/errors/app_exception.dart';
import '../../audio/wav_codec.dart';
import '../../chunking/text_chunker.dart';
import '../../models/audio_format.dart';
import '../../models/cancellation_token.dart';
import '../../models/engine_capabilities.dart';
import '../../models/engine_id.dart';
import '../../models/generation_progress.dart';
import '../../models/synthesis.dart';
import '../../models/tts_voice.dart';
import '../../tts_engine.dart';
import 'piper_model_manifest.dart';
import 'piper_model_manager.dart';

/// Genuine offline Piper VITS inference.
///
/// sherpa-onnx executes the ONNX graph and piper-phonemize (espeak-ng) creates
/// phoneme codepoints. Inference runs in a disposable isolate so the UI stays
/// responsive and cancellation can kill the isolate.
class PiperTtsEngine implements TtsEngine {
  PiperTtsEngine(this._manager, this._modelId);

  static const int maxChunkChars = 600;
  static String? _espeakDataDirCache;

  final PiperModelManager _manager;
  final String _modelId;
  bool _busy = false;

  PiperModelManifest? get _manifest => piperModelById(_modelId);

  /// espeak-ng voice used by the phonemizer. Only English manifests are in the
  /// catalogue, so anything else is refused instead of being phonemised as
  /// English and producing wrong-sounding audio.
  static String? _phonemeVoiceFor(String language) {
    final normalized = language.toLowerCase().replaceAll('_', '-');
    if (normalized.startsWith('en')) return 'en-us';
    return null;
  }

  @override
  EngineDescriptor get descriptor => const EngineDescriptor(
    id: TtsEngineId.piper,
    name: 'Piper ONNX',
    tagline: 'Genuine on-device synthesis',
    description:
        'Piper VITS inference on the device with sherpa-onnx and '
        'piper-phonemize. Audio never leaves the phone.',
    capabilities: EngineCapabilities(
      offline: true,
      requiresNetwork: false,
      requiresApiKey: false,
      requiresModelDownload: true,
      platforms: {EnginePlatform.android, EnginePlatform.ios},
      cancellation: CancellationSupport.immediate,
      supportsVoiceSelection: false,
      supportsSpeed: true,
      supportsStyle: false,
      supportsWaveform: true,
      maxChunkChars: maxChunkChars,
      outputFormats: ['wav'],
    ),
    notes: [
      'The bundled catalogue is English (en_US-lessac). It does not synthesize Burmese.',
      'Piper and espeak-ng carry their own licenses; see docs/ENGINE_COMPATIBILITY.md.',
      'Model files are downloaded externally and are never bundled in the APK.',
    ],
    docsUrl: 'https://github.com/k2-fsa/sherpa-onnx',
  );

  @override
  Future<EngineStatus> status() async {
    final manifest = _manifest;
    if (manifest == null) {
      return const EngineStatus.needsSetup('Select a Piper model');
    }
    final status = await _manager.status(manifest);
    if (!status.installed) {
      return EngineStatus.needsSetup(
        'Download ${manifest.name}',
        detail: 'Model Manager → Piper',
      );
    }
    return EngineStatus.ready(manifest.name);
  }

  @override
  Future<List<TtsVoice>> voices() async {
    final manifest = _manifest;
    if (manifest == null) return const [];
    if (_phonemeVoiceFor(manifest.language) == null) return const [];
    return [
      TtsVoice(
        id: 'lessac',
        name: 'Lessac',
        engineId: TtsEngineId.piper,
        languageCode: manifest.language,
        description:
            '${manifest.quality} · ${manifest.sampleRate} Hz · English only',
        isDefault: true,
      ),
    ];
  }

  Future<String> _espeakDataDir() async {
    final cached = _espeakDataDirCache;
    if (cached != null) return cached;
    final dir = await piper.extractEspeakNgData();
    _espeakDataDirCache = dir;
    return dir;
  }

  @override
  Future<SynthesisResult> synthesize({
    required SynthesisRequest request,
    required String outputPath,
    required CancellationToken cancel,
    required ProgressCallback onProgress,
  }) async {
    if (_busy) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'A generation is already running.',
      );
    }
    final manifest = _manifest;
    if (manifest == null) {
      throw const AppException(
        AppErrorKind.modelMissing,
        'Select a Piper model in Settings.',
      );
    }
    final status = await _manager.status(manifest);
    if (!status.installed ||
        status.modelPath == null ||
        status.tokensPath == null) {
      throw AppException(
        AppErrorKind.modelMissing,
        '${manifest.name} is not installed.',
        detail: 'Download it from Model Manager first.',
      );
    }
    if (request.text.trim().isEmpty) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'Enter some text to synthesize.',
      );
    }
    final phonemeVoice = _phonemeVoiceFor(manifest.language);
    if (phonemeVoice == null) {
      throw AppException(
        AppErrorKind.unsupported,
        'This Piper model (${manifest.language}) has no verified phonemizer '
        'mapping in this build.',
        detail: 'The bundled Piper catalogue is English only.',
      );
    }

    _busy = true;
    final receive = ReceivePort();
    final exit = ReceivePort();
    final done = Completer<Map<String, Object?>>();
    Isolate? isolate;
    Timer? cancelTimer;
    StreamSubscription<dynamic>? subscription;

    try {
      final espeakDir = await _espeakDataDir();
      subscription = receive.listen((message) {
        if (message is List && message.length >= 2) {
          if (!done.isCompleted) {
            done.completeError(
              AppException(
                AppErrorKind.unknown,
                'Piper inference failed.',
                detail: '${message[0]}',
              ),
            );
          }
          return;
        }
        if (message is! Map) return;
        final type = message['type'];
        if (type == 'progress') {
          onProgress(
            GenerationProgress(
              phase: GenerationPhase.synthesizing,
              completedChunks: (message['completed'] as num?)?.toInt() ?? 0,
              totalChunks: (message['total'] as num?)?.toInt() ?? 0,
            ),
          );
        } else if (type == 'done') {
          if (!done.isCompleted) {
            done.complete(Map<String, Object?>.from(message));
          }
        } else if (type == 'error') {
          if (!done.isCompleted) {
            done.completeError(
              AppException(
                AppErrorKind.unknown,
                (message['message'] as String?) ?? 'Piper inference failed.',
                detail: message['detail'] as String?,
              ),
            );
          }
        }
      });

      final args = <String, Object>{
        'modelPath': status.modelPath!,
        'tokensPath': status.tokensPath!,
        'espeakDataDir': espeakDir,
        'text': request.text,
        'outputPath': outputPath,
        'speed': request.speed,
        'phonemeVoice': phonemeVoice,
        'maxChars': maxChunkChars,
        'send': receive.sendPort,
      };
      isolate = await Isolate.spawn<Map<String, Object>>(
        _piperEntry,
        args,
        onError: receive.sendPort,
        onExit: exit.sendPort,
        errorsAreFatal: true,
      );

      cancelTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
        if (cancel.isCancelled && !done.isCompleted) {
          isolate?.kill(priority: Isolate.immediate);
          done.completeError(const CancelledException());
        }
      });

      final result = await done.future;
      cancel.throwIfCancelled();
      final sampleRate = (result['sampleRate'] as num?)?.toInt() ?? 0;
      final durationMs = (result['durationMs'] as num?)?.toInt() ?? 0;
      return SynthesisResult(
        audioPath: outputPath,
        format: AudioFormat.wav,
        sampleRate: sampleRate,
        duration: Duration(milliseconds: durationMs),
        engineId: TtsEngineId.piper,
        voiceId: request.voiceId,
        charCount: request.text.length,
        chunkCount: (result['chunks'] as num?)?.toInt() ?? 1,
      );
    } finally {
      _busy = false;
      cancelTimer?.cancel();
      await subscription?.cancel();
      receive.close();
      exit.close();
      isolate?.kill(priority: Isolate.beforeNextEvent);
    }
  }

  @override
  Future<void> dispose() async {}
}

/// Entry point used by [Isolate.spawn]. Kept top-level and sendable.
Future<void> _piperEntry(Map<String, Object> args) async {
  final send = args['send']! as SendPort;
  try {
    await sherpa.initBindingsAsync();
    piper.initBindings();
    final init = piper.PiperPhonemize.initialize(
      args['espeakDataDir']! as String,
    );
    if (init < 0) {
      throw StateError('Could not initialize the Piper phonemizer.');
    }
    final model = sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: args['modelPath']! as String,
        tokens: args['tokensPath']! as String,
      ),
      numThreads: 2,
      debug: false,
    );
    final tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(model: model, maxNumSentences: 1),
    );
    final text = args['text']! as String;
    final speed = (args['speed'] as num?)?.toDouble() ?? 1.0;
    final maxChars = (args['maxChars'] as num?)?.toInt() ?? 600;
    final chunks = TextChunker.split(text, maxChars: maxChars);
    if (chunks.isEmpty) {
      throw StateError('No text to synthesize.');
    }
    final segments = <Float32List>[];
    var sampleRate = 0;
    for (var i = 0; i < chunks.length; i++) {
      final sentences = piper.PiperPhonemize.phonemize(
        chunks[i],
        voice: args['phonemeVoice']! as String,
      ).where((sentence) => sentence.isNotEmpty).toList(growable: false);
      if (sentences.isEmpty) continue;
      final audio = tts.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(
          sid: 0,
          speed: speed,
          phonemeCodepoints: sentences,
        ),
      );
      if (audio.samples.isEmpty) {
        throw StateError('Piper produced no audio for segment ${i + 1}.');
      }
      sampleRate = audio.sampleRate;
      segments.add(audio.samples);
      send.send({
        'type': 'progress',
        'completed': i + 1,
        'total': chunks.length,
      });
    }
    tts.free();
    if (segments.isEmpty) {
      throw StateError('Piper produced no audio.');
    }

    final gapSamples = (sampleRate * 0.12).round();
    final total =
        segments.fold<int>(0, (sum, part) => sum + part.length) +
        gapSamples * (segments.length - 1);
    final joined = Float32List(total);
    var offset = 0;
    for (var i = 0; i < segments.length; i++) {
      joined.setAll(offset, segments[i]);
      offset += segments[i].length;
      if (i != segments.length - 1) offset += gapSamples;
    }
    final wav = WavCodec.encodeFloat32(joined, sampleRate: sampleRate);
    final file = File(args['outputPath']! as String);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(wav, flush: true);
    send.send({
      'type': 'done',
      'sampleRate': sampleRate,
      'durationMs': (joined.length * 1000) ~/ sampleRate,
      'chunks': chunks.length,
    });
  } catch (error, stack) {
    send.send({
      'type': 'error',
      'message': 'Piper inference failed.',
      'detail': '$error\n$stack',
    });
  }
}
