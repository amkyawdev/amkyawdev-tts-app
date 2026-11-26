/// Local translation-model catalogue (GGUF text LLMs).
///
/// GGUF in this app is used exclusively for offline text translation. Speech
/// synthesis stays with Piper, Gemini and VieNeu; no GGUF file is ever offered
/// as a TTS voice.
///
/// Every size, SHA-256 and license was read from the public Hugging Face API
/// (`/api/models/{repo}/tree/main?recursive=true`, whose LFS `oid` is the file
/// SHA-256). Architectures and context lengths were read from the real GGUF
/// header with an HTTP Range request, not from marketing text.
library;

import 'gguf_metadata_reader.dart';

enum GgufFileRole { model, projector, tokenizer }

class GgufFileSpec {
  const GgufFileSpec({
    required this.role,
    required this.path,
    required this.sizeBytes,
    this.sha256,
  });

  final GgufFileRole role;
  final String path;
  final int sizeBytes;

  /// SHA-256 published by Hugging Face as the LFS object id, when present.
  final String? sha256;

  String get name => path.split('/').last;

  bool get isModel => role == GgufFileRole.model;
}

class GgufTranslationModel {
  const GgufTranslationModel({
    required this.id,
    required this.name,
    required this.publisher,
    required this.repoId,
    required this.files,
    required this.architecture,
    required this.quantization,
    required this.contextLength,
    required this.languages,
    required this.license,
    required this.description,
    required this.minRamMb,
    this.revision = 'main',
    this.licenseUrl,
    this.verifiedAt = '2026-11-26',
  });

  final String id;
  final String name;
  final String publisher;
  final String repoId;
  final String revision;
  final List<GgufFileSpec> files;

  /// `general.architecture` from the real file header.
  final String architecture;

  /// `general.file_type` / filename quantization, e.g. Q4_K_M.
  final String quantization;

  /// Context window in tokens, read from the GGUF header.
  final int contextLength;
  final List<String> languages;
  final String license;
  final String? licenseUrl;
  final String description;
  final int minRamMb;
  final String verifiedAt;

  GgufFileSpec get primaryFile =>
      files.firstWhere((file) => file.isModel, orElse: () => files.first);

  int get totalBytes => files.fold(0, (sum, file) => sum + file.sizeBytes);

  bool get hasPublishedChecksums => files.every((file) => file.sha256 != null);

  /// Conservative per-chunk character budget derived from the real context
  /// window, leaving room for the prompt and the generated answer.
  int get recommendedChunkChars {
    final usableTokens = (contextLength * 0.45).floor().clamp(256, 3000);
    // Burmese/CJK tokenise densely; ~2.5 characters per token is conservative.
    return (usableTokens * 2.5).floor().clamp(512, 6000);
  }

  Uri pageUrl() => Uri.https('huggingface.co', '/$repoId');

  Uri downloadUrl(GgufFileSpec file) =>
      Uri.https('huggingface.co', '/$repoId/resolve/$revision/${file.path}');

  Uri? licenseUri() => licenseUrl == null ? null : Uri.tryParse(licenseUrl!);
}

const List<GgufTranslationModel> ggufTranslationCatalog = [
  GgufTranslationModel(
    id: 'qwen3-0.6b-q4km',
    name: 'Qwen3 0.6B (Q4_K_M)',
    publisher: 'unsloth',
    repoId: 'unsloth/Qwen3-0.6B-GGUF',
    files: [
      GgufFileSpec(
        role: GgufFileRole.model,
        path: 'Qwen3-0.6B-Q4_K_M.gguf',
        sizeBytes: 396705472,
        sha256:
            'ac2d97712095a558e31573f62f466a3f9d93990898b0ec79d7c974c1780d524a',
      ),
    ],
    architecture: 'qwen3',
    quantization: 'Q4_K_M',
    contextLength: 40960,
    languages: ['en', 'zh', 'my'],
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/Qwen/Qwen3-0.6B',
    description:
        'Small multilingual instruct model. The upstream model card lists '
        'Burmese among supported languages; translation quality for Burmese is '
        'not verified by this app.',
    minRamMb: 1536,
  ),
  GgufTranslationModel(
    id: 'qwen2.5-0.5b-instruct-q4km',
    name: 'Qwen2.5 0.5B Instruct (Q4_K_M)',
    publisher: 'Qwen',
    repoId: 'Qwen/Qwen2.5-0.5B-Instruct-GGUF',
    files: [
      GgufFileSpec(
        role: GgufFileRole.model,
        path: 'qwen2.5-0.5b-instruct-q4_k_m.gguf',
        sizeBytes: 491400032,
        sha256:
            '74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db',
      ),
    ],
    architecture: 'qwen2',
    quantization: 'Q4_K_M',
    contextLength: 32768,
    languages: ['en', 'zh', 'my'],
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct',
    description:
        'Official Qwen GGUF quantisation. Multilingual instruct model; '
        'Burmese output exists but quality is not verified here.',
    minRamMb: 1792,
  ),
  GgufTranslationModel(
    id: 'smollm2-360m-instruct-q4km',
    name: 'SmolLM2 360M Instruct (Q4_K_M)',
    publisher: 'unsloth',
    repoId: 'unsloth/SmolLM2-360M-Instruct-GGUF',
    files: [
      GgufFileSpec(
        role: GgufFileRole.model,
        path: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
        sizeBytes: 270590560,
        sha256:
            '16c7f1667fea34bacad196a57b548effcb37614db4ab5677a20c8c7b823b9e63',
      ),
    ],
    architecture: 'llama',
    quantization: 'Q4_K_M',
    contextLength: 8192,
    languages: ['en'],
    license: 'Apache-2.0',
    licenseUrl: 'https://huggingface.co/HuggingFaceTB/SmolLM2-360M-Instruct',
    description:
        'Smallest option, English-focused. Useful for low-memory phones and '
        'for quick tests; expect weak Burmese output.',
    minRamMb: 1024,
  ),
];

