import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

class AudioExportService {
  Future<void> share(String path, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        subject: subject ?? 'AmkyawDev TTS Studio audio',
      ),
    );
  }

  /// Uses the platform save dialog / SAF. Returns false when the user cancels.
  Future<bool> saveCopy(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    final bytes = await file.readAsBytes();
    final uri = await FilePicker.saveFile(
      fileName: p.basename(path),
      bytes: bytes,
      mimeType: 'audio/wav',
      dialogTitle: 'Save TTS audio',
    );
    return uri != null;
  }
}
