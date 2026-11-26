import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/errors/app_exception.dart';
import '../../audio/wav_codec.dart';
import '../../models/audio_format.dart';
import '../../models/cancellation_token.dart';
import '../../models/engine_capabilities.dart';
import '../../models/engine_id.dart';
import '../../models/generation_progress.dart';
import '../../models/synthesis.dart';
import '../../models/tts_voice.dart';
import '../../tts_engine.dart';

/// Thin wrapper around the platform speech synthesizer.
///
/// File export is real, but its container depends on the OS. Android produces
/// WAV; iOS may produce CAF. Waveform extraction is only offered for WAV.
class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  final Map<String, Map<String, String>> _voiceMaps = {};
  bool _initialized = false;

  @override
  EngineDescriptor get descriptor => const EngineDescriptor(
    id: TtsEngineId.system,
    name: 'System TTS',
    tagline: 'Device fallback',
    description:
        'Uses the speech synthesizer installed on the device. Availability, '
        'voice quality and offline behaviour depend on the platform engine.',
    capabilities: EngineCapabilities(
      offline: false,
      requiresNetwork: false,
      requiresApiKey: false,
      requiresModelDownload: false,
      platforms: {EnginePlatform.android, EnginePlatform.ios},
      cancellation: CancellationSupport.none,
      supportsVoiceSelection: true,
      supportsSpeed: true,
      supportsStyle: false,
      supportsWaveform: false,
      maxChunkChars: 4000,
      outputFormats: ['wav', 'caf'],
    ),
    notes: [
      'Some installed voices require a network connection; the app cannot verify that per voice.',
      'Android exports WAV; iOS may export CAF. MP3 is never produced.',
    ],
  );

  Future<void> _ensureInitialized() async {
    if (_initialized) return;
    await _tts.awaitSynthCompletion(true);
    _initialized = true;
  }

  @override
  Future<EngineStatus> status() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return const EngineStatus.unsupported(
        'System TTS is only available on Android and iOS in this build.',
      );
    }
    return const EngineStatus.ready('Device speech engine available');
  }

  @override
  Future<List<TtsVoice>> voices() async {
    await _ensureInitialized();
    try {
      final raw = await _tts.getVoices;
      final voices = <TtsVoice>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final map = item.map((key, value) => MapEntry('$key', '$value'));
          final name = map['name'] ?? 'Device voice';
          final locale = map['locale'] ?? 'en-US';
          final id = map['identifier'] ?? '$name|$locale';
          _voiceMaps[id] = map;
          voices.add(
            TtsVoice(
              id: id,
              name: name,
              engineId: TtsEngineId.system,
              languageCode: locale,
              description: locale,
            ),
          );
        }
      }
      if (voices.isEmpty) {
        return const [
          TtsVoice(
            id: 'default',
            name: 'Device default',
            engineId: TtsEngineId.system,
            languageCode: 'device',
            description: 'Uses the platform default voice',
            isDefault: true,
          ),
        ];
      }
      return voices;
    } catch (_) {
      return const [
        TtsVoice(
          id: 'default',
          name: 'Device default',
          engineId: TtsEngineId.system,
          languageCode: 'device',
          description: 'Uses the platform default voice',
          isDefault: true,
        ),
      ];
    }
  }

  @override
  Future<SynthesisResult> synthesize({
    required SynthesisRequest request,
    required String outputPath,
    required CancellationToken cancel,
    required ProgressCallback onProgress,
  }) async {
    await _ensureInitialized();
    onProgress(
      const GenerationProgress(
        phase: GenerationPhase.synthesizing,
        totalChunks: 1,
        completedChunks: 0,
        message: 'Handing text to the device speech engine',
      ),
    );
    final map = _voiceMaps[request.voiceId];
    if (map != null) {
      await _tts.setVoice(map);
      final locale = map['locale'];
      if (locale != null && locale.isNotEmpty) {
        await _tts.setLanguage(locale);
      }
    }
    // flutter_tts uses 0.0-1.0 with ~0.5 as normal speed.
    await _tts.setSpeechRate((request.speed * 0.5).clamp(0.1, 1.0));
    await _tts.awaitSynthCompletion(true);
    final result = await _tts.synthesizeToFile(request.text, outputPath, true);
    if (result != 1) {
      throw AppException(
        AppErrorKind.unsupported,
        'The device speech engine did not produce a file.',
        detail: 'synthesizeToFile returned $result',
      );
    }
    final file = File(outputPath);
    if (!await file.exists()) {
      throw const AppException(
        AppErrorKind.storage,
        'The device speech engine reported success but no file was created.',
      );
    }
    final bytes = await file.readAsBytes();
    final isWav = WavCodec.isWav(bytes);
    final format = isWav ? AudioFormat.wav : AudioFormat.caf;
    final duration = isWav ? WavCodec.durationOf(bytes) : Duration.zero;
    onProgress(
      const GenerationProgress(
        phase: GenerationPhase.completed,
        totalChunks: 1,
        completedChunks: 1,
      ),
    );
    return SynthesisResult(
      audioPath: outputPath,
      format: format,
      sampleRate: isWav ? WavCodec.parse(bytes).sampleRate : 0,
      duration: duration,
      engineId: TtsEngineId.system,
      voiceId: request.voiceId,
      charCount: request.text.length,
      chunkCount: 1,
    );
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}
