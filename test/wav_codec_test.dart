import 'dart:typed_data';

import 'package:amkyaw_tts_studio/core/errors/app_exception.dart';
import 'package:amkyaw_tts_studio/tts/audio/wav_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WavCodec', () {
    test('encodes, parses and reports duration', () {
      final samples = Int16List.fromList(List.generate(24000, (i) => i % 100));
      final bytes = WavCodec.encode(samples: samples, sampleRate: 24000);

      expect(WavCodec.isWav(bytes), isTrue);
      final audio = WavCodec.parse(bytes);
      expect(audio.sampleRate, 24000);
      expect(audio.channels, 1);
      expect(audio.bitsPerSample, 16);
      expect(audio.duration.inSeconds, 1);
    });

    test('merges matching segments', () {
      final first = WavCodec.encode(
        samples: Int16List.fromList(List.filled(1000, 10)),
        sampleRate: 16000,
      );
      final second = WavCodec.encode(
        samples: Int16List.fromList(List.filled(1000, 20)),
        sampleRate: 16000,
      );
      final merged = WavCodec.merge([first, second], gapMs: 10);
      final audio = WavCodec.parse(merged);
      expect(audio.pcm.length, greaterThan(4000));
      expect(audio.duration, greaterThan(const Duration(milliseconds: 100)));
    });

    test('builds a waveform envelope', () {
      final samples = Int16List.fromList(
        List.generate(4800, (i) => i.isEven ? 16000 : -16000),
      );
      final bytes = WavCodec.encode(samples: samples, sampleRate: 48000);
      final waveform = WavCodec.waveform(bytes, buckets: 24);
      expect(waveform.length, 24);
      expect(waveform.every((value) => value > 0 && value <= 1), isTrue);
    });

    test('rejects non-WAV bytes', () {
      expect(
        () => WavCodec.parse(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<AppException>()),
      );
    });
  });
}
