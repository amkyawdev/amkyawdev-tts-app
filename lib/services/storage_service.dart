import 'dart:io';

import 'package:disk_space_plus/disk_space_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../tts/models/audio_format.dart';

class StorageService {
  StorageService({
    Future<Directory> Function()? supportDirectory,
    Future<double?> Function(String path)? freeSpace,
  }) : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory,
       _freeSpace =
           freeSpace ??
           ((path) => DiskSpacePlus().getFreeDiskSpaceForPath(path));

  final Future<Directory> Function() _supportDirectory;
  final Future<double?> Function(String path) _freeSpace;

  Future<Directory> supportDir() async {
    final dir = await _supportDirectory();
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> audioDir() async {
    final dir = Directory(p.join((await supportDir()).path, 'audio'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> piperDir() async {
    final dir = Directory(p.join((await supportDir()).path, 'piper'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> ggufDir() async {
    final dir = Directory(p.join((await supportDir()).path, 'gguf'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> newAudioPath(AudioFormat format) async {
    final dir = await audioDir();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(dir.path, 'tts_$stamp.${format.extension}');
  }

  Future<int> directoryBytes(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // Ignore files that disappear during the walk.
        }
      }
    }
    return total;
  }

  Future<int> audioBytes() async => directoryBytes(await audioDir());

  Future<int> modelBytes() async =>
      await directoryBytes(await piperDir()) +
      await directoryBytes(await ggufDir());

  Future<void> deleteFile(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int?> freeBytes(String path) async {
    try {
      final value = await _freeSpace(path);
      return value?.round();
    } catch (_) {
      return null;
    }
  }
}
