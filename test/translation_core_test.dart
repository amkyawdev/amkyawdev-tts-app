import 'dart:convert';
import 'dart:typed_data';

import 'package:amkyaw_tts_studio/core/errors/app_exception.dart';
import 'package:amkyaw_tts_studio/gguf/gguf_catalog.dart';
import 'package:amkyaw_tts_studio/providers/translation_providers.dart';
import 'package:amkyaw_tts_studio/translate/subtitle_document.dart';
import 'package:amkyaw_tts_studio/translate/translation_engine.dart';
import 'package:amkyaw_tts_studio/tts/models/cancellation_token.dart';
import 'package:flutter_test/flutter_test.dart';

const _srt =
    '1\r\n'
    '00:00:01,000 --> 00:00:03,500\r\n'
    'မင်္ဂလာပါ\r\n'
    'Second line\r\n'
    '\r\n'
    '2\r\n'
    '00:00:04,000 --> 00:00:06,000\r\n'
    '<i>Hello</i> world\r\n'
    '\r\n'
    '3\r\n'
    '00:00:07,000 --> 00:00:08,000\r\n'
    'Bye\r\n';

class _FakeBackend implements TranslationBackend {
  _FakeBackend({
    this.available = true,
    this.failuresBeforeSuccess = 0,
    this.emptyOutput = false,
  });

  final bool available;
  int failuresBeforeSuccess;
  final bool emptyOutput;
  final List<String> received = [];
  int prepareCalls = 0;

  @override
  String get name => 'Fake local model';

  @override
  TranslationMode get mode => TranslationMode.offline;

  @override
  bool get isReady => available;

  @override
  String? get unavailableReason => available ? null : 'No model installed.';

  @override
  Future<void> prepare({
    required String sourceLanguage,
    required String targetLanguage,
    required int maxChunkChars,
  }) async {
    prepareCalls++;
    if (!available) throw const TranslationException('No model installed.');
  }

  @override
  Future<String> translate(
    String text, {
    required String sourceLanguage,
    required String targetLanguage,
    required CancellationToken cancel,
  }) async {
    if (!available) throw const TranslationException('No model installed.');
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess--;
      throw const TranslationException('Temporary chunk failure');
    }
    received.add(text);
    if (emptyOutput) return '   ';
    return 'MY: $text';
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('SRT parsing', () {
    test('round-trips indices, timings, multiline cues and CRLF', () {
      final document = SubtitleDocument.parse(_srt, filename: 'a.srt');
      expect(document.format, SubtitleFormat.srt);
      expect(document.cueCount, 3);
      expect(document.cues.first.identifier, '1');
      expect(document.cues.first.timing, '00:00:01,000 --> 00:00:03,500');
      expect(document.cues.first.textLines.length, 2);
      expect(document.cues.first.text, contains('မင်္ဂလာပါ'));
      final serialized = document.serialize();
      expect(serialized, contains('00:00:01,000 --> 00:00:03,500'));
      expect(serialized, contains('မင်္ဂလာပါ'));
      expect(serialized, contains('<i>Hello</i> world'));
      // Re-parsing must produce an identical structure.
      final reparsed = SubtitleDocument.parse(serialized, filename: 'a.srt');
      expect(reparsed.cueCount, 3);
      expect(
        reparsed.cues.map((cue) => cue.timing).toList(),
        document.cues.map((cue) => cue.timing).toList(),
      );
    });

    test('translation replaces only cue text', () {
      final document = SubtitleDocument.parse(_srt, filename: 'a.srt');
      final translated = document.withTranslatedTexts([
        'မြန်မာ ၁',
        'မြန်မာ ၂',
        'မြန်မာ ၃',
      ]);
      final output = translated.serialize();
      expect(output, contains('00:00:01,000 --> 00:00:03,500'));
      expect(output, contains('မြန်မာ ၁'));
      expect(output, isNot(contains('မင်္ဂလာပါ')));
      expect(output, contains('3\r\n00:00:07,000'));
    });

    test('rejects a translation count that would drop lines', () {
      final document = SubtitleDocument.parse(_srt, filename: 'a.srt');
      expect(
        () => document.withTranslatedTexts(['only one']),
        throwsArgumentError,
      );
    });

    test('keeps malformed blocks verbatim', () {
      const broken =
          '1\n00:00:01,000 --> 00:00:02,000\nText\n\nNOTE stray block\n';
      final document = SubtitleDocument.parse(broken, filename: 'a.srt');
      expect(document.serialize(), contains('NOTE stray block'));
    });
  });

