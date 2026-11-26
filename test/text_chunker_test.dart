import 'package:amkyaw_tts_studio/tts/chunking/text_chunker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TextChunker', () {
    test('splits long text within the character budget', () {
      final text = List.filled(
        40,
        'This is a sentence with enough words to exercise the chunker.',
      ).join(' ');
      final chunks = TextChunker.split(text, maxChars: 120);

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 120), isTrue);
      expect(chunks.every((chunk) => chunk.trim().isNotEmpty), isTrue);
      expect(
        chunks.join(' ').replaceAll(RegExp(r'\s+'), ' '),
        text.replaceAll(RegExp(r'\s+'), ' '),
      );
    });

    test('keeps short text in one chunk', () {
      expect(TextChunker.split('မင်္ဂလာပါ။', maxChars: 100), ['မင်္ဂလာပါ။']);
    });

    test('splits Burmese sentences on the section sign', () {
      final chunks = TextChunker.split(
        'ပထမစာကြောင်း။ ဒုတိယစာကြောင်း။ တတိယစာကြောင်း။',
        maxChars: 24,
      );
      expect(chunks.length, greaterThanOrEqualTo(2));
      expect(chunks.every((chunk) => chunk.length <= 24), isTrue);
    });

    test('rejects an unusable budget', () {
      expect(
        () => TextChunker.split('hello', maxChars: 4),
        throwsArgumentError,
      );
    });
  });
}
