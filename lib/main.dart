import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'providers/app_providers.dart';
import 'services/audio_export_service.dart';
import 'services/history_repository.dart';
import 'services/key_value_store.dart';
import 'services/secure_key_store.dart';
import 'services/settings_repository.dart';
import 'services/storage_service.dart';
import 'tts/engines/gemini/gemini_client.dart';
import 'tts/engines/piper/piper_model_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = SharedPreferencesStore(prefs);
  final history = await HistoryRepository.openPlatform();
  final storage = StorageService();
  final httpClient = http.Client();
  final deps = AppDependencies(
    settingsRepository: SettingsRepository(keyValueStore),
    historyRepository: history,
    storage: storage,
    secureKeys: FlutterSecureKeyStore(),
    piperModels: PiperModelManager(storage, httpClient: httpClient),
    geminiClient: GeminiTtsClient(httpClient: httpClient),
    exportService: AudioExportService(),
    keyValueStore: keyValueStore,
    httpClient: httpClient,
  );
  runApp(
    ProviderScope(
      overrides: [depsProvider.overrideWithValue(deps)],
      child: const AmkyawApp(),
    ),
  );
}