  group('VTT and TXT', () {
    test('parses VTT header and cues', () {
      const vtt =
          'WEBVTT\n\n'
          'cue-1\n'
          '00:00:01.000 --> 00:00:02.000\n'
          'Hello\n\n'
          '00:00:03.000 --> 00:00:04.000\n'
          'World\n';
      final document = SubtitleDocument.parse(vtt, filename: 'a.vtt');
      expect(document.format, SubtitleFormat.vtt);
      expect(document.cueCount, 2);
      expect(document.cues.first.identifier, 'cue-1');
      expect(document.serialize(), contains('WEBVTT'));
      expect(document.serialize(), contains('00:00:01.000 --> 00:00:02.000'));
    });

    test('plain text keeps Burmese and paragraph order', () {
      const text = 'ပထမ ပိုဒ်\n\nSecond paragraph\n';
      final document = SubtitleDocument.parse(text, filename: 'a.txt');
      expect(document.format, SubtitleFormat.plainText);
      expect(document.toPlainText(), contains('ပထမ ပိုဒ်'));
      expect(document.serialize(), contains('Second paragraph'));
    });
  });

  group('encoding detection', () {
    test('UTF-8 with BOM keeps Burmese intact', () {
      final bytes = Uint8List.fromList([
        0xEF,
        0xBB,
        0xBF,
        ...utf8.encode('မြန်မာ'),
      ]);
      final decoded = decodeTextBytes(bytes);
      expect(decoded.text, 'မြန်မာ');
      expect(decoded.encoding, 'UTF-8');
      expect(decoded.hadBom, isTrue);
      expect(decoded.lossy, isFalse);
    });

    test('UTF-16 LE with BOM decodes', () {
      final units = 'မြန်မာ'.codeUnits;
      final bytes = Uint8List.fromList([
        0xFF,
        0xFE,
        for (final unit in units) ...[unit & 0xFF, unit >> 8],
      ]);
      expect(decodeTextBytes(bytes).text, 'မြန်မာ');
    });

    test('invalid UTF-8 falls back and reports lossy decoding', () {
      final decoded = decodeTextBytes(Uint8List.fromList([0xE9, 0xE8, 0xFF]));
      expect(decoded.lossy, isTrue);
      expect(decoded.encoding, contains('Latin-1'));
    });
  });

  group('chunking', () {
    test('never drops or reorders text', () {
      final text = List.generate(
        40,
        (index) => 'Paragraph $index. ${'word ' * 30}',
      ).join('\n\n');
      final chunks = chunkText(text, maxChars: 240);
      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 240), isTrue);
      expect(chunks.join(), text);
    });

    test('hard-splits a single oversized word without truncation', () {
      final text = 'x' * 1000;
      final chunks = chunkText(text, maxChars: 100);
      expect(chunks.length, 10);
      expect(chunks.join(), text);
    });

