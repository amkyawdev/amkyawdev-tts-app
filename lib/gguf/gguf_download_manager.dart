import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../core/errors/app_exception.dart';
import '../services/key_value_store.dart';
import '../services/storage_service.dart';
import '../tts/models/cancellation_token.dart';
import 'gguf_catalog.dart';

enum GgufDownloadStatus {
  idle,
  downloading,
  paused,
  verifying,
  completed,
  failed,
}

class GgufDownloadState {
  const GgufDownloadState({
    required this.modelId,
    this.status = GgufDownloadStatus.idle,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.fileIndex = 0,
    this.fileCount = 0,
    this.error,
    this.updatedAt,
  });

  final String modelId;
  final GgufDownloadStatus status;
  final int receivedBytes;
  final int totalBytes;

  /// 1-based index of the file currently being fetched (model, then companions).
  final int fileIndex;
  final int fileCount;
  final String? error;
  final DateTime? updatedAt;

  bool get isActive => status == GgufDownloadStatus.downloading;

  bool get isComplete => status == GgufDownloadStatus.completed;

  double? get fraction =>
      totalBytes <= 0 ? null : (receivedBytes / totalBytes).clamp(0, 1);

  GgufDownloadState copyWith({
    GgufDownloadStatus? status,
    int? receivedBytes,
    int? totalBytes,
    int? fileIndex,
    int? fileCount,
    String? error,
    bool clearError = false,
  }) {
    return GgufDownloadState(
      modelId: modelId,
      status: status ?? this.status,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      fileIndex: fileIndex ?? this.fileIndex,
      fileCount: fileCount ?? this.fileCount,
      error: clearError ? null : (error ?? this.error),
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
    'modelId': modelId,
    'status': status.name,
    'receivedBytes': receivedBytes,
    'totalBytes': totalBytes,
    'fileIndex': fileIndex,
    'fileCount': fileCount,
    'error': error,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  factory GgufDownloadState.fromJson(Map<String, Object?> json) {
    return GgufDownloadState(
      modelId: json['modelId'] as String? ?? '',
      status: GgufDownloadStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => GgufDownloadStatus.idle,
      ),
      receivedBytes: (json['receivedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      fileIndex: (json['fileIndex'] as num?)?.toInt() ?? 0,
      fileCount: (json['fileCount'] as num?)?.toInt() ?? 0,
      error: json['error'] as String?,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

/// Resumable downloader for GGUF model files.
///
/// Files live in app-specific storage (`<support>/gguf/models/<id>`), so no
/// broad storage permission is needed on Android. Partial data is kept in a
/// `.part` file and resumed with HTTP Range only when the server honours it.
class GgufDownloadManager {
  GgufDownloadManager({
    required this.storage,
    required this.store,
    http.Client? client,
    this.chunkTimeout = const Duration(seconds: 90),
    this.headerTimeout = const Duration(seconds: 60),
    this.urlBuilder,
  }) : _client = client ?? http.Client();

  static const String _stateKey = 'gguf.downloads.v1';
  static const int _storageHeadroomBytes = 32 * 1024 * 1024;

  final StorageService storage;
  final KeyValueStore store;
  final http.Client _client;
  final Duration chunkTimeout;
  final Duration headerTimeout;

  /// Override used by tests and mirrors; production resolves Hugging Face URLs.
  final Uri Function(GgufTranslationModel model, GgufFileSpec file)? urlBuilder;

  final Map<String, GgufDownloadState> _states = {};
  final StreamController<Map<String, GgufDownloadState>> _updates =
      StreamController<Map<String, GgufDownloadState>>.broadcast();
  CancellationToken? _activeToken;
  String? _activeModelId;
  bool _initialized = false;

  Stream<Map<String, GgufDownloadState>> get updates => _updates.stream;

  Map<String, GgufDownloadState> get snapshot => Map.unmodifiable(_states);

  String? get activeModelId => _activeModelId;

  void dispose() {
    _activeToken?.cancel();
    _updates.close();
    _client.close();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    final raw = store.getString(_stateKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is Map) {
              final state = GgufDownloadState.fromJson(
                value.map((key, value) => MapEntry('$key', value)),
              );
              if (state.modelId.isNotEmpty) _states[state.modelId] = state;
            }
          }
        }
      } catch (_) {
        // Corrupt state must never block startup.
      }
    }
    for (final model in ggufTranslationCatalog) {
      await _reconcile(model);
    }
    _emit();
  }

  /// Re-reads disk state without reopening the store. Used after external
  /// changes (file deleted by the OS, app returning to foreground).
  Future<void> refresh() async {
    for (final model in ggufTranslationCatalog) {
      await _reconcile(model);
    }
    _emit();
  }

  /// Reconciles one model, including models injected by tests.
  Future<void> rescan(GgufTranslationModel model) async {
    await _reconcile(model);
    _emit();
  }

  Future<void> _reconcile(GgufTranslationModel model) async {
    final previous = _states[model.id];
    if (await isInstalled(model)) {
      _states[model.id] = GgufDownloadState(
        modelId: model.id,
        status: GgufDownloadStatus.completed,
        receivedBytes: model.totalBytes,
        totalBytes: model.totalBytes,
        fileIndex: model.files.length,
        fileCount: model.files.length,
        updatedAt: previous?.updatedAt ?? DateTime.now(),
      );
      return;
    }
    final partial = await _partialBytes(model);
    if (partial > 0) {
      _states[model.id] = GgufDownloadState(
        modelId: model.id,
        status: GgufDownloadStatus.paused,
        receivedBytes: partial,
        totalBytes: model.totalBytes,
        fileCount: model.files.length,
        error: previous?.error,
        updatedAt: DateTime.now(),
      );
    } else if (previous != null &&
        previous.status != GgufDownloadStatus.downloading &&
        previous.status != GgufDownloadStatus.verifying) {
      _states[model.id] = previous.copyWith(status: GgufDownloadStatus.idle);
    } else {
      _states[model.id] = GgufDownloadState(
        modelId: model.id,
        fileCount: model.files.length,
      );
    }
  }

  GgufDownloadState stateFor(String modelId) =>
      _states[modelId] ?? GgufDownloadState(modelId: modelId);

  Future<Directory> modelDir(GgufTranslationModel model) async {
    final base = await storage.ggufDir();
    return Directory(p.join(base.path, 'models', _safeSegment(model.id)));
  }

  Future<File> fileFor(GgufTranslationModel model, GgufFileSpec spec) async {
    return File(p.join((await modelDir(model)).path, _safeName(spec.name)));
  }

  Future<File> partialFor(GgufTranslationModel model, GgufFileSpec spec) async {
    final file = await fileFor(model, spec);
    return File('${file.path}.part');
  }

  Future<int> _partialBytes(GgufTranslationModel model) async {
    var total = 0;
    for (final spec in model.files) {
      final part = await partialFor(model, spec);
      if (await part.exists()) total += await part.length();
    }
    return total;
  }

  Future<bool> isInstalled(GgufTranslationModel model) async {
    for (final spec in model.files) {
      final file = await fileFor(model, spec);
      if (!await file.exists()) return false;
      if (await file.length() != spec.sizeBytes) return false;
    }
    return true;
  }

  Future<int> installedBytes() async {
    final dir = Directory(p.join((await storage.ggufDir()).path, 'models'));
    return storage.directoryBytes(dir);
  }

  Future<void> start(GgufTranslationModel model) async {
    if (_activeModelId != null && _activeModelId != model.id) {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'Another model is downloading. Pause it before starting a new one.',
      );
    }
    if (await isInstalled(model)) {
      _states[model.id] = stateFor(model.id).copyWith(
        status: GgufDownloadStatus.completed,
        receivedBytes: model.totalBytes,
        totalBytes: model.totalBytes,
        clearError: true,
      );
      _emit();
      return;
    }
    final free = await storage.freeBytes((await modelDir(model)).path);
    if (free != null && free < model.totalBytes + _storageHeadroomBytes) {
      throw AppException(
        AppErrorKind.storage,
        'Not enough free space for ${model.name}.',
        detail:
            'Need about ${(model.totalBytes / 1024 / 1024).round()} MB plus '
            'headroom; ${(free / 1024 / 1024).round()} MB free.',
      );
    }
    final token = CancellationToken();
    _activeToken = token;
    _activeModelId = model.id;
    var completedBytes = 0;
    _states[model.id] = GgufDownloadState(
      modelId: model.id,
      status: GgufDownloadStatus.downloading,
      totalBytes: model.totalBytes,
      fileCount: model.files.length,
      updatedAt: DateTime.now(),
    );
    _emit();
    try {
      for (var index = 0; index < model.files.length; index++) {
        final spec = model.files[index];
        _states[model.id] = stateFor(model.id)
            .copyWith(fileIndex: index + 1, receivedBytes: completedBytes);
        _emit();
        await _fetchFile(
          model: model,
          spec: spec,
          token: token,
          alreadyDone: completedBytes,
          onFileProgress: (received) {
            _states[model.id] = stateFor(model.id)
                .copyWith(receivedBytes: completedBytes + received);
            _emit();
          },
        );
        completedBytes += spec.sizeBytes;
      }
      if (token.isCancelled) throw const CancelledException();
      _states[model.id] = stateFor(model.id).copyWith(
        status: GgufDownloadStatus.completed,
        receivedBytes: model.totalBytes,
        clearError: true,
      );
    } on CancelledException {
      _states[model.id] = stateFor(model.id)
          .copyWith(status: GgufDownloadStatus.paused);
    } on AppException catch (error) {
      _states[model.id] = stateFor(model.id).copyWith(
        status: GgufDownloadStatus.failed,
        error: error.detail == null
            ? error.message
            : '${error.message} ${error.detail}',
      );
    } catch (error) {
      _states[model.id] = stateFor(model.id).copyWith(
        status: GgufDownloadStatus.failed,
        error: 'Download failed: $error',
      );
    } finally {
      _activeModelId = null;
      _activeToken = null;
      _emit();
      await _persist();
    }
  }

  Future<void> _fetchFile({
    required GgufTranslationModel model,
    required GgufFileSpec spec,
    required CancellationToken token,
    required int alreadyDone,
    required void Function(int received) onFileProgress,
  }) async {
    final target = await fileFor(model, spec);
    await target.parent.create(recursive: true);
    if (await target.exists() && await target.length() == spec.sizeBytes) {
      onFileProgress(spec.sizeBytes);
      return;
    }
    if (await target.exists()) await target.delete();
    final part = await partialFor(model, spec);
    var existing = await part.exists() ? await part.length() : 0;
    if (existing > spec.sizeBytes) {
      await part.delete();
      existing = 0;
    }

    var attempts = 0;
    while (existing < spec.sizeBytes) {
      token.throwIfCancelled();
      attempts++;
      try {
        await _fetchInto(
          url: urlBuilder?.call(model, spec) ?? model.downloadUrl(spec),
          part: part,
          existing: existing,
          expectedSize: spec.sizeBytes,
          token: token,
          onReceived: (received) {
            existing = received;
            onFileProgress(received);
          },
        );
      } on AppException catch (error) {
        if (!error.retryable || attempts >= 3) rethrow;
        existing = await part.exists() ? await part.length() : 0;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempts));
        continue;
      } on TimeoutException {
        if (attempts >= 3) {
          throw const AppException(
            AppErrorKind.network,
            'The download stalled.',
            detail: 'Check your connection and resume.',
            retryable: true,
          );
        }
        existing = await part.exists() ? await part.length() : 0;
        continue;
      }
      break;
    }

