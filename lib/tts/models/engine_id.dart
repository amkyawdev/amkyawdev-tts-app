/// Identifiers for every speech engine exposed by the studio.
enum TtsEngineId {
  piper('piper'),
  gemini('gemini'),
  vieneu('vieneu'),
  system('system');

  const TtsEngineId(this.id);

  final String id;

  static TtsEngineId? fromId(String? value) {
    for (final engine in TtsEngineId.values) {
      if (engine.id == value) return engine;
    }
    return null;
  }
}
