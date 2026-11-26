import '../models/tts_language.dart';
import '../models/tts_voice.dart';

/// Voices grouped under one language, ready for the picker UI.
class LanguageOption {
  const LanguageOption({required this.language, required this.voices});

  final TtsLanguage language;
  final List<TtsVoice> voices;

  int get voiceCount => voices.length;

  bool get isMultilingual => language.isMultilingual;
  bool get isUnknown => language.isUnknown;
  bool get isDeviceDefault => language.isDeviceDefault;

  /// Locale or pseudo-code shown next to the name.
  String get codeLabel => language.code.toUpperCase();

  String get searchableText =>
      '${language.searchableText} ${voices.map((voice) => voice.name).join(' ')}'
          .toLowerCase();
}

/// Pure, synchronous voice/language indexing shared by the provider and tests.
///
/// Nothing here performs I/O: the catalogue is rebuilt from whatever voices the
/// active engine actually returned, so unsupported languages are never shown.
class VoiceCatalog {
  VoiceCatalog(Iterable<TtsVoice> voices)
    : _voices = List.unmodifiable(voices) {
    _options = _buildOptions(_voices);
    _optionByCode = {
      for (final option in _options) option.language.code: option,
    };
  }

  final List<TtsVoice> _voices;
  late final List<LanguageOption> _options;
  late final Map<String, LanguageOption> _optionByCode;

  List<TtsVoice> get voices => _voices;

  List<LanguageOption> get options => _options;

  bool get isEmpty => _voices.isEmpty;

  LanguageOption? optionForCode(String? code) {
    final normalized = normalizeLanguageCode(code);
    if (normalized.isEmpty) return null;
    return _optionByCode[normalized];
  }

  TtsLanguage? languageForVoice(String? voiceId) {
    if (voiceId == null || voiceId.isEmpty) return null;
    for (final voice in _voices) {
      if (voice.id == voiceId) return resolveTtsLanguage(voice.languageCode);
    }
    return null;
  }

  LanguageOption? optionForVoice(String? voiceId) {
    final language = languageForVoice(voiceId);
    if (language == null) return null;
    return _optionByCode[language.code];
  }

  List<TtsVoice> voicesForCode(String? code) {
    final option = optionForCode(code);
    return option?.voices ?? const [];
  }

  /// Chooses the voice to select for [code], keeping [preferredVoiceId] when it
  /// still belongs to that language.
  String resolveVoiceSelection({
    required String? code,
    String? preferredVoiceId,
  }) {
    final voices = voicesForCode(code);
    if (voices.isEmpty) return '';
    for (final voice in voices) {
      if (voice.id == preferredVoiceId) return voice.id;
    }
    for (final voice in voices) {
      if (voice.isDefault) return voice.id;
    }
    return voices.first.id;
  }

  /// Language to show when a voice was restored from settings.
  String? codeForVoice(String? voiceId) {
    return optionForVoice(voiceId)?.language.code;
  }

  /// Instant, local search across names, native scripts, codes and aliases.
  List<LanguageOption> search(String query) {
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty) return _options;
    final scored = <MapEntry<LanguageOption, int>>[];
    for (final option in _options) {
      final score = _score(option, normalized);
      if (score > 0) scored.add(MapEntry(option, score));
    }
    scored.sort((a, b) {
      final byScore = b.value.compareTo(a.value);
      if (byScore != 0) return byScore;
      return a.key.language.englishName.compareTo(b.key.language.englishName);
    });
    return scored.map((entry) => entry.key).toList(growable: false);
  }

  List<LanguageOption> _buildOptions(List<TtsVoice> voices) {
    final grouped = <String, List<TtsVoice>>{};
    final languages = <String, TtsLanguage>{};
    for (final voice in voices) {
      final language = resolveTtsLanguage(voice.languageCode);
      grouped.putIfAbsent(language.code, () => []).add(voice);
      languages[language.code] = language;
    }
    final options = [
      for (final entry in grouped.entries)
        LanguageOption(language: languages[entry.key]!, voices: entry.value),
    ];
    options.sort((a, b) {
      if (a.language.isMultilingual != b.language.isMultilingual) {
        return a.language.isMultilingual ? -1 : 1;
      }
      if (a.language.isUnknown != b.language.isUnknown) {
        return a.language.isUnknown ? 1 : -1;
      }
      return a.language.englishName.compareTo(b.language.englishName);
    });
    return List.unmodifiable(options);
  }

  int _score(LanguageOption option, String query) {
    final language = option.language;
    final code = language.code.toLowerCase();
    final base = code.split('-').first;
    final english = language.englishName.toLowerCase();
    final native = language.nativeName?.toLowerCase() ?? '';
    final aliases = language.aliases.map((alias) => alias.toLowerCase());

    if (code == query || base == query) return 100;
    if (code.startsWith(query)) return 95;
    if (english == query) return 90;
    if (native.isNotEmpty && native == query) return 90;
    if (aliases.any((alias) => alias == query)) return 85;
    if (english.startsWith(query)) return 80;
    if (native.isNotEmpty && native.startsWith(query)) return 78;
    if (aliases.any((alias) => alias.startsWith(query))) return 76;
    if (english.contains(query)) return 60;
    if (native.isNotEmpty && native.contains(query)) return 58;
    if (aliases.any((alias) => alias.contains(query))) return 56;
    // Voice names help when several voices share one multilingual language.
    if (option.voices.any(
      (voice) => _normalizeQuery(voice.name).contains(query),
    )) {
      return 30;
    }
    return 0;
  }

  /// Lower-cases and strips zero-width characters so Burmese and CJK input
  /// matches regardless of invisible formatting characters pasted by keyboards.
  static String _normalizeQuery(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp('[\u200B-\u200D\uFEFF]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