    test('rejects unusable limits', () {
      expect(() => chunkText('abc', maxChars: 10), throwsArgumentError);
    });
  });

  group('translation runner', () {
    test('reports real per-chunk progress and preserves order', () async {
      final backend = _FakeBackend();
      final updates = <TranslationProgress>[];
      final runner = TranslationRunner(
        backend: backend,
        chunks: const ['a', 'b', 'c'],
        sourceLanguage: 'en',
        targetLanguage: 'my',
        onProgress: updates.add,
      );
      final result = await runner.run();
      expect(result.translations, ['MY: a', 'MY: b', 'MY: c']);
      expect(updates.last.completedChunks, 3);
      expect(updates.last.fraction, 1);
      expect(
        updates.map((update) => update.stage),
        contains(TranslationStage.translating),
      );
      expect(backend.prepareCalls, 1);
    });

    test('retries a failing chunk once', () async {
      final backend = _FakeBackend(failuresBeforeSuccess: 1);
      final runner = TranslationRunner(
        backend: backend,
        chunks: const ['a'],
        sourceLanguage: 'en',
        targetLanguage: 'my',
        onProgress: (_) {},
      );
      final result = await runner.run();
      expect(result.translations.single, 'MY: a');
    });

    test('fails honestly when the runtime is missing', () async {
      final updates = <TranslationProgress>[];
      final runner = TranslationRunner(
        backend: _FakeBackend(available: false),
        chunks: const ['a'],
        sourceLanguage: 'en',
        targetLanguage: 'my',
        onProgress: updates.add,
      );
      await expectLater(runner.run(), throwsA(isA<TranslationException>()));
      expect(updates.last.stage, TranslationStage.failed);
    });

    test('treats an empty model reply as a failure', () async {
      final runner = TranslationRunner(
        backend: _FakeBackend(emptyOutput: true),
        chunks: const ['a'],
        sourceLanguage: 'en',
        targetLanguage: 'my',
        onProgress: (_) {},
      );
      await expectLater(runner.run(), throwsA(isA<TranslationException>()));
    });

    test('cancellation stops before writing more chunks', () async {
      final token = CancellationToken()..cancel();
      final runner = TranslationRunner(
        backend: _FakeBackend(),
        chunks: const ['a', 'b'],
        sourceLanguage: 'en',
        targetLanguage: 'my',
        onProgress: (_) {},
        cancel: token,
      );
      await expectLater(runner.run(), throwsA(isA<CancelledException>()));
    });
  });

  group('model compatibility gate', () {
    final model = ggufTranslationCatalog.first;

    test('ready only when runtime, architecture and file are present', () {
      final ready = assessTranslationModel(
        model: model,
        runtimeAvailable: true,
        runtimeArchitectures: translationRuntimeArchitectures,
        installed: true,
      );
      expect(ready.readiness, TranslationReadiness.ready);
    });

    test('download-only when the model is not installed', () {
      final assessment = assessTranslationModel(
        model: model,
        runtimeAvailable: true,
        runtimeArchitectures: translationRuntimeArchitectures,
        installed: false,
      );
      expect(assessment.readiness, TranslationReadiness.downloadOnly);
      expect(assessment.reason, contains('Download'));
    });

    test('unsupported architecture is blocked, not attempted', () {
      final assessment = assessTranslationModel(
        model: model,
        runtimeAvailable: true,
        runtimeArchitectures: const {'llama'},
        installed: true,
      );
      expect(assessment.readiness, TranslationReadiness.unsupported);
      expect(assessment.reason, contains('qwen3'));
    });

    test('low RAM produces a warning', () {
      final assessment = assessTranslationModel(
        model: model,
        runtimeAvailable: true,
        runtimeArchitectures: translationRuntimeArchitectures,
        installed: true,
        deviceRamMb: 512,
      );
      expect(assessment.warnings, isNotEmpty);
    });

    test('catalogue only contains non-empty verified metadata', () {
      for (final entry in ggufTranslationCatalog) {
        expect(entry.files, isNotEmpty);
        expect(entry.contextLength, greaterThan(1024));
        expect(entry.license, isNotEmpty);
        expect(entry.hasPublishedChecksums, isTrue);
        expect(entry.recommendedChunkChars, greaterThan(0));
        expect(entry.downloadUrl(entry.primaryFile).host, 'huggingface.co');
      }
    });

    test('search matches architecture and language', () {
      expect(searchGgufTranslationModels('qwen3'), isNotEmpty);
      expect(searchGgufTranslationModels('en').isNotEmpty, isTrue);
      expect(searchGgufTranslationModels('does-not-exist'), isEmpty);
    });
  });
}
