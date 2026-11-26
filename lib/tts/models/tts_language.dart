/// Language metadata for voice discovery.
///
/// Engines report a locale string (`en-US`, `my-MM`, `multi`, `device`, …).
/// This file turns those strings into a stable, searchable description with an
/// English name, a native name and aliases, without inventing coverage: a
/// language only becomes selectable in the studio when a real voice reports it.
class TtsLanguage {
  const TtsLanguage({
    required this.code,
    required this.englishName,
    this.nativeName,
    this.aliases = const [],
    this.isMultilingual = false,
    this.isDeviceDefault = false,
    this.isUnknown = false,
  });

  /// Normalised locale or pseudo-code (`en-US`, `my-MM`, `multi`, `device`).
  final String code;
  final String englishName;
  final String? nativeName;
  final List<String> aliases;

  /// True for engines whose voices are language agnostic and follow the script.
  final bool isMultilingual;

  /// True for the Android/iOS "use whatever the system picked" voice.
  final bool isDeviceDefault;

  /// True when the engine voice carried no usable locale metadata.
  final bool isUnknown;

  static const TtsLanguage multilingual = TtsLanguage(
    code: 'multi',
    englishName: 'Multilingual',
    aliases: ['multi', 'multilingual', 'all languages', 'automatic', 'auto'],
    isMultilingual: true,
  );

  static const TtsLanguage deviceDefault = TtsLanguage(
    code: 'device',
    englishName: 'Device default',
    aliases: ['device', 'system default', 'default voice'],
    isDeviceDefault: true,
  );

  static const TtsLanguage unknown = TtsLanguage(
    code: 'und',
    englishName: 'Unknown language',
    aliases: ['unknown', 'unspecified', 'undetermined'],
    isUnknown: true,
  );

  bool get hasNativeName =>
      nativeName != null &&
      nativeName!.trim().isNotEmpty &&
      nativeName != englishName;

  /// Primary label, e.g. `Burmese · မြန်မာ`.
  String get label =>
      hasNativeName ? '$englishName · $nativeName' : englishName;

  /// Searchable text: code, base code, names and aliases.
  String get searchableText {
    final base = code.contains('-') ? code.split('-').first : code;
    return [
      code,
      base,
      englishName,
      nativeName ?? '',
      ...aliases,
    ].join(' ').toLowerCase();
  }

  @override
  bool operator ==(Object other) => other is TtsLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => 'TtsLanguage($code, $englishName)';
}

/// Lower-cases, trims and normalises separators. Keeps the locale subtags.
String normalizeLanguageCode(String? raw) {
  if (raw == null) return '';
  var value = raw.trim().toLowerCase().replaceAll('_', '-');
  while (value.contains('--')) {
    value = value.replaceAll('--', '-');
  }
  value = value.replaceAll(RegExp(r'^[-\s]+|[-\s]+$'), '');
  switch (value) {
    case '':
    case 'und':
    case 'unknown':
    case 'none':
    case 'null':
      return '';
    case 'multi':
    case 'multilingual':
    case '*':
    case 'auto':
      return 'multi';
    case 'device':
    case 'default':
    case 'system':
    case 'system-default':
      return 'device';
  }
  return value;
}

class _LanguageEntry {
  const _LanguageEntry(this.english, this.native, [this.aliases = const []]);
  final String english;
  final String native;
  final List<String> aliases;
}

class _Variant {
  const _Variant(this.english, this.native);
  final String english;
  final String native;
}

const Map<String, _Variant> _variants = {
  'zh-cn': _Variant('Chinese (Simplified)', '中文（简体）'),
  'zh-sg': _Variant('Chinese (Simplified)', '中文（简体）'),
  'zh-hans': _Variant('Chinese (Simplified)', '中文（简体）'),
  'zh-tw': _Variant('Chinese (Traditional)', '中文（繁體）'),
  'zh-hk': _Variant('Chinese (Traditional)', '中文（繁體）'),
  'zh-mo': _Variant('Chinese (Traditional)', '中文（繁體）'),
  'zh-hant': _Variant('Chinese (Traditional)', '中文（繁體）'),
  'pt-br': _Variant('Portuguese (Brazil)', 'Português (Brasil)'),
  'pt-pt': _Variant('Portuguese (Portugal)', 'Português (Portugal)'),
  'en-gb': _Variant('English (United Kingdom)', 'English (UK)'),
  'en-us': _Variant('English (United States)', 'English (US)'),
  'my-mm': _Variant('Burmese', 'မြန်မာ'),
};