GgufTranslationModel? ggufTranslationModelById(String id) {
  for (final model in ggufTranslationCatalog) {
    if (model.id == id) return model;
  }
  return null;
}

List<GgufTranslationModel> searchGgufTranslationModels(
  String query, {
  Iterable<GgufTranslationModel> models = ggufTranslationCatalog,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return models.toList(growable: false);
  return models
      .where((model) {
        final haystack = [
          model.name,
          model.publisher,
          model.repoId,
          model.architecture,
          model.license,
          model.quantization,
          ...model.languages,
        ].join(' ').toLowerCase();
        return haystack.contains(q);
      })
      .toList(growable: false);
}

enum TranslationReadiness { ready, downloadOnly, unsupported }

class TranslationAssessment {
  const TranslationAssessment({
    required this.readiness,
    required this.label,
    required this.reason,
    this.missing = const [],
    this.warnings = const [],
  });

  final TranslationReadiness readiness;
  final String label;
  final String reason;
  final List<String> missing;
  final List<String> warnings;
}

/// Validates a model for translation: runtime, architecture, checksum
/// availability, context window, tokenizer and memory.
TranslationAssessment assessTranslationModel({
  required GgufTranslationModel model,
  required bool runtimeAvailable,
  required Set<String> runtimeArchitectures,
  required bool installed,
  int? deviceRamMb,
}) {
  final warnings = <String>[];
  if (deviceRamMb != null && deviceRamMb < model.minRamMb) {
    warnings.add(
      'Model needs about ${model.minRamMb} MB RAM; this device reports '
      '$deviceRamMb MB. Loading may fail.',
    );
  }
  if (!model.hasPublishedChecksums) {
    warnings.add('Upstream publishes no SHA-256 for every file.');
  }
  if (model.contextLength < 1024) {
    return TranslationAssessment(
      readiness: TranslationReadiness.unsupported,
      label: 'Unsupported',
      reason: 'The model context window is too small for subtitle chunks.',
      warnings: warnings,
    );
  }
  if (!runtimeArchitectures.contains(model.architecture)) {
    return TranslationAssessment(
      readiness: TranslationReadiness.unsupported,
      label: 'Unsupported architecture',
      reason:
          'The bundled llama.cpp runtime does not list '
          '${model.architecture}. Loading it would fail.',
      warnings: warnings,
    );
  }
  if (!runtimeAvailable) {
    return TranslationAssessment(
      readiness: TranslationReadiness.downloadOnly,
      label: 'Download only',
      reason: 'The local translation runtime is not available in this build.',
      missing: const [
        'llamadart native llama.cpp runtime for Android (arm64-v8a)',
      ],
      warnings: warnings,
    );
  }
  if (!installed) {
    return TranslationAssessment(
      readiness: TranslationReadiness.downloadOnly,
      label: 'Download to translate',
      reason: 'Download the model file to enable offline translation.',
      warnings: warnings,
    );
  }
  return TranslationAssessment(
    readiness: TranslationReadiness.ready,
    label: 'Translation-ready',
    reason:
        'Model file verified, ${model.contextLength} token context, '
        '${model.quantization} quantisation. Runs offline after the first load.',
    warnings: warnings,
  );
}

/// Reads the real file header and confirms the model is what the catalogue says.
Future<String?> validateTranslationModelFile({
  required GgufTranslationModel model,
  required String path,
  required int fileSize,
}) async {
  final metadata = await GgufMetadataReader.read(path);
  if (metadata == null) return 'Not a readable GGUF file.';
  if (metadata.architecture != model.architecture) {
    return 'Architecture mismatch: file says ${metadata.architecture}, '
        'catalogue says ${model.architecture}.';
  }
  if (fileSize != model.primaryFile.sizeBytes) {
    return 'Size mismatch: on disk $fileSize, expected '
        '${model.primaryFile.sizeBytes}.';
  }
  if (metadata.tokenizerModel == null || metadata.tokenizerModel!.isEmpty) {
    return 'No tokenizer metadata found; the model cannot be prompted.';
  }
  return null;
}
