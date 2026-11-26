import 'dart:convert';
import 'dart:typed_data';

/// Subtitle/plain-text parsing that never rewrites timing or cue indices.
///
/// Blocks that are not well-formed cues (VTT NOTE/STYLE, stray text) are kept
/// verbatim so a round-trip export cannot lose data.
enum SubtitleFormat { srt, vtt, plainText }

class DecodedText {
  const DecodedText({
    required this.text,
    required this.encoding,
    this.hadBom = false,
    this.lossy = false,
  });

  final String text;
  final String encoding;
  final bool hadBom;
  final bool lossy;
}

/// UTF-8 first (with or without BOM), then UTF-16 BOMs, then Latin-1.
///
/// Burmese must stay intact, so a UTF-8 failure is never silently decoded with
/// replacement characters unless every other option failed.
DecodedText decodeTextBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: true),
      encoding: 'UTF-16 LE',
      hadBom: true,
    );
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(
      text: _decodeUtf16(bytes.sublist(2), littleEndian: false),
      encoding: 'UTF-16 BE',
      hadBom: true,
    );
  }
  final hasUtf8Bom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final body = hasUtf8Bom ? bytes.sublist(3) : bytes;
  try {
    return DecodedText(
      text: const Utf8Decoder().convert(body),
      encoding: 'UTF-8',
      hadBom: hasUtf8Bom,
    );
  } on FormatException {
    // Windows-1252 / Latin-1 fallback. Burmese is not representable there, so
    // the caller is told the decode was lossy.
    return DecodedText(
      text: latin1.decode(body, allowInvalid: true),
      encoding: 'Latin-1 (fallback)',
      hadBom: hasUtf8Bom,
      lossy: true,
    );
  }
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1],
    );
  }
  return String.fromCharCodes(units);
}

SubtitleFormat detectSubtitleFormat(String filename, String content) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.srt')) return SubtitleFormat.srt;
  if (lower.endsWith('.vtt')) return SubtitleFormat.vtt;
  if (lower.endsWith('.txt')) return SubtitleFormat.plainText;
  final head = content.trimLeft().toUpperCase();
  if (head.startsWith('WEBVTT')) return SubtitleFormat.vtt;
  if (content.contains('-->')) return SubtitleFormat.srt;
  return SubtitleFormat.plainText;
}

class SubtitleCue {
  const SubtitleCue({
    required this.timing,
    required this.textLines,
    this.identifier,
  });

  /// Cue index (SRT) or cue identifier (VTT). Preserved exactly.
  final String? identifier;
  final String timing;
  final List<String> textLines;

  String get text => textLines.join('\n');

  bool get hasTranslatableText =>
      textLines.any((line) => line.trim().isNotEmpty);

  SubtitleCue withTextLines(List<String> lines) =>
      SubtitleCue(identifier: identifier, timing: timing, textLines: lines);
}

class SubtitleBlock {
  const SubtitleBlock.cue(this.cue) : rawLines = null;
  const SubtitleBlock.raw(this.rawLines) : cue = null;

  final SubtitleCue? cue;
  final List<String>? rawLines;
}

class SubtitleDocument {
  const SubtitleDocument({
    required this.format,
    required this.blocks,
    this.headerLines = const [],
    this.newline = '\n',
  });

  final SubtitleFormat format;
  final List<SubtitleBlock> blocks;

  /// `WEBVTT` header and its metadata lines.
  final List<String> headerLines;
  final String newline;

  Iterable<SubtitleCue> get cues =>
      blocks.where((block) => block.cue != null).map((block) => block.cue!);

  int get cueCount => cues.length;

  int get translatableCueCount =>
      cues.where((cue) => cue.hasTranslatableText).length;

