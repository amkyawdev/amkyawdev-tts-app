import 'audio_format.dart';
import 'engine_id.dart';

class SynthesisRequest {
  const SynthesisRequest({
    required this.text,
    required this.voiceId,
    required this.speed,
    this.style,
  });

  final String text;
  final String voiceId;
  final double speed;
  final String? style;
}

class SynthesisResult {
  const SynthesisResult({
    required this.audioPath,
    required this.format,
    required this.sampleRate,
    required this.duration,
    required this.engineId,
    required this.voiceId,
    required this.charCount,
    required this.chunkCount,
  });

  final String audioPath;
  final AudioFormat format;
  final int sampleRate;
  final Duration duration;
  final TtsEngineId engineId;
  final String voiceId;
  final int charCount;
  final int chunkCount;
}