/// Known languages keyed by ISO 639-1 / 639-2 base subtag.
const Map<String, _LanguageEntry> _languages = {
  'af': _LanguageEntry('Afrikaans', 'Afrikaans'),
  'am': _LanguageEntry('Amharic', 'አማርኛ'),
  'ar': _LanguageEntry('Arabic', 'العربية', ['arabic', 'arabi']),
  'as': _LanguageEntry('Assamese', 'অসমীয়া'),
  'az': _LanguageEntry('Azerbaijani', 'Azərbaycan', ['azerbaijani', 'azeri']),
  'be': _LanguageEntry('Belarusian', 'Беларуская'),
  'bg': _LanguageEntry('Bulgarian', 'Български'),
  'bn': _LanguageEntry('Bengali', 'বাংলা', ['bangla']),
  'bs': _LanguageEntry('Bosnian', 'Bosanski'),
  'ca': _LanguageEntry('Catalan', 'Català'),
  'cs': _LanguageEntry('Czech', 'Čeština'),
  'cy': _LanguageEntry('Welsh', 'Cymraeg'),
  'da': _LanguageEntry('Danish', 'Dansk'),
  'de': _LanguageEntry('German', 'Deutsch'),
  'el': _LanguageEntry('Greek', 'Ελληνικά'),
  'en': _LanguageEntry('English', 'English'),
  'es': _LanguageEntry('Spanish', 'Español', ['castilian']),
  'et': _LanguageEntry('Estonian', 'Eesti'),
  'eu': _LanguageEntry('Basque', 'Euskara'),
  'fa': _LanguageEntry('Persian', 'فارسی', ['farsi']),
  'fi': _LanguageEntry('Finnish', 'Suomi'),
  'fil': _LanguageEntry('Filipino', 'Filipino', ['tagalog']),
  'fr': _LanguageEntry('French', 'Français'),
  'ga': _LanguageEntry('Irish', 'Gaeilge'),
  'gl': _LanguageEntry('Galician', 'Galego'),
  'gu': _LanguageEntry('Gujarati', 'ગુજરાતી'),
  'ha': _LanguageEntry('Hausa', 'Hausa'),
  'he': _LanguageEntry('Hebrew', 'עברית', ['iw']),
  'hi': _LanguageEntry('Hindi', 'हिन्दी', ['hindustani']),
  'hr': _LanguageEntry('Croatian', 'Hrvatski'),
  'hu': _LanguageEntry('Hungarian', 'Magyar'),
  'hy': _LanguageEntry('Armenian', 'Հայերեն'),
  'id': _LanguageEntry('Indonesian', 'Bahasa Indonesia', ['bahasa']),
  'ig': _LanguageEntry('Igbo', 'Igbo'),
  'is': _LanguageEntry('Icelandic', 'Íslenska'),
  'it': _LanguageEntry('Italian', 'Italiano'),
  'ja': _LanguageEntry('Japanese', '日本語', ['nihongo', 'jp']),
  'ka': _LanguageEntry('Georgian', 'ქართული'),
  'kk': _LanguageEntry('Kazakh', 'Қазақша'),
  'km': _LanguageEntry('Khmer', 'ខ្មែរ', ['cambodian']),
  'kn': _LanguageEntry('Kannada', 'ಕನ್ನಡ'),
  'ko': _LanguageEntry('Korean', '한국어', ['hangul', 'kr']),
  'lo': _LanguageEntry('Lao', 'ລາວ'),
  'lt': _LanguageEntry('Lithuanian', 'Lietuvių'),
  'lv': _LanguageEntry('Latvian', 'Latviešu'),
  'mk': _LanguageEntry('Macedonian', 'Македонски'),
  'ml': _LanguageEntry('Malayalam', 'മലയാളം'),
  'mn': _LanguageEntry('Mongolian', 'Монгол'),
  'mr': _LanguageEntry('Marathi', 'मराठी'),
  'ms': _LanguageEntry('Malay', 'Bahasa Melayu', ['malaysian']),
  'my': _LanguageEntry('Burmese', 'မြန်မာ', [
    'myanmar',
    'myanma',
    'bamar',
    'bama',
    'burma',
    'မြန်မာစာ',
  ]),
  'ne': _LanguageEntry('Nepali', 'नेपाली', ['nepalese']),
  'nl': _LanguageEntry('Dutch', 'Nederlands', ['flemish']),
  'no': _LanguageEntry('Norwegian', 'Norsk', ['nb', 'nn']),
  'or': _LanguageEntry('Odia', 'ଓଡ଼ିଆ', ['oriya']),
  'pa': _LanguageEntry('Punjabi', 'ਪੰਜਾਬੀ', ['panjabi']),
  'pl': _LanguageEntry('Polish', 'Polski'),
  'ps': _LanguageEntry('Pashto', 'پښتو'),
  'ro': _LanguageEntry('Romanian', 'Română', ['moldavian']),
  'ru': _LanguageEntry('Russian', 'Русский'),
  'si': _LanguageEntry('Sinhala', 'සිංහල', ['sinhalese']),
  'sk': _LanguageEntry('Slovak', 'Slovenčina'),
  'sl': _LanguageEntry('Slovenian', 'Slovenščina'),
  'sq': _LanguageEntry('Albanian', 'Shqip'),
  'sr': _LanguageEntry('Serbian', 'Српски', ['srpski']),
  'su': _LanguageEntry('Sundanese', 'Basa Sunda'),
  'sv': _LanguageEntry('Swedish', 'Svenska'),
  'sw': _LanguageEntry('Swahili', 'Kiswahili'),
  'ta': _LanguageEntry('Tamil', 'தமிழ்'),
  'te': _LanguageEntry('Telugu', 'తెలుగు'),
  'th': _LanguageEntry('Thai', 'ไทย', ['thai']),
  'tl': _LanguageEntry('Filipino', 'Filipino', ['tagalog']),
  'tr': _LanguageEntry('Turkish', 'Türkçe'),
  'uk': _LanguageEntry('Ukrainian', 'Українська'),
  'ur': _LanguageEntry('Urdu', 'اردو'),
  'uz': _LanguageEntry('Uzbek', 'Oʻzbek'),
  'vi': _LanguageEntry('Vietnamese', 'Tiếng Việt', ['vietnamese']),
  'yo': _LanguageEntry('Yoruba', 'Yorùbá'),
  'zh': _LanguageEntry('Chinese', '中文', [
    'mandarin',
    'cantonese',
    'zhongwen',
    'hanyu',
    '汉语',
    '漢語',
    '普通话',
  ]),
  'zu': _LanguageEntry('Zulu', 'isiZulu'),
};

/// Resolves an engine locale string into a searchable [TtsLanguage].
///
/// Unknown but well-formed locales keep their code and are labelled with the
/// code itself instead of being dropped or mislabelled.
TtsLanguage resolveTtsLanguage(String? rawCode) {
  final code = normalizeLanguageCode(rawCode);
  if (code.isEmpty) return TtsLanguage.unknown;
  if (code == 'multi') return TtsLanguage.multilingual;
  if (code == 'device') return TtsLanguage.deviceDefault;

  final variant = _variants[code];
  final base = code.split('-').first;
  final entry = _languages[base] ?? _languages[code];
  if (entry == null) {
    final label = code.length <= 3 ? code.toUpperCase() : code;
    return TtsLanguage(
      code: code,
      englishName: 'Unrecognised language ($label)',
      aliases: [base],
    );
  }
  return TtsLanguage(
    code: code,
    englishName: variant?.english ?? entry.english,
    nativeName: variant?.native ?? entry.native,
    aliases: [
      base,
      ...entry.aliases,
      if (entry.native != (variant?.native ?? entry.native)) entry.native,
    ],
  );
}
