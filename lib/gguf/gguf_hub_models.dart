import 'package:path/path.dart' as p;

class HfRepoRef {
  const HfRepoRef({
    required this.repoId,
    this.revision = 'main',
    this.filePath,
  });

  final String repoId;
  final String revision;
  final String? filePath;

  String get displayRevision => revision;

  /// Accepts `owner/repo`, huggingface.co URLs, and blob/resolve/tree URLs.
  static HfRepoRef? parse(String input) {
    var value = input.trim();
    if (value.isEmpty) return null;
    Uri? uri;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      uri = Uri.tryParse(value);
      if (uri == null) return null;
      if (!const {
        'huggingface.co',
        'www.huggingface.co',
        'hf.co',
      }.contains(uri.host)) {
        return null;
      }
      value = uri.path;
    }
    final segments = value
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .map(Uri.decodeComponent)
        .toList();
    if (segments.length < 2) return null;
    final repoId = '${segments[0]}/${segments[1]}';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*$')
        .hasMatch(repoId)) {
      return null;
    }
    var revision = 'main';
    String? filePath;
    if (segments.length >= 4 &&
        const {'tree', 'blob', 'resolve'}.contains(segments[2])) {
      revision = segments[3];
      if (segments.length > 4) filePath = segments.sublist(4).join('/');
    } else if (segments.length > 2) {
      filePath = segments.sublist(2).join('/');
    }
    return HfRepoRef(repoId: repoId, revision: revision, filePath: filePath);
  }

  Uri apiUri() => Uri.https('huggingface.co', '/api/models/$repoId', {
    'blobs': 'true',
    if (revision != 'main') 'revision': revision,
  });

  Uri resolveUri(String filename) => Uri.https(
    'huggingface.co',
    '/$repoId/resolve/$revision/${filename.split('/').map(Uri.encodeComponent).join('/')}',
  );

  Uri rawCardUri() =>
      Uri.https('huggingface.co', '/$repoId/raw/$revision/README.md');
}

class HfFile {
  const HfFile({
    required this.path,
    required this.size,
    this.sha256,
    this.isProjector = false,
    this.quantization,
  });

  final String path;
  final int size;
  final String? sha256;
  final bool isProjector;
  final String? quantization;

  String get name => p.basename(path);

  bool get isGguf => path.toLowerCase().endsWith('.gguf');
}

class HfRepoInfo {
  const HfRepoInfo({
    required this.ref,
    required this.commitSha,
    required this.license,
    required this.languages,
    required this.gated,
    required this.files,
    this.pipelineTag,
    this.downloads,
  });

  final HfRepoRef ref;
  final String commitSha;
  final String? license;
  final List<String> languages;
  final bool gated;
  final List<HfFile> files;
  final String? pipelineTag;
  final int? downloads;

  List<HfFile> get ggufFiles =>
      files.where((file) => file.isGguf).toList(growable: false);

  List<HfFile> get projectors =>
      ggufFiles.where((file) => file.isProjector).toList(growable: false);
}

class GgufModelEntry {
  const GgufModelEntry({
    required this.id,
    required this.filename,
    required this.localPath,
    required this.sizeBytes,
    required this.importedAt,
    required this.role,
    this.repoId,
    this.revision = 'main',
    this.quantization,
    this.license,
    this.languages = const [],
    this.architecture,
    this.sha256,
    this.metadata = const {},
    this.error,
  });

  final String id;
  final String filename;
  final String localPath;
  final int sizeBytes;
  final DateTime importedAt;
  final String role;
  final String? repoId;
  final String revision;
  final String? quantization;
  final String? license;
  final List<String> languages;
  final String? architecture;
  final String? sha256;
  final Map<String, Object?> metadata;
  final String? error;

  bool get isProjector => role == 'projector';

  Map<String, Object?> toJson() => {
    'id': id,
    'filename': filename,
    'local_path': localPath,
    'size_bytes': sizeBytes,
    'imported_at': importedAt.toIso8601String(),
    'role': role,
    'repo_id': repoId,
    'revision': revision,
    'quantization': quantization,
    'license': license,
    'languages': languages,
    'architecture': architecture,
    'sha256': sha256,
    'metadata': metadata,
    'error': error,
  };

  factory GgufModelEntry.fromJson(Map<String, Object?> json) => GgufModelEntry(
    id: json['id']! as String,
    filename: json['filename']! as String,
    localPath: json['local_path'] as String? ?? '',
    sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
    importedAt:
        DateTime.tryParse(json['imported_at'] as String? ?? '') ??
        DateTime.now(),
    role: json['role'] as String? ?? 'base',
    repoId: json['repo_id'] as String?,
    revision: json['revision'] as String? ?? 'main',
    quantization: json['quantization'] as String?,
    license: json['license'] as String?,
    languages:
        (json['languages'] as List?)?.whereType<String>().toList() ?? const [],
    architecture: json['architecture'] as String?,
    sha256: json['sha256'] as String?,
    metadata:
        (json['metadata'] as Map?)?.map((k, v) => MapEntry('$k', v)) ??
        const {},
    error: json['error'] as String?,
  );
}

enum GgufCompatibilityKind {
  externalRuntime,
  unsupportedArchitecture,
  unsupportedRuntime,
  missingCompanion,
  incompleteMetadata,
  projectorOnly,
}

class GgufCompatibility {
  const GgufCompatibility({
    required this.kind,
    required this.label,
    required this.reason,
    this.canSynthesize = false,
  });

  final GgufCompatibilityKind kind;
  final String label;
  final String reason;
  final bool canSynthesize;
}
