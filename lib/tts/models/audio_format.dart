/// Container formats the app can actually produce.
///
/// MP3 is intentionally present but marked [implemented] = false: no encoder is
/// bundled, so the UI must never offer it as a working export option.
enum AudioFormat {
  wav('wav', 'audio/wav', implemented: true),
  caf('caf', 'audio/x-caf', implemented: true),
  mp3('mp3', 'audio/mpeg', implemented: false);

  const AudioFormat(this.extension, this.mimeType, {required this.implemented});

  final String extension;
  final String mimeType;
  final bool implemented;

  static AudioFormat? fromExtension(String extension) {
    final normalized = extension.toLowerCase();
    for (final format in AudioFormat.values) {
      if (format.extension == normalized) return format;
    }
    return null;
  }

  static AudioFormat? fromMimeType(String? mimeType) {
    if (mimeType == null) return null;
    final normalized = mimeType.toLowerCase();
    if (normalized.contains('wav')) return AudioFormat.wav;
    if (normalized.contains('caf')) return AudioFormat.caf;
    if (normalized.contains('mpeg') || normalized.contains('mp3')) {
      return AudioFormat.mp3;
    }
    return null;
  }
}
