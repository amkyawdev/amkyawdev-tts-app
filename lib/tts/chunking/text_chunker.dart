/// Splits long text into engine-sized segments without breaking words when
/// avoidable.
///
/// Engines call this with their own conservative [maxChars] budget. Sentence
/// enders cover Latin punctuation and the Myanmar section sign (။).
class TextChunker {
  const TextChunker._();

  static const Set<String> _sentenceEnders = {'.', '!', '?', '။', '…'};
  static const List<String> _softBreaks = [' ', ',', ';', ':', '၊'];

  static List<String> split(
    String text, {
    required int maxChars,
    int minChars = 1,
  }) {
    if (maxChars < 16) {
      throw ArgumentError.value(maxChars, 'maxChars', 'Must be at least 16');
    }
    final normalized = text
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .trim();
    if (normalized.isEmpty) return const [];

    final chunks = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) chunks.add(value);
      buffer.clear();
    }

    for (final unit in _splitUnits(normalized)) {
      if (unit.length > maxChars) {
        flush();
        chunks.addAll(_hardSplit(unit, maxChars));
        continue;
      }
      if (buffer.isEmpty) {
        buffer.write(unit);
      } else if (buffer.length + 1 + unit.length <= maxChars) {
        buffer
          ..write(' ')
          ..write(unit);
      } else {
        flush();
        buffer.write(unit);
      }
    }
    flush();

    if (minChars > 1 && chunks.length > 1 && chunks.last.length < minChars) {
      final tail = chunks.removeLast();
      chunks[chunks.length - 1] = '${chunks.last} $tail';
    }
    return chunks;
  }

  static int estimateChunkCount(String text, {required int maxChars}) =>
      split(text, maxChars: maxChars).length;

  static List<String> _splitUnits(String text) {
    final units = <String>[];
    final buffer = StringBuffer();

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) units.add(value);
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\n') {
        flush();
        continue;
      }
      buffer.write(char);
      if (_sentenceEnders.contains(char)) {
        while (i + 1 < text.length &&
            (_sentenceEnders.contains(text[i + 1]) ||
                text[i + 1] == '"' ||
                text[i + 1] == '”' ||
                text[i + 1] == ')')) {
          buffer.write(text[++i]);
        }
        final next = i + 1 < text.length ? text[i + 1] : ' ';
        if (next.trim().isEmpty) flush();
      }
    }
    flush();
    return units;
  }

  static List<String> _hardSplit(String unit, int maxChars) {
    final result = <String>[];
    var remaining = unit.trim();

    while (remaining.length > maxChars) {
      var cut = -1;
      final window = remaining.substring(0, maxChars + 1);
      for (final separator in _softBreaks) {
        final index = window.lastIndexOf(separator);
        if (index > cut && index >= maxChars ~/ 2) cut = index;
      }
      if (cut <= 0) cut = maxChars;
      cut = _safeCut(remaining, cut);

      final piece = remaining.substring(0, cut).trim();
      if (piece.isNotEmpty) result.add(piece);
      remaining = remaining.substring(cut).trim();
    }
    if (remaining.isNotEmpty) result.add(remaining);
    return result;
  }

  /// Avoids splitting a UTF-16 surrogate pair in the middle.
  static int _safeCut(String value, int cut) {
    if (cut <= 0 || cut >= value.length) return cut;
    final unit = value.codeUnitAt(cut - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) return cut - 1;
    return cut;
  }
}
