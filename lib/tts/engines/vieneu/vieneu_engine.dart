import 'dart:io';
import 'dart:typed_data';

import '../../../core/errors/app_exception.dart';
import '../../../services/secure_key_store.dart';
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
import 'vieneu_client.dart';

/// Server adapter only. VieNeu's official inference stack is Python + ONNX
/// Runtime / PyTorch; no verified Flutter on-device runtime is bundled.
class VieNeuTtsEngine implements TtsEngine {
  VieNeuTtsEngine({
    required String baseUrl,
    required SecureKeyStore secureKeys,
    VieNeuTtsClient? client,
  }) : _baseUrl = baseUrl,
       _secureKeys = secureKeys,
       _client = client ?? VieNeuTtsClient(baseUrl: baseUrl);

  static const int maxChunkChars = 2000;

  final String _baseUrl;
  final SecureKeyStore _secureKeys;
  final VieNeuTtsClient _client;
  bool _busy = false;

  @override
  EngineDescriptor get descriptor => const EngineDescriptor(
    id: TtsEngineId.vieneu,
    name: 'VieNeu',
    tagline: 'Optional LAN inference server',
    description:
        'Connects to the official VieNeu v3 Turbo OpenAI-compatible server. '
        'No VieNeu inference runs inside this app.',
    capabilities: EngineCapabilities(
      offline: false,
      requiresNetwork: true,
      requiresApiKey: false,
      requiresModelDownload: false,
      platforms: {EnginePlatform.android, EnginePlatform.ios},
      cancellation: CancellationSupport.betweenSegments,
      supportsVoiceSelection: true,
      supportsSpeed: false,
      supportsStyle: false,
      supportsWaveform: true,
      maxChunkChars: maxChunkChars,
      outputFormats: ['wav'],
    ),
    notes: [
      'Requires a separately deployed VieNeu server; see docs/ENGINE_COMPATIBILITY.md.',
      'The official open-source runtime is Python/PyTorch/ONNX Runtime, not an embedded Flutter engine.',
      'The adapter expects POST /v1/audio/speech with response_format=wav.',
    ],
    docsUrl: 'https://github.com/pnnbao97/VieNeu-TTS',
  );

  @override
  Future<EngineStatus> status() async {
    if (_baseUrl.trim().isEmpty) {
      return const EngineStatus.needsSetup(
        'Set your VieNeu server URL in Settings',
        detail: 'Example: http://192.168.1.20:8000',
      );
    }
    return const EngineStatus.ready(
      'Server configured; connection is tested on generation',
    );
  }

  @override
  Future<List<TtsVoice>> voices() async {
    final token = await _secureKeys.read(SecureKeys.vieneuToken) ?? '';
    final names = await _client.voices(token: token);
    final effective = names.isEmpty ? const ['Mai Anh'] : names;
    return effective
        .map(
          (name) => TtsVoice(
            id: name,
            name: name,
            engineId: TtsEngineId.vieneu,
            languageCode: 'vi-VN',
            description: names.isEmpty
                ? 'Documented example voice; server list unavailable'
                : 'Reported by your VieNeu server',
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<SynthesisResult> synthesize({
    required SynthesisRequest request,
    required String outputPath,
    required CancellationToken cancel,
    required ProgressCallback onProgress,
  }) async {
    if (_baseUrl.trim().isEmpty) {
      throw const AppException(
        AppErrorKind.unsupported,
        'Configure a VieNeu server URL first.',
      );
    }
    if (_busy) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'A generation is already running.',
      );
    }
    _busy = true;
    try {
      final token = await _secureKeys.read(SecureKeys.vieneuToken) ?? '';
      final chunks = TextChunker.split(request.text, maxChars: maxChunkChars);
      if (chunks.isEmpty) {
        throw const AppException(
          AppErrorKind.invalidRequest,
          'Enter some text to synthesize.',
        );
      }
      onProgress(
        GenerationProgress(
          phase: GenerationPhase.preparing,
          totalChunks: chunks.length,
        ),
      );
      final segments = <Uint8List>[];
      for (var i = 0; i < chunks.length; i++) {
        cancel.throwIfCancelled();
        final bytes = await _client.synthesize(
          text: chunks[i],
          voice: request.voiceId,
          token: token,
        );
        cancel.throwIfCancelled();
        segments.add(bytes);
        onProgress(
          GenerationProgress(
            phase: GenerationPhase.synthesizing,
            completedChunks: i + 1,
            totalChunks: chunks.length,
          ),
        );
      }
      cancel.throwIfCancelled();
      onProgress(
        GenerationProgress(
          phase: GenerationPhase.postProcessing,
          completedChunks: chunks.length,
          totalChunks: chunks.length,
          message: 'Joining audio',
        ),
      );
      final merged = WavCodec.merge(segments, gapMs: 120);
      final file = File(outputPath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(merged, flush: true);
      final audio = WavCodec.parse(merged);
      return SynthesisResult(
        audioPath: outputPath,
        format: AudioFormat.wav,
        sampleRate: audio.sampleRate,
        duration: audio.duration,
        engineId: TtsEngineId.vieneu,
        voiceId: request.voiceId,
        charCount: request.text.length,
        chunkCount: chunks.length,
      );
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> dispose() async => _client.close();
}
