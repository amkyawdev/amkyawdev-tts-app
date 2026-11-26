import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../../../core/errors/app_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/storage_service.dart';
import '../../models/cancellation_token.dart';
import 'piper_model_manifest.dart';

class PiperModelStatus {
  const PiperModelStatus({
    required this.manifest,
    required this.installed,
    this.modelPath,
    this.tokensPath,
    this.bytesOnDisk = 0,
    this.error,
  });

  final PiperModelManifest manifest;
  final bool installed;
  final String? modelPath;
  final String? tokensPath;
  final int bytesOnDisk;
  final String? error;
}

class PiperModelManager {
  PiperModelManager(this._storage, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final StorageService _storage;
  final http.Client _http;

  Future<Directory> _modelDir(PiperModelManifest manifest) async {
    final base = await _storage.piperDir();
    return Directory(p.join(base.path, manifest.id));
  }

  Future<List<PiperModelStatus>> list() async {
    final result = <PiperModelStatus>[];
    for (final manifest in piperModelManifest) {
      result.add(await status(manifest));
    }
    return result;
  }

  Future<PiperModelStatus> status(PiperModelManifest manifest) async {
    final dir = await _modelDir(manifest);
    if (!await dir.exists()) {
      return PiperModelStatus(manifest: manifest, installed: false);
    }
    final modelFile = await _findFile(dir, 'model.onnx');
    final tokensFile = await _findFile(dir, 'tokens.txt');
    final installed = modelFile != null && tokensFile != null;
    return PiperModelStatus(
      manifest: manifest,
      installed: installed,
      modelPath: modelFile?.path,
      tokensPath: tokensFile?.path,
      bytesOnDisk: await _storage.directoryBytes(dir),
      error: installed ? null : 'Incomplete model directory',
    );
  }

  Future<File?> _findFile(Directory dir, String name) async {
    if (!await dir.exists()) return null;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && p.basename(entity.path) == name) {
        return entity;
      }
    }
    return null;
  }

  Future<PiperModelStatus> download(
    PiperModelManifest manifest, {
    required CancellationToken cancel,
    required void Function(int received, int total) onProgress,
  }) async {
    final dir = await _modelDir(manifest);
    await dir.create(recursive: true);
    final archiveFile = File(p.join(dir.path, 'download.tar.bz2'));
    final partial = File('${archiveFile.path}.part');

    final free = await _storage.freeBytes(dir.path);
    if (free != null && free < manifest.sizeBytes + (32 * 1024 * 1024)) {
      throw AppException(
        AppErrorKind.storage,
        'Not enough free space for ${manifest.name}.',
        detail:
            'Need ${formatBytes(manifest.sizeBytes + 32 * 1024 * 1024)}, '
            'free ${formatBytes(free)}.',
      );
    }

    try {
      if (await partial.exists()) await partial.delete();
      final request = http.Request('GET', Uri.parse(manifest.url));
      final response = await _http.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AppException(
          AppErrorKind.network,
          'Model download failed (${response.statusCode}).',
          retryable: true,
        );
      }
      final total = response.contentLength ?? manifest.sizeBytes;
      final sink = partial.openWrite();
      var received = 0;
      var lastReport = 0;
      await for (final chunk in response.stream) {
        cancel.throwIfCancelled();
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastReport > 120) {
          lastReport = now;
          onProgress(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      onProgress(received, total);

      if (received != manifest.sizeBytes) {
        throw AppException(
          AppErrorKind.storage,
          'Model download was incomplete.',
          detail: 'Expected ${manifest.sizeBytes} bytes, got $received.',
          retryable: true,
        );
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != manifest.sha256) {
        throw const AppException(
          AppErrorKind.storage,
          'Model checksum verification failed.',
          detail: 'The downloaded archive does not match the manifest.',
        );
      }
      await partial.rename(archiveFile.path);
      await _extract(archiveFile, dir);
      await archiveFile.delete();
      final result = await status(manifest);
      if (!result.installed) {
        throw const AppException(
          AppErrorKind.storage,
          'The model archive did not contain the expected files.',
        );
      }
      return result;
    } on AppException {
      await _cleanup(partial);
      rethrow;
    } catch (error) {
      await _cleanup(partial);
      throw AppException(
        AppErrorKind.storage,
        'Could not install the Piper model.',
        detail: error.toString(),
      );
    }
  }

  Future<void> _cleanup(File partial) async {
    if (await partial.exists()) {
      try {
        await partial.delete();
      } catch (_) {}
    }
  }

  Future<void> _extract(File archiveFile, Directory target) async {
    final bytes = await archiveFile.readAsBytes();
    final decompressed = BZip2Decoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(decompressed);
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      final relative = _stripTopLevel(entry.name);
      if (relative.isEmpty) continue;
      final normalized = p.normalize(relative);
      if (p.isAbsolute(normalized) ||
          normalized.split(p.separator).contains('..')) {
        throw const AppException(
          AppErrorKind.storage,
          'Model archive contains an unsafe path.',
        );
      }
      final file = File(p.join(target.path, normalized));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.content, flush: true);
    }
  }

  String _stripTopLevel(String name) {
    final normalized = name.replaceAll('\\', '/');
    final parts = normalized
        .split('/')
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length <= 1) return '';
    return parts.sublist(1).join('/');
  }

  Future<void> delete(PiperModelManifest manifest) async {
    final dir = await _modelDir(manifest);
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
