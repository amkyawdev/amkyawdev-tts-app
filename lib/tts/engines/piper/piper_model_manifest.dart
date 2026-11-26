class PiperModelManifest {
  const PiperModelManifest({
    required this.id,
    required this.name,
    required this.language,
    required this.quality,
    required this.sampleRate,
    required this.sizeBytes,
    required this.sha256,
    required this.url,
    required this.license,
    required this.notes,
  });

  final String id;
  final String name;
  final String language;
  final String quality;
  final int sampleRate;
  final int sizeBytes;
  final String sha256;
  final String url;
  final String license;
  final String notes;

  String get fileName => '$id.tar.bz2';

  bool get isEnglish => language.toLowerCase().startsWith('en');
}

/// Official sherpa-onnx conversions of Piper VITS models.
///
/// Checksums were computed from the published release assets. The English
/// lessac model does not synthesize Burmese.
const List<PiperModelManifest> piperModelManifest = [
  PiperModelManifest(
    id: 'piper-en_US-lessac-medium-int8',
    name: 'Lessac · medium · int8',
    language: 'en-US',
    quality: 'medium (int8)',
    sampleRate: 22050,
    sizeBytes: 20969179,
    sha256: 'f1c6d0295cf16087b05f80fdca5b44daca5cd78e2c425d419a42ba34929805f9',
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-lessac-medium-int8.tar.bz2',
    license: 'Piper model card / Lessac Blizzard 2013 dataset license; review before redistribution.',
    notes: 'Recommended download. English only. Runs offline with sherpa-onnx + piper-phonemize.',
  ),
  PiperModelManifest(
    id: 'piper-en_US-lessac-medium',
    name: 'Lessac · medium · fp32',
    language: 'en-US',
    quality: 'medium (fp32)',
    sampleRate: 22050,
    sizeBytes: 67230653,
    sha256: '9e3febfacf0abf4270172d2958bcec246032b7e88efc2720840cc80c93de334e',
    url:
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        'vits-piper-en_US-lessac-medium.tar.bz2',
    license: 'Piper model card / Lessac Blizzard 2013 dataset license; review before redistribution.',
    notes: 'Larger download. English only. Same runtime as the int8 model.',
  ),
];

PiperModelManifest? piperModelById(String id) {
  for (final model in piperModelManifest) {
    if (model.id == id) return model;
  }
  return null;
}
