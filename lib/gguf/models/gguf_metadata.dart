/// GGUF scalar/array metadata types from the GGUF specification.
enum GgufValueType {
  uint8(0),
  int8(1),
  uint16(2),
  int16(3),
  uint32(4),
  int32(5),
  float32(6),
  bool8(7),
  string(8),
  array(9),
  uint64(10),
  int64(11),
  float64(12);

  const GgufValueType(this.code);

  final int code;

  static GgufValueType? fromCode(int code) {
    for (final type in GgufValueType.values) {
      if (type.code == code) return type;
    }
    return null;
  }
}

class GgufArrayValue {
  const GgufArrayValue({
    required this.elementType,
    required this.count,
    required this.preview,
  });

  final GgufValueType elementType;
  final int count;

  /// Only the first few elements are retained; the rest are skipped on disk.
  final List<Object?> preview;

  List<String> get stringValues =>
      preview.whereType<String>().toList(growable: false);
}

class GgufMetadata {
  const GgufMetadata({
    required this.version,
    required this.tensorCount,
    required this.metadataCount,
    required this.values,
    required this.architecture,
    required this.name,
    required this.license,
    required this.languages,
    required this.parameterCount,
    required this.fileType,
    required this.quantization,
    required this.tokenizerModel,
    required this.contextLength,
    required this.isProjector,
    required this.audioKeys,
    required this.inspectedAt,
  });

  final int version;
  final int tensorCount;
  final int metadataCount;
  final Map<String, Object?> values;
  final String? architecture;
  final String? name;
  final String? license;
  final List<String> languages;
  final int? parameterCount;
  final int? fileType;
  final String? quantization;
  final String? tokenizerModel;
  final int? contextLength;
  final bool isProjector;
  final List<String> audioKeys;
  final DateTime inspectedAt;

  bool get hasAudioMetadata => audioKeys.isNotEmpty;

  bool get isComplete => architecture != null && architecture!.isNotEmpty;

  Map<String, Object?> toSummaryJson() => {
    'version': version,
    'tensor_count': tensorCount,
    'metadata_count': metadataCount,
    'architecture': architecture,
    'name': name,
    'license': license,
    'languages': languages,
    'parameter_count': parameterCount,
    'file_type': fileType,
    'quantization': quantization,
    'tokenizer_model': tokenizerModel,
    'context_length': contextLength,
    'is_projector': isProjector,
    'audio_keys': audioKeys,
    'inspected_at': inspectedAt.toIso8601String(),
  };
}

class GgufParseException implements Exception {
  const GgufParseException(this.message);

  final String message;

  @override
  String toString() => 'GgufParseException: $message';
}
