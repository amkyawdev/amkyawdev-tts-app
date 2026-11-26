import 'package:amkyaw_tts_studio/features/studio/language_picker_sheet.dart';
import 'package:amkyaw_tts_studio/tts/models/engine_id.dart';
import 'package:amkyaw_tts_studio/tts/models/tts_language.dart';
import 'package:amkyaw_tts_studio/tts/models/tts_voice.dart';
import 'package:amkyaw_tts_studio/tts/voices/voice_catalog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _voices = [
  TtsVoice(
    id: 'my_voice',
    name: 'Myanmar Voice',
    engineId: TtsEngineId.system,
    languageCode: 'my-MM',
  ),
  TtsVoice(
    id: 'en_voice',
    name: 'English Voice',
    engineId: TtsEngineId.system,
    languageCode: 'en-US',
  ),
  TtsVoice(
    id: 'zh_voice',
    name: '中文声音',
    engineId: TtsEngineId.system,
    languageCode: 'zh-CN',
  ),
  TtsVoice(
    id: 'ja_voice',
    name: 'Japanese Voice',
    engineId: TtsEngineId.system,
    languageCode: 'ja-JP',
  ),
  TtsVoice(
    id: 'kore',
    name: 'Kore',
    engineId: TtsEngineId.gemini,
    languageCode: 'multi',
  ),
  TtsVoice(
    id: 'nameless',
    name: 'Nameless Voice',
    engineId: TtsEngineId.system,
    languageCode: '',
  ),
];

void main() {
  group('language resolution', () {
    test('normalises separators, case and pseudo codes', () {
      expect(normalizeLanguageCode('MY_mm'), 'my-mm');
      expect(normalizeLanguageCode(' multi '), 'multi');
      expect(normalizeLanguageCode('default'), 'device');
      expect(normalizeLanguageCode(' und '), '');
    });

    test('Burmese resolves with native name and aliases', () {
      final language = resolveTtsLanguage('my-MM');
      expect(language.englishName, 'Burmese');
      expect(language.nativeName, 'မြန်မာ');
      expect(language.searchableText, contains('myanmar'));
      expect(language.label, contains('မြန်မာ'));
    });

    test('Chinese variants carry distinct names', () {
      expect(resolveTtsLanguage('zh-CN').englishName, 'Chinese (Simplified)');
      expect(resolveTtsLanguage('zh-TW').englishName, 'Chinese (Traditional)');
      expect(resolveTtsLanguage('zh-CN').nativeName, '中文（简体）');
    });

    test('unknown but well-formed locale is labelled, never dropped', () {
      final language = resolveTtsLanguage('xx-YY');
      expect(language.englishName, contains('Unrecognised'));
      expect(language.code, 'xx-yy');
    });
  });

  group('voice catalogue', () {
    final catalog = VoiceCatalog(_voices);

    test('groups real voices per language and keeps order stable', () {
      expect(catalog.options.length, 6);
      expect(catalog.options.first.language.isMultilingual, isTrue);
      expect(catalog.options.last.language.isUnknown, isTrue);
      expect(catalog.optionForCode('my-MM')!.voiceCount, 1);
    });

    test('searches English names', () {
      expect(catalog.search('burmese').single.language.code, 'my-mm');
      expect(catalog.search('japanese').single.language.code, 'ja-jp');
    });

    test('searches native scripts including Burmese', () {
      expect(catalog.search('မြန်မာ').single.language.code, 'my-mm');
      expect(catalog.search('中文').single.language.code, 'zh-cn');
      expect(catalog.search('日本語').single.language.code, 'ja-jp');
    });

    test('searches aliases and locale codes', () {
      expect(catalog.search('Myanmar').single.language.code, 'my-mm');
      expect(catalog.search('my-MM').single.language.code, 'my-mm');
      expect(catalog.search('zh').first.language.code, 'zh-cn');
      expect(catalog.search('multi').single.language.code, 'multi');
    });

    test('Burmese search tolerates zero-width characters', () {
      expect(catalog.search('မြန်\u200Bမာ').single.language.code, 'my-mm');
    });

    test(
      'unknown language is still selectable and searchable by voice name',
      () {
        expect(catalog.search('Nameless').single.language.isUnknown, isTrue);
      },
    );

    test('no results for unsupported languages', () {
      expect(catalog.search('klingon'), isEmpty);
      expect(catalog.search('tlh'), isEmpty);
    });

    test('selection keeps a valid voice and falls back to defaults', () {
      expect(
        catalog.resolveVoiceSelection(
          code: 'en-us',
          preferredVoiceId: 'en_voice',
        ),
        'en_voice',
      );
      expect(
        catalog.resolveVoiceSelection(
          code: 'my-mm',
          preferredVoiceId: 'en_voice',
        ),
        'my_voice',
      );
      expect(catalog.voicesForCode('xx-yy'), isEmpty);
      expect(catalog.resolveVoiceSelection(code: 'xx-yy'), '');
    });
  });

  group('language picker sheet', () {
    Future<void> pumpSheet(
      WidgetTester tester, {
      required String selected,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LanguagePickerSheet(
              options: VoiceCatalog(_voices).options,
              selectedCode: selected,
              recentCodes: const ['my-MM'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('filters by Burmese Unicode and returns the selection', (
      tester,
    ) async {
      await pumpSheet(tester, selected: 'en-us');
      await tester.enterText(find.byType(TextField), 'မြန်မာ');
      await tester.pumpAndSettle();
      expect(find.text('Burmese'), findsOneWidget);
      expect(find.text('Japanese'), findsNothing);
      await tester.tap(find.text('Burmese'));
      await tester.pumpAndSettle();
    });

    testWidgets('shows an empty state and clear affordance', (tester) async {
      await pumpSheet(tester, selected: 'en-us');
      await tester.enterText(find.byType(TextField), 'klingon');
      await tester.pumpAndSettle();
      expect(find.textContaining('No languages match'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('English (United States)'), findsOneWidget);
    });

    testWidgets('marks the selected language and groups recents', (
      tester,
    ) async {
      await pumpSheet(tester, selected: 'my-mm');
      expect(find.text('RECENTLY USED'), findsOneWidget);
      expect(find.text('ALL LANGUAGES'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
