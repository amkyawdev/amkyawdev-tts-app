import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:amkyaw_tts_studio/gguf/gguf_catalog.dart';
import 'package:amkyaw_tts_studio/gguf/gguf_download_manager.dart';
import 'package:amkyaw_tts_studio/services/key_value_store.dart';
import 'package:amkyaw_tts_studio/services/storage_service.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// Small local HTTP server that speaks real HTTP Range semantics.
class _TestServer {
  _TestServer._(this._server, this._body, {required this.honourRange});

  final HttpServer _server;
  final Uint8List _body;
  final bool honourRange;
  int requests = 0;

  static Future<_TestServer> start(
    Uint8List body, {
    bool honourRange = true,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _TestServer._(server, body, honourRange: honourRange);
    server.listen(testServer._handle);
    return testServer;
  }

  Uri url(String path) => Uri.parse('http://127.0.0.1:${_server.port}/$path');

  Future<void> _handle(HttpRequest request) async {
    requests++;
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (honourRange && range != null) {
      final match = RegExp(r'bytes=(\d+)-').firstMatch(range);
      final start = int.parse(match!.group(1)!);
      final slice = _body.sublist(start);
      request.response.statusCode = HttpStatus.partialContent;
      request.response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${_body.length - 1}/${_body.length}',
      );
      request.response.headers.contentLength = slice.length;
      request.response.add(slice);
      await request.response.close();
      return;
    }
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentLength = _body.length;
    request.response.add(_body);
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

GgufTranslationModel _modelWith({
  required String urlPath,
  required Uint8List bytes,
  String? sha256,
}) {
  return GgufTranslationModel(
    id: 'test-model',
    name: 'Test model',
    publisher: 'test',
    repoId: 'test/test',
    files: [
      GgufFileSpec(
        role: GgufFileRole.model,
        path: urlPath,
        sizeBytes: bytes.length,
        sha256: sha256,
      ),
    ],
    architecture: 'llama',
    quantization: 'Q4_K_M',
    contextLength: 8192,
    languages: const ['en'],
    license: 'MIT',
    description: 'test',
    minRamMb: 512,
  );
}

void main() {
  late Directory tempDir;
  late StorageService storage;
  late InMemoryKeyValueStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gguf-test');
    storage = StorageService(
      supportDirectory: () async => tempDir,
      freeSpace: (_) async => 1024 * 1024 * 1024,
    );
    store = InMemoryKeyValueStore();
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('downloads a file, verifies SHA-256 and moves it atomically', () async {
    final body = Uint8List.fromList(List.generate(300000, (i) => i % 251));
    final server = await _TestServer.start(body);
    final manager = GgufDownloadManager(
      storage: storage,
      store: store,
      urlBuilder: (_, file) => server.url(file.name),
    );
    await manager.initialize();
    final model = _modelWith(
      urlPath: 'model.gguf',
      bytes: body,
      sha256: sha256.convert(body).toString(),
    );
    final updates = <GgufDownloadState>[];
    final sub = manager.updates.listen((states) {
      final update = states[model.id];
      if (update != null) updates.add(update);
    });
    await manager.start(model);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();

    expect(manager.stateFor(model.id).status, GgufDownloadStatus.completed);
    final file = await manager.fileFor(model, model.primaryFile);
    expect(await file.exists(), isTrue);
    expect(await file.length(), body.length);
    expect(await manager.isInstalled(model), isTrue);
    expect(updates.last.fraction, 1);
    expect(await manager.verify(model), contains('readable GGUF'));
    await server.close();
    manager.dispose();
  });

  test('resumes a partial download with HTTP Range', () async {
    final body = Uint8List.fromList(
      List.generate(200000, (i) => (i * 7) % 251),
    );
    final server = await _TestServer.start(body);
    final manager = GgufDownloadManager(
      storage: storage,
      store: store,
      urlBuilder: (_, file) => server.url(file.name),
    );
    await manager.initialize();
    final model = _modelWith(
      urlPath: 'model.gguf',
      bytes: body,
      sha256: sha256.convert(body).toString(),
    );
    final part = await manager.partialFor(model, model.primaryFile);
    await part.parent.create(recursive: true);
    await part.writeAsBytes(body.sublist(0, 70000));

    await manager.start(model);
    final file = await manager.fileFor(model, model.primaryFile);
    expect(await file.length(), body.length);
    expect(await file.readAsBytes(), body);
    expect(server.requests, 1);
    await server.close();
    manager.dispose();
  });

  test('restarts safely when the server ignores Range', () async {
    final body = Uint8List.fromList(List.generate(120000, (i) => i % 199));
    final server = await _TestServer.start(body, honourRange: false);
    final manager = GgufDownloadManager(
      storage: storage,
      store: store,
      urlBuilder: (_, file) => server.url(file.name),
    );
    await manager.initialize();
    final model = _modelWith(
      urlPath: 'model.gguf',
      bytes: body,
      sha256: sha256.convert(body).toString(),
    );
    final part = await manager.partialFor(model, model.primaryFile);
    await part.parent.create(recursive: true);
    await part.writeAsBytes(body.sublist(0, 40000));

    await manager.start(model);
    final file = await manager.fileFor(model, model.primaryFile);
    expect(await file.readAsBytes(), body);
    expect(await file.length(), body.length);
    await server.close();
    manager.dispose();
  });

  test('rejects a checksum mismatch and deletes the file', () async {
    final body = Uint8List.fromList(List.generate(50000, (i) => i % 97));
    final server = await _TestServer.start(body);
    final manager = GgufDownloadManager(
      storage: storage,
      store: store,
      urlBuilder: (_, file) => server.url(file.name),
    );
    await manager.initialize();
    final model = _modelWith(
      urlPath: 'model.gguf',
      bytes: body,
      sha256: '0' * 64,
    );
    await manager.start(model);
    final state = manager.stateFor(model.id);
    expect(state.status, GgufDownloadStatus.failed);
    expect(state.error, contains('Checksum'));
    final file = await manager.fileFor(model, model.primaryFile);
    expect(await file.exists(), isFalse);
    expect(await manager.isInstalled(model), isFalse);
    await server.close();
    manager.dispose();
  });

  test(
    'persists state across manager instances and reconciles completed files',
    () async {
      final body = Uint8List.fromList(List.generate(20000, (i) => i % 53));
      final server = await _TestServer.start(body);
      final first = GgufDownloadManager(
        storage: storage,
        store: store,
        urlBuilder: (_, file) => server.url(file.name),
      );
      await first.initialize();
      final model = _modelWith(urlPath: 'model.gguf', bytes: body);
      await first.start(model);
      first.dispose();

      final second = GgufDownloadManager(storage: storage, store: store);
      await second.initialize();
      final restored = second.stateFor(model.id);
      expect(restored.status, GgufDownloadStatus.completed);
      expect(restored.receivedBytes, body.length);
      expect(await second.isInstalled(model), isTrue);

      await second.delete(model);
      expect(await second.isInstalled(model), isFalse);
      expect(second.stateFor(model.id).status, GgufDownloadStatus.idle);
      await server.close();
      second.dispose();
    },
  );

  test('reports a stalled partial download as paused, not completed', () async {
    final body = Uint8List.fromList(List.generate(10000, (i) => i % 13));
    final manager = GgufDownloadManager(storage: storage, store: store);
    await manager.initialize();
    final model = _modelWith(urlPath: 'model.gguf', bytes: body);
    final part = await manager.partialFor(model, model.primaryFile);
    await part.parent.create(recursive: true);
    await part.writeAsBytes(body.sublist(0, 5000));
    await manager.rescan(model);
    final state = manager.stateFor(model.id);
    expect(state.status, GgufDownloadStatus.paused);
    expect(state.receivedBytes, 5000);
    manager.dispose();
  });

  test('catalogue entries point at real HTTPS hosts and licenses', () {
    for (final model in ggufTranslationCatalog) {
      final uri = model.downloadUrl(model.primaryFile);
      expect(uri.scheme, 'https');
      expect(uri.host, 'huggingface.co');
      expect(uri.path, contains('/resolve/main/'));
      expect(model.license, isNotEmpty);
      expect(model.licenseUri(), isNotNull);
    }
  });

  test('brand icon, Android resources and manifest are wired', () async {
    final icon = File('assets/branding/icon.svg');
    expect(await icon.exists(), isTrue);
    final svg = await icon.readAsString();
    expect(svg, contains('viewBox="0 0 512 512"'));
    expect(svg, contains('<linearGradient'));
    expect(svg, isNot(contains('<image')));

    final manifest = await File('android/app/src/main/AndroidManifest.xml')
        .readAsString();
    expect(manifest, contains('android.permission.INTERNET'));
    expect(manifest, contains('android.intent.action.TTS_SERVICE'));
    expect(manifest, contains('@mipmap/ic_launcher'));

    final adaptive = await File(
      'android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
    ).readAsString();
    expect(adaptive, contains('<adaptive-icon'));
    expect(adaptive, contains('@mipmap/ic_launcher_foreground'));
    expect(adaptive, contains('@color/ic_launcher_background'));

    for (final density in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
      expect(
        await File('android/app/src/main/res/mipmap-$density/ic_launcher.png')
            .exists(),
        isTrue,
      );
      expect(
        await File(
          'android/app/src/main/res/mipmap-$density'
          '/ic_launcher_foreground.png',
        ).exists(),
        isTrue,
      );
    }

    final pubspec = await File('pubspec.yaml').readAsString();
    expect(pubspec, contains('assets/branding/'));

    final iosIcon = File(
      'ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    );
    expect(await iosIcon.exists(), isTrue);
    // iOS requires an opaque 1024 icon: PNG colour type 2 (truecolour), no alpha.
    final header = (await iosIcon.readAsBytes()).sublist(0, 32);
    expect(header[25], 2);
  });

  test('TTS engine registry never imports GGUF code', () async {
    final files = Directory('lib/tts')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in files) {
      final source = await file.readAsString();
      expect(
        source.contains('gguf'),
        isFalse,
        reason: '${file.path} must not reference GGUF models for speech',
      );
    }
  });

  test('README states GGUF is translation-only', () async {
    final readme = await File('README.md').readAsString();
    final lower = readme.toLowerCase();
    expect(lower, contains('gguf'));
    expect(lower, contains('translation'));
    expect(lower, contains('speech'));
  });

  test('no secrets are committed', () async {
    final pubspec = await File('pubspec.yaml').readAsString();
    const patterns = ['AIza', 'sk-', 'ghp_', 'BEGIN PRIVATE KEY'];
    for (final pattern in patterns) {
      expect(pubspec.contains(pattern), isFalse);
    }
    expect(Directory('android/app/src/main/res').existsSync(), isTrue);
    expect(
      await File('android/app/google-services.json')
          .exists()
          .catchError((_) => false),
      isFalse,
    );
  });

  test('icon PNG bytes are decodable and correctly sized', () async {
    for (final entry in {
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png': 192,
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher_foreground.png': 432,
      'assets/branding/icon_256.png': 256,
    }.entries) {
      final bytes = await File(entry.key).readAsBytes();
      final data = ByteData.sublistView(bytes);
      expect(data.getUint32(0), 0x89504E47, reason: 'PNG signature');
      final width = data.getUint32(16);
      final height = data.getUint32(20);
      expect(width, entry.value);
      expect(height, entry.value);
      expect(bytes.length, greaterThan(100));
      expect(utf8.decode([0x50, 0x4E, 0x47], allowMalformed: true), 'PNG');
    }
  });
}
