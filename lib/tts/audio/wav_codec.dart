import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors/app_exception.dart';

class WavAudio {
  const WavAudio({
    required this.sampleRate,
    required this.channels,
    required this.bitsPerSample,
    required this.pcm,
  });

  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final Uint8List pcm;

  Duration get duration {
    final bytesPerFrame = channels * (bitsPerSample ~/ 8);
    if (bytesPerFrame <= 0 || sampleRate <= 0) return Duration.zero;
    final frames = pcm.length ~/ bytesPerFrame;
    return Duration(microseconds: (frames * 1000000) ~/ sampleRate);
  }
}

/// Minimal, dependency-free RIFF/WAVE reader and writer.
///
/// Only 16-bit PCM is produced. Parsing accepts 16-bit PCM (including
/// WAVE_FORMAT_EXTENSIBLE) and rejects anything the app cannot concatenate.
class WavCodec {
  const WavCodec._();

  static const int _headerSize = 44;

  static bool isWav(Uint8List bytes) {
    if (bytes.length < 12) return false;
    return ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE';
  }

  static WavAudio parse(Uint8List bytes) {
    if (!isWav(bytes)) {
      throw const AppException(
        AppErrorKind.malformedResponse,
        'The audio data is not a RIFF/WAVE file.',
      );
    }
    final data = ByteData.sublistView(bytes);
    var offset = 12;
    int? sampleRate;
    int? channels;
    int? bitsPerSample;
    int? audioFormat;
    Uint8List? pcm;

    while (offset + 8 <= bytes.length) {
      final id = ascii.decode(bytes.sublist(offset, offset + 4));
      final size = data.getUint32(offset + 4, Endian.little);
      final bodyStart = offset + 8;
      if (bodyStart + size > bytes.length) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'The WAV file is truncated.',
        );
      }
      if (id == 'fmt ') {
        if (size < 16) {
          throw const AppException(
            AppErrorKind.malformedResponse,
            'The WAV format block is invalid.',
          );
        }
        audioFormat = data.getUint16(bodyStart, Endian.little);
        channels = data.getUint16(bodyStart + 2, Endian.little);
        sampleRate = data.getUint32(bodyStart + 4, Endian.little);
        bitsPerSample = data.getUint16(bodyStart + 14, Endian.little);
        if (audioFormat == 0xFFFE && size >= 40) {
          // WAVE_FORMAT_EXTENSIBLE stores the real format in the GUID prefix.
          audioFormat = data.getUint16(bodyStart + 24, Endian.little);
        }
      } else if (id == 'data') {
        pcm = bytes.sublist(bodyStart, bodyStart + size);
      }
      offset = bodyStart + size + (size.isOdd ? 1 : 0);
    }

    if (audioFormat != 1 ||
        sampleRate == null ||
        channels == null ||
        bitsPerSample == null ||
        pcm == null) {
      throw const AppException(
        AppErrorKind.malformedResponse,
        'Unsupported WAV encoding. Only 16-bit PCM is supported.',
      );
    }
    if (bitsPerSample != 16 || channels < 1) {
      throw AppException(
        AppErrorKind.malformedResponse,
        'Unsupported WAV layout ($bitsPerSample bit, $channels channels).',
      );
    }
    return WavAudio(
      sampleRate: sampleRate,
      channels: channels,
      bitsPerSample: bitsPerSample,
      pcm: pcm,
    );
  }

  static Uint8List encode({
    required Int16List samples,
    required int sampleRate,
    int channels = 1,
  }) {
    if (sampleRate <= 0 || channels <= 0) {
      throw ArgumentError('Invalid WAV parameters');
    }
    final dataSize = samples.length * 2;
    final bytes = Uint8List(_headerSize + dataSize);
    final data = ByteData.sublistView(bytes);
    _writeAscii(data, 0, 'RIFF');
    data.setUint32(4, 36 + dataSize, Endian.little);
    _writeAscii(data, 8, 'WAVE');
    _writeAscii(data, 12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, channels, Endian.little);
    data.setUint32(24, sampleRate, Endian.little);
    data.setUint32(28, sampleRate * channels * 2, Endian.little);
    data.setUint16(32, channels * 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    _writeAscii(data, 36, 'data');
    data.setUint32(40, dataSize, Endian.little);
    final pcm = bytes.buffer.asInt16List(_headerSize, samples.length);
    pcm.setAll(0, samples);
    return bytes;
  }

  static Uint8List encodeFloat32(
    Float32List samples, {
    required int sampleRate,
    int channels = 1,
  }) {
    final pcm = Int16List(samples.length);
    for (var i = 0; i < samples.length; i++) {
      final value = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      pcm[i] = value;
    }
    return encode(samples: pcm, sampleRate: sampleRate, channels: channels);
  }

  /// Concatenates WAV segments into one file.
  ///
  /// All segments must share sample rate, channel count and bit depth, which is
  /// guaranteed when they come from the same engine and voice.
  static Uint8List merge(List<Uint8List> segments, {int gapMs = 0}) {
    if (segments.isEmpty) {
      throw const AppException(
        AppErrorKind.malformedResponse,
        'No audio segments were produced.',
      );
    }
    final parsed = segments.map(parse).toList(growable: false);
    final first = parsed.first;
    for (final audio in parsed.skip(1)) {
      if (audio.sampleRate != first.sampleRate ||
          audio.channels != first.channels ||
          audio.bitsPerSample != first.bitsPerSample) {
        throw const AppException(
          AppErrorKind.malformedResponse,
          'Audio segments use different formats and cannot be joined.',
        );
      }
    }

    final gapFrames = (first.sampleRate * gapMs) ~/ 1000;
    final gapBytes = gapFrames * first.channels * 2;
    final totalBytes =
        parsed.fold<int>(0, (sum, audio) => sum + audio.pcm.length) +
        (gapBytes * (parsed.length - 1));

    final pcm = Uint8List(totalBytes);
    var offset = 0;
    for (var i = 0; i < parsed.length; i++) {
      pcm.setRange(offset, offset + parsed[i].pcm.length, parsed[i].pcm);
      offset += parsed[i].pcm.length;
      if (gapBytes > 0 && i != parsed.length - 1) {
        offset += gapBytes;
      }
    }

    final samples = Int16List.view(
      pcm.buffer,
      pcm.offsetInBytes,
      pcm.length ~/ 2,
    );
    return encode(
      samples: samples,
      sampleRate: first.sampleRate,
      channels: first.channels,
    );
  }

  static Duration durationOf(Uint8List bytes) => parse(bytes).duration;

  /// Peak-amplitude envelope for the waveform view, normalised to 0..1.
  static List<double> waveform(Uint8List bytes, {int buckets = 96}) {
    if (buckets <= 0) return const [];
    final audio = parse(bytes);
    final frames = audio.pcm.length ~/ (audio.channels * 2);
    if (frames == 0) return List<double>.filled(buckets, 0);
    final samples = audio.pcm.buffer.asInt16List(
      audio.pcm.offsetInBytes,
      audio.pcm.length ~/ 2,
    );
    final framesPerBucket = (frames / buckets).ceil();
    final result = <double>[];

    for (var bucket = 0; bucket < buckets; bucket++) {
      final start = bucket * framesPerBucket;
      if (start >= frames) {
        result.add(0);
        continue;
      }
      final end = (start + framesPerBucket).clamp(0, frames);
      var peak = 0;
      for (var frame = start; frame < end; frame++) {
        for (var channel = 0; channel < audio.channels; channel++) {
          final value = samples[frame * audio.channels + channel].abs();
          if (value > peak) peak = value;
        }
      }
      result.add((peak / 32768).clamp(0.0, 1.0));
    }
    return result;
  }

  static void _writeAscii(ByteData data, int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      data.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
}
