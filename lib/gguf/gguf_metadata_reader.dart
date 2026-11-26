import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gguf_quantization.dart';
import 'models/gguf_metadata.dart';

/// Bounded GGUF metadata inspection. Reads at most 64 MiB; never reads tensors.
class GgufMetadataReader {
  const GgufMetadataReader._();

  static Future<GgufMetadata?> read(String path) async {
    try {
      final file = File(path);
      final length = await file.length();
      final readLength = length < 64 * 1024 * 1024 ? length : 64 * 1024 * 1024;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in file.openRead(0, readLength)) {
        builder.add(chunk);
      }
      return _parse(builder.takeBytes(), path.split(RegExp(r'[/\\]')).last);
    } catch (_) {
      return null;
    }
  }

  static GgufMetadata? _parse(Uint8List bytes, String filename) {
    final r = _Reader(bytes);
    if (r.u32() != 0x46554747) return null;
    final version = r.u32();
    if (version != 2 && version != 3) return null;
    final tensorCount = r.u64();
    final metadataCount = r.u64();
    if (metadataCount > 200000) return null;
    final values = <String, Object?>{};
    for (var i = 0; i < metadataCount; i++) {
      final key = r.str(1 << 20);
      final type = GgufValueType.fromCode(r.u32());
      if (type == null) return null;
      values[key] = _value(r, type, 0);
    }
    final architecture = _str(values['general.architecture']);
    final fileType = _int(values['general.file_type']);
    final audioKeys = values.keys
        .where(
          (k) => const [
            'audio',
            'codec',
            'vocoder',
            'speaker',
            'tts',
          ].any((n) => k.toLowerCase().contains(n)),
        )
        .toList();
    final basename = filename;
    return GgufMetadata(
      version: version,
      tensorCount: tensorCount,
      metadataCount: metadataCount,
      values: values,
      architecture: architecture,
      name: _str(values['general.name']),
      license:
          _str(values['general.license']) ??
          _str(values['general.license.name']),
      languages: _strings(values['general.languages']),
      parameterCount: _int(values['general.parameter_count']),
      fileType: fileType,
      quantization:
          quantizationFromFileType(fileType) ??
          quantizationFromFilename(basename),
      tokenizerModel: _str(values['tokenizer.ggml.model']),
      contextLength: _context(values),
      isProjector:
          (architecture != null &&
              const [
                'clip',
                'mtmd',
                'mmproj',
              ].contains(architecture.toLowerCase())) ||
          basename.toLowerCase().contains('mmproj'),
      audioKeys: audioKeys,
      inspectedAt: DateTime.now(),
    );
  }

  static Object? _value(_Reader r, GgufValueType type, int depth) {
    switch (type) {
      case GgufValueType.uint8:
        return r.u8();
      case GgufValueType.int8:
        return r.i8();
      case GgufValueType.uint16:
        return r.u16();
      case GgufValueType.int16:
        return r.i16();
      case GgufValueType.uint32:
        return r.u32();
      case GgufValueType.int32:
        return r.i32();
      case GgufValueType.float32:
        return r.f32();
      case GgufValueType.bool8:
        return r.u8() != 0;
      case GgufValueType.string:
        return r.str();
      case GgufValueType.uint64:
        return r.u64();
      case GgufValueType.int64:
        return r.i64();
      case GgufValueType.float64:
        return r.f64();
      case GgufValueType.array:
        if (depth > 4) throw const GgufParseException('Array too deep');
        final element = GgufValueType.fromCode(r.u32());
        if (element == null) throw const GgufParseException('Bad array type');
        final count = r.u64();
        if (count > 50000000) throw const GgufParseException('Array too long');
        final preview = <Object?>[];
        for (var i = 0; i < count; i++) {
          if (i < 32) {
            preview.add(_value(r, element, depth + 1));
          } else {
            _skip(r, element, depth + 1);
          }
        }
        return GgufArrayValue(
          elementType: element,
          count: count,
          preview: preview,
        );
    }
  }

  static void _skip(_Reader r, GgufValueType type, int depth) {
    switch (type) {
      case GgufValueType.uint8:
      case GgufValueType.int8:
      case GgufValueType.bool8:
        r.skip(1);
      case GgufValueType.uint16:
      case GgufValueType.int16:
        r.skip(2);
      case GgufValueType.uint32:
      case GgufValueType.int32:
      case GgufValueType.float32:
        r.skip(4);
      case GgufValueType.uint64:
      case GgufValueType.int64:
      case GgufValueType.float64:
        r.skip(8);
      case GgufValueType.string:
        r.skip(r.u64());
      case GgufValueType.array:
        if (depth > 4) throw const GgufParseException('Array too deep');
        final element = GgufValueType.fromCode(r.u32());
        if (element == null) throw const GgufParseException('Bad array type');
        final count = r.u64();
        for (var i = 0; i < count; i++) {
          _skip(r, element, depth + 1);
        }
    }
  }

  static String? _str(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
  static int? _int(Object? value) => value is num ? value.toInt() : null;
  static List<String> _strings(Object? value) {
    if (value is GgufArrayValue) return value.stringValues;
    if (value is String) return [value];
    return const [];
  }

  static int? _context(Map<String, Object?> values) {
    for (final entry in values.entries) {
      if (entry.key.endsWith('.context_length')) return _int(entry.value);
    }
    return null;
  }
}

class _Reader {
  _Reader(this.bytes) : data = ByteData.sublistView(bytes);
  final Uint8List bytes;
  final ByteData data;
  int offset = 0;

  void _need(int n) {
    if (n < 0 || offset + n > bytes.length) {
      throw const GgufParseException('Unexpected end of metadata');
    }
  }

  int u8() {
    _need(1);
    return data.getUint8(offset++);
  }

  int i8() {
    _need(1);
    return data.getInt8(offset++);
  }

  int u16() {
    _need(2);
    final v = data.getUint16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int i16() {
    _need(2);
    final v = data.getInt16(offset, Endian.little);
    offset += 2;
    return v;
  }

  int u32() {
    _need(4);
    final v = data.getUint32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int i32() {
    _need(4);
    final v = data.getInt32(offset, Endian.little);
    offset += 4;
    return v;
  }

  double f32() {
    _need(4);
    final v = data.getFloat32(offset, Endian.little);
    offset += 4;
    return v;
  }

  int u64() {
    _need(8);
    final v = data.getUint64(offset, Endian.little);
    offset += 8;
    return v;
  }

  int i64() {
    _need(8);
    final v = data.getInt64(offset, Endian.little);
    offset += 8;
    return v;
  }

  double f64() {
    _need(8);
    final v = data.getFloat64(offset, Endian.little);
    offset += 8;
    return v;
  }

  String str([int max = 64 * 1024 * 1024]) {
    final n = u64();
    if (n > max) throw const GgufParseException('String too long');
    _need(n);
    final v = utf8.decode(
      bytes.sublist(offset, offset + n),
      allowMalformed: true,
    );
    offset += n;
    return v;
  }

  void skip(int n) {
    _need(n);
    offset += n;
  }
}
