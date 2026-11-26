import 'package:material_ui/material_ui.dart';

import '../tts/models/audio_format.dart';
import '../tts/models/engine_id.dart';
import 'key_value_store.dart';

enum AppLanguage {
  english('en', 'English'),
  burmese('my', 'မြန်မာ');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;

  static AppLanguage fromCode(String? code) {
    for (final language in AppLanguage.values) {
      if (language.code == code) return language;
    }
    return AppLanguage.english;
  }
}

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.dark,
    this.language = AppLanguage.english,
    this.defaultEngine = TtsEngineId.piper,
    this.defaultVoiceIds = const {
      TtsEngineId.piper: 'lessac',
      TtsEngineId.gemini: 'Kore',
      TtsEngineId.vieneu: 'Mai Anh',
      TtsEngineId.system: '',
    },
    this.speechRate = 1.0,
    this.autoPlay = true,
    this.piperModelId = 'piper-en_US-lessac-medium-int8',
    this.vieneuBaseUrl = '',
    this.outputFormat = AudioFormat.wav,
    this.recentLanguageCodes = const [],
    this.translationModelId = 'qwen3-0.6b-q4km',
  });

  final ThemeMode themeMode;
  final AppLanguage language;
  final TtsEngineId defaultEngine;
  final Map<TtsEngineId, String> defaultVoiceIds;
  final double speechRate;
  final bool autoPlay;
  final String piperModelId;
  final String vieneuBaseUrl;
  final AudioFormat outputFormat;

  /// Most recently used studio languages, newest first. Real usage only.
  final List<String> recentLanguageCodes;

  /// GGUF text model used for offline translation (never for speech).
  final String translationModelId;

  String voiceFor(TtsEngineId engine) => defaultVoiceIds[engine] ?? '';

  AppSettings copyWith({
    ThemeMode? themeMode,
    AppLanguage? language,
    TtsEngineId? defaultEngine,
    Map<TtsEngineId, String>? defaultVoiceIds,
    double? speechRate,
    bool? autoPlay,
    String? piperModelId,
    String? vieneuBaseUrl,
    AudioFormat? outputFormat,
    List<String>? recentLanguageCodes,
    String? translationModelId,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      language: language ?? this.language,
      defaultEngine: defaultEngine ?? this.defaultEngine,
      defaultVoiceIds: defaultVoiceIds ?? this.defaultVoiceIds,
      speechRate: speechRate ?? this.speechRate,
      autoPlay: autoPlay ?? this.autoPlay,
      piperModelId: piperModelId ?? this.piperModelId,
      vieneuBaseUrl: vieneuBaseUrl ?? this.vieneuBaseUrl,
      outputFormat: outputFormat ?? this.outputFormat,
      recentLanguageCodes: recentLanguageCodes ?? this.recentLanguageCodes,
      translationModelId: translationModelId ?? this.translationModelId,
    );
  }
}

class SettingsRepository {
  SettingsRepository(this._store);

  static const String _themeKey = 'settings.theme_mode';
  static const String _languageKey = 'settings.language';
  static const String _engineKey = 'settings.default_engine';
  static const String _rateKey = 'settings.speech_rate';
  static const String _autoPlayKey = 'settings.autoplay';
  static const String _piperModelKey = 'settings.piper_model';
  static const String _vieneuUrlKey = 'settings.vieneu_base_url';
  static const String _outputKey = 'settings.output_format';
  static const String _voicePrefix = 'settings.voice.';
  static const String _recentLanguagesKey = 'settings.recent_languages';
  static const String _translationModelKey = 'settings.translation_model';

  final KeyValueStore _store;

  AppSettings load() {
    final theme = switch (_store.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    final voices = <TtsEngineId, String>{
      ...const AppSettings().defaultVoiceIds,
    };
    for (final engine in TtsEngineId.values) {
      final value = _store.getString('$_voicePrefix${engine.id}');
      if (value != null) voices[engine] = value;
    }
    return AppSettings(
      themeMode: theme,
      language: AppLanguage.fromCode(_store.getString(_languageKey)),
      defaultEngine:
          TtsEngineId.fromId(_store.getString(_engineKey)) ?? TtsEngineId.piper,
      defaultVoiceIds: voices,
      speechRate: (_store.getDouble(_rateKey) ?? 1.0).clamp(0.5, 2.0),
      autoPlay: _store.getBool(_autoPlayKey) ?? true,
      piperModelId:
          _store.getString(_piperModelKey) ?? const AppSettings().piperModelId,
      vieneuBaseUrl: _store.getString(_vieneuUrlKey) ?? '',
      outputFormat:
          AudioFormat.fromExtension(_store.getString(_outputKey) ?? 'wav') ??
          AudioFormat.wav,
      recentLanguageCodes: (_store.getString(_recentLanguagesKey) ?? '')
          .split(',')
          .map((code) => code.trim())
          .where((code) => code.isNotEmpty)
          .take(6)
          .toList(growable: false),
      translationModelId:
          _store.getString(_translationModelKey) ??
          const AppSettings().translationModelId,
    );
  }

  Future<void> save(AppSettings settings) async {
    await _store.setString(_themeKey, settings.themeMode.name);
    await _store.setString(_languageKey, settings.language.code);
    await _store.setString(_engineKey, settings.defaultEngine.id);
    await _store.setDouble(_rateKey, settings.speechRate);
    await _store.setBool(_autoPlayKey, settings.autoPlay);
    await _store.setString(_piperModelKey, settings.piperModelId);
    await _store.setString(_vieneuUrlKey, settings.vieneuBaseUrl.trim());
    await _store.setString(_outputKey, settings.outputFormat.extension);
    await _store.setString(
      _recentLanguagesKey,
      settings.recentLanguageCodes.join(','),
    );
    await _store.setString(_translationModelKey, settings.translationModelId);
    for (final entry in settings.defaultVoiceIds.entries) {
      await _store.setString('$_voicePrefix${entry.key.id}', entry.value);
    }
  }
}
