import '../core/errors/app_exception.dart';
import 'models/engine_id.dart';
import 'tts_engine.dart';

class EngineRegistry {
  EngineRegistry(this.engines);

  final List<TtsEngine> engines;

  TtsEngine byId(TtsEngineId id) {
    for (final engine in engines) {
      if (engine.descriptor.id == id) return engine;
    }
    throw AppException(
      AppErrorKind.unsupported,
      'Engine ${id.id} is not available in this build.',
    );
  }

  Iterable<TtsEngine> get all => engines;
}
