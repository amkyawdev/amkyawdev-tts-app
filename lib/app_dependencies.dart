import 'package:http/http.dart' as http;

import 'services/audio_export_service.dart';
import 'services/history_repository.dart';
import 'services/key_value_store.dart';
import 'services/secure_key_store.dart';
import 'services/settings_repository.dart';
import 'services/storage_service.dart';
import 'tts/engines/gemini/gemini_client.dart';
import 'tts/engines/piper/piper_model_manager.dart';

class AppDependencies {
  AppDependencies({
    required this.settingsRepository,
    required this.historyRepository,
    required this.storage,
    required this.secureKeys,
    required this.piperModels,
    required this.geminiClient,
    required this.exportService,
    required this.keyValueStore,
    required this.httpClient,
  });

  final SettingsRepository settingsRepository;
  final HistoryRepository historyRepository;
  final StorageService storage;
  final SecureKeyStore secureKeys;
  final PiperModelManager piperModels;
  final GeminiTtsClient geminiClient;
  final AudioExportService exportService;
  final KeyValueStore keyValueStore;
  final http.Client httpClient;
}