    final length = await part.exists() ? await part.length() : 0;
    if (length != spec.sizeBytes) {
      throw AppException(
        AppErrorKind.storage,
        'Download incomplete for ${spec.name}.',
        detail: 'Expected ${spec.sizeBytes} bytes, have $length.',
        retryable: true,
      );
    }
    if (spec.sha256 != null) {
      _states[model.id] = stateFor(model.id)
          .copyWith(status: GgufDownloadStatus.verifying);
      _emit();
      final digest = await sha256.bind(part.openRead()).first;
      if (digest.toString() != spec.sha256) {
        await part.delete();
        throw AppException(
          AppErrorKind.storage,
          'Checksum mismatch for ${spec.name}.',
          detail: 'The file was deleted. Download it again.',
        );
      }
      _states[model.id] = stateFor(model.id)
          .copyWith(status: GgufDownloadStatus.downloading);
      _emit();
    }
    await part.rename(target.path);
  }

  Future<void> _fetchInto({
    required Uri url,
    required File part,
    required int existing,
    required int expectedSize,
    required CancellationToken token,
    required void Function(int received) onReceived,
  }) async {
    final request = http.Request('GET', url);
    request.headers['Accept-Encoding'] = 'identity';
    if (existing > 0) {
      request.headers['Range'] = 'bytes=$existing-';
    }
    final response = await _client.send(request).timeout(headerTimeout);
    var resumeFrom = existing;
    if (response.statusCode == 416) {
      // Range not satisfiable: the partial file is unusable, start over.
      if (await part.exists()) await part.delete();
      resumeFrom = 0;
      throw const AppException(
        AppErrorKind.network,
        'Server rejected the resume request.',
        detail: 'Restarting the download.',
        retryable: true,
      );
    }
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw AppException(
        AppErrorKind.network,
        'Download failed with HTTP ${response.statusCode}.',
        retryable: response.statusCode >= 500 || response.statusCode == 429,
      );
    }
    final isPartial = response.statusCode == 206;
    if (resumeFrom > 0 && !isPartial) {
      // The server ignored Range. Never append a full body to a partial file.
      if (await part.exists()) await part.delete();
      resumeFrom = 0;
    }
    if (isPartial) {
      final contentRange = response.headers['content-range'];
      final start = _contentRangeStart(contentRange);
      if (start == null || start != resumeFrom) {
        if (await part.exists()) await part.delete();
        throw const AppException(
          AppErrorKind.network,
          'Server returned an unexpected byte range.',
          detail: 'Restarting the download.',
          retryable: true,
        );
      }
    }
    final total = isPartial
        ? _contentRangeTotal(response.headers['content-range']) ?? expectedSize
        : response.contentLength ?? expectedSize;
    if (total != expectedSize) {
      throw AppException(
        AppErrorKind.storage,
        'Remote file size does not match the catalogue.',
        detail: 'Server says $total bytes, expected $expectedSize.',
      );
    }
    final sink = part.openWrite(
      mode: resumeFrom > 0 ? FileMode.append : FileMode.write,
    );
    var received = resumeFrom;
    try {
      await for (final chunk in response.stream.timeout(chunkTimeout)) {
        token.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        onReceived(received);
        if (received > expectedSize) {
          throw const AppException(
            AppErrorKind.storage,
            'The server sent more data than expected.',
          );
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  int? _contentRangeStart(String? header) {
    final match = RegExp(r'bytes\s+(\d+)-\d+/(\d+|\*)')
        .firstMatch(header ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  int? _contentRangeTotal(String? header) {
    final match = RegExp(r'bytes\s+\d+-\d+/(\d+)').firstMatch(header ?? '');
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  void pause() {
    _activeToken?.cancel();
  }

  /// Stops the transfer and removes partial data for [model].
  Future<void> cancel(GgufTranslationModel model) async {
    if (_activeModelId == model.id) _activeToken?.cancel();
    for (final spec in model.files) {
      final part = await partialFor(model, spec);
      if (await part.exists()) await part.delete();
    }
    _states[model.id] = GgufDownloadState(
      modelId: model.id,
      status: GgufDownloadStatus.idle,
      totalBytes: model.totalBytes,
      fileCount: model.files.length,
      updatedAt: DateTime.now(),
    );
    _emit();
    await _persist();
  }

  Future<void> delete(GgufTranslationModel model) async {
    if (_activeModelId == model.id) {
      _activeToken?.cancel();
      throw const AppException(
        AppErrorKind.invalidRequest,
        'Pause the download before deleting this model.',
      );
    }
    final dir = await modelDir(model);
    if (await dir.exists()) await dir.delete(recursive: true);
    _states[model.id] = GgufDownloadState(
      modelId: model.id,
      fileCount: model.files.length,
      totalBytes: model.totalBytes,
    );
    _emit();
    await _persist();
  }

  /// Re-reads the file header and reports a human-readable problem, or null.
  Future<String?> verify(GgufTranslationModel model) async {
    if (!await isInstalled(model)) return 'The model is not fully downloaded.';
    final file = await fileFor(model, model.primaryFile);
    return validateTranslationModelFile(
      model: model,
      path: file.path,
      fileSize: await file.length(),
    );
  }

  Future<void> _persist() async {
    final payload = jsonEncode({
      for (final entry in _states.entries) entry.key: entry.value.toJson(),
    });
    await store.setString(_stateKey, payload);
  }

  void _emit() {
    if (_updates.isClosed) return;
    _updates.add(Map.unmodifiable(_states));
  }

  String _safeSegment(String value) {
    final cleaned = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return cleaned.isEmpty ? 'model' : cleaned;
  }

  String _safeName(String value) {
    final base = p.basename(value).replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (base.isEmpty || base == '.' || base == '..') {
      throw const AppException(
        AppErrorKind.invalidRequest,
        'The model file name is not safe to store.',
      );
    }
    return base;
  }
}
