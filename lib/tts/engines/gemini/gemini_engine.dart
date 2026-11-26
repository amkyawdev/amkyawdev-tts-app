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
import 'gemini_client.dart';
import 'gemini_voices.dart';

class GeminiTtsEngine implements TtsEngine {
  GeminiTtsEngine({
    required GeminiTtsClient client,
    required SecureKeyStore secureKeys,
  }) : _client = client,
       _secureKeys = secureKeys;

  static const int maxChunkChars = 1500;

  final GeminiTtsClient _client;
  final SecureKeyStore _secureKeys;
  bool _busy = false;

  @override
  EngineDescriptor get descriptor => const EngineDescriptor(
    id: TtsEngineId.gemini,
    name: 'Gemini TTS',
    tagline: 'Cloud speech generation',
    description:
        'Google Gemini native speech generation with a user-supplied API key. '
        'Text is sent to Google only when you press Generate.',
    capabilities: EngineCapabilities(
      offline: false,
      requiresNetwork: true,
      requiresApiKey: true,
      requiresModelDownload: false,
      platforms: {EnginePlatform.android, EnginePlatform.ios},
      cancellation: CancellationSupport.betweenSegments,
      supportsVoiceSelection: true,
      supportsSpeed: false,
      supportsStyle: true,
      supportsWaveform: true,
      maxChunkChars: maxChunkChars,
      outputFormats: ['wav'],
    ),
    notes: [
      'Uses gemini-3.8-flash-tts by default; override with GEMINI_TTS_MODEL.',
      'Burmese is listed as supported by Gemini 3.8 Flash TTS, but output quality is not verified by this app.',
      'The API key is stored in platform secure storage, never in history.',
    ],
    docsUrl: 'https://ai.google.dev/gemini-api/docs/speech-generation',
  );

  @override
  Future<EngineStatus> status() async {
    if (_client.config.isBackendProxy) {
      return const EngineStatus.ready('Backend adapter configured');
    }
    final key = await _secureKeys.read(SecureKeys.geminiApiKey);
    if (key == null || key.trim().isEmpty) {
      return const EngineStatus.needsApiKey(
        'Add your Gemini API key in Settings',
      );
    }
    return const EngineStatus.ready('API key stored');
  }

  @override
  Future<List<TtsVoice>> voices() async => geminiPrebuiltVoices;

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
    _busy = true;
    try {
      final key = await _secureKeys.read(SecureKeys.geminiApiKey) ?? '';
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
          message: 'Preparing ${chunks.length} segment(s)',
        ),
      );

      final segments = <Uint8List>[];
      for (var i = 0; i < chunks.length; i++) {
        cancel.throwIfCancelled();
        final bytes = await _client.synthesize(
          apiKey: key,
          text: chunks[i],
          voice: request.voiceId,
          style: request.style,
        );
        cancel.throwIfCancelled();
        WavCodec.parse(bytes);
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
        engineId: TtsEngineId.gemini,
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
