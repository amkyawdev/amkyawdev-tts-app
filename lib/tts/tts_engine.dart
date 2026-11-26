import 'models/cancellation_token.dart';
import 'models/engine_capabilities.dart';
import 'models/generation_progress.dart';
import 'models/synthesis.dart';
import 'models/tts_voice.dart';

typedef ProgressCallback = void Function(GenerationProgress progress);

/// Contract implemented by every speech engine.
///
/// Engines write a real audio file to [outputPath]. They must never return
/// placeholder or mock audio in production.
abstract class TtsEngine {
  EngineDescriptor get descriptor;

  Future<EngineStatus> status();

  Future<List<TtsVoice>> voices();

  Future<SynthesisResult> synthesize({
    required SynthesisRequest request,
    required String outputPath,
    required CancellationToken cancel,
    required ProgressCallback onProgress,
  });

  Future<void> dispose();
}