  static SubtitleDocument parse(
    String content, {
    SubtitleFormat? format,
    String filename = '',
  }) {
    final newline = content.contains('\r\n') ? '\r\n' : '\n';
    final normalized = content.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final resolved = format ?? detectSubtitleFormat(filename, normalized);
    if (resolved == SubtitleFormat.plainText) {
      return SubtitleDocument(
        format: SubtitleFormat.plainText,
        blocks: [
          SubtitleBlock.raw(
            normalized.replaceFirst(RegExp(r'^\uFEFF'), '').split('\n'),
          ),
        ],
        newline: newline,
      );
    }

    final lines = normalized.replaceFirst(RegExp(r'^\uFEFF'), '').split('\n');
    final header = <String>[];
    var index = 0;
    if (resolved == SubtitleFormat.vtt) {
      if (lines.isNotEmpty &&
          lines.first.trim().toUpperCase().startsWith('WEBVTT')) {
        header.add(lines.first);
        index = 1;
        while (index < lines.length && lines[index].trim().isNotEmpty) {
          header.add(lines[index]);
          index++;
        }
        while (index < lines.length && lines[index].trim().isEmpty) {
          index++;
        }
      }
    }

    final blocks = <SubtitleBlock>[];
    var current = <String>[];
    void flush() {
      if (current.isEmpty) return;
      blocks.add(_parseBlock(current, resolved));
      current = <String>[];
    }

    for (; index < lines.length; index++) {
      final line = lines[index];
      if (line.trim().isEmpty) {
        flush();
      } else {
        current.add(line);
      }
    }
    flush();

    return SubtitleDocument(
      format: resolved,
      blocks: blocks,
      headerLines: header,
      newline: newline,
    );
  }

  static SubtitleBlock _parseBlock(List<String> lines, SubtitleFormat format) {
    final timingIndex = lines.indexWhere((line) => line.contains('-->'));
    if (timingIndex < 0 || timingIndex > 1) {
      return SubtitleBlock.raw(List.of(lines));
    }
    final identifier = timingIndex == 1 ? lines.first.trim() : null;
    return SubtitleBlock.cue(
      SubtitleCue(
        identifier: identifier,
        timing: lines[timingIndex],
        textLines: lines.sublist(timingIndex + 1),
      ),
    );
  }

  /// Replaces cue text in order. Pass exactly [translatableCueCount] strings.
  SubtitleDocument withTranslatedTexts(List<String> texts) {
    if (texts.length != translatableCueCount) {
      throw ArgumentError(
        'Expected $translatableCueCount translations, got ${texts.length}.',
      );
    }
    var position = 0;
    final updated = <SubtitleBlock>[];
    for (final block in blocks) {
      final cue = block.cue;
      if (cue == null || !cue.hasTranslatableText) {
        updated.add(block);
        continue;
      }
      updated.add(
        SubtitleBlock.cue(cue.withTextLines(texts[position++].split('\n'))),
      );
    }
    return SubtitleDocument(
      format: format,
      blocks: updated,
      headerLines: headerLines,
      newline: newline,
    );
  }

  /// Serialises back to the original format, keeping indices, timings and
  /// passthrough blocks byte-for-byte.
  String serialize() {
    if (format == SubtitleFormat.plainText) {
      return blocks
          .firstWhere(
            (block) => block.rawLines != null,
            orElse: () => const SubtitleBlock.raw([]),
          )
          .rawLines!
          .join(newline);
    }
    final buffer = StringBuffer();
    for (final line in headerLines) {
      buffer.write(line);
      buffer.write(newline);
    }
    if (headerLines.isNotEmpty) buffer.write(newline);
    for (final block in blocks) {
      final cue = block.cue;
      if (cue == null) {
        for (final line in block.rawLines ?? const <String>[]) {
          buffer.write(line);
          buffer.write(newline);
        }
        buffer.write(newline);
        continue;
      }
      if (cue.identifier != null) {
        buffer.write(cue.identifier);
        buffer.write(newline);
      }
      buffer.write(cue.timing);
      buffer.write(newline);
      for (final line in cue.textLines) {
        buffer.write(line);
        buffer.write(newline);
      }
      buffer.write(newline);
    }
    var result = buffer.toString();
    if (result.endsWith('$newline$newline')) {
      result = result.substring(0, result.length - newline.length);
    }
    return result;
  }

  /// Human-readable text export: cue text in order, one paragraph per cue.
  String toPlainText() {
    if (format == SubtitleFormat.plainText) {
      return blocks
          .firstWhere(
            (block) => block.rawLines != null,
            orElse: () => const SubtitleBlock.raw([]),
          )
          .rawLines!
          .join('\n')
          .trim();
    }
    return cues
        .where((cue) => cue.hasTranslatableText)
        .map((cue) => cue.text)
        .join('\n\n');
  }
}
