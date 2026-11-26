import 'engine_id.dart';

enum EnginePlatform { android, ios }

enum CancellationSupport {
  /// The engine cannot stop an in-flight request.
  none,

  /// Cancellation takes effect between text segments.
  betweenSegments,

  /// Cancellation can interrupt the active segment.
  immediate,
}

class EngineCapabilities {
  const EngineCapabilities({
    required this.offline,
    required this.requiresNetwork,
    required this.requiresApiKey,
    required this.requiresModelDownload,
    required this.platforms,
    required this.cancellation,
    required this.supportsVoiceSelection,
    required this.supportsSpeed,
    required this.supportsStyle,
    required this.supportsWaveform,
    required this.maxChunkChars,
    this.outputFormats = const [],
  });

  final bool offline;
  final bool requiresNetwork;
  final bool requiresApiKey;
  final bool requiresModelDownload;
  final Set<EnginePlatform> platforms;
  final CancellationSupport cancellation;
  final bool supportsVoiceSelection;
  final bool supportsSpeed;
  final bool supportsStyle;
  final bool supportsWaveform;
  final int maxChunkChars;
  final List<String> outputFormats;

  bool supportsCurrentPlatform(EnginePlatform platform) =>
      platforms.contains(platform);
}

class EngineDescriptor {
  const EngineDescriptor({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.capabilities,
    this.notes = const [],
    this.docsUrl,
  });

  final TtsEngineId id;
  final String name;
  final String tagline;
  final String description;
  final EngineCapabilities capabilities;
  final List<String> notes;
  final String? docsUrl;
}

enum EngineStatusKind { ready, needsSetup, needsApiKey, unsupported, error }

class EngineStatus {
  const EngineStatus({required this.kind, required this.message, this.detail});

  const EngineStatus.ready([this.message = 'Ready'])
    : kind = EngineStatusKind.ready,
      detail = null;

  const EngineStatus.needsSetup(this.message, {this.detail})
    : kind = EngineStatusKind.needsSetup;

  const EngineStatus.needsApiKey([this.message = 'API key required'])
    : kind = EngineStatusKind.needsApiKey,
      detail = null;

  const EngineStatus.unsupported(this.message, {this.detail})
    : kind = EngineStatusKind.unsupported;

  const EngineStatus.error(this.message, {this.detail})
    : kind = EngineStatusKind.error;

  final EngineStatusKind kind;
  final String message;
  final String? detail;

  bool get isReady => kind == EngineStatusKind.ready;
}
