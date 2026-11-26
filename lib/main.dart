import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'app_dependencies.dart';
import 'core/theme/app_theme.dart';
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
  runApp(const BootstrapApp());
}

/// Opens platform services before the first frame.
///
/// A failure here used to leave the user with a black screen. It now surfaces
/// as a readable error with a retry action instead of a silent crash.
Future<AppDependencies> bootstrapDependencies() async {
  final prefs = await SharedPreferences.getInstance();
  final keyValueStore = SharedPreferencesStore(prefs);
  final history = await HistoryRepository.openPlatform();
  final storage = StorageService();
  final httpClient = http.Client();
  return AppDependencies(
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
}

class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key, this.bootstrap});

  /// Injection point for tests.
  final Future<AppDependencies> Function()? bootstrap;

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<AppDependencies> _future;

  @override
  void initState() {
    super.initState();
    _future = (widget.bootstrap ?? bootstrapDependencies)();
  }

  void _retry() {
    setState(() {
      _future = (widget.bootstrap ?? bootstrapDependencies)();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AmkyawDev TTS Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: FutureBuilder<AppDependencies>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _BootSplash();
          }
          final error = snapshot.error;
          if (error != null || snapshot.data == null) {
            return _BootFailure(error: error, onRetry: _retry);
          }
          return ProviderScope(
            overrides: [depsProvider.overrideWithValue(snapshot.data!)],
            child: const AmkyawApp(),
          );
        },
      ),
    );
  }
}

class _BootSplash extends StatelessWidget {
  const _BootSplash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BrandMark(size: 72),
            SizedBox(height: 20),
            Text('AmkyawDev TTS Studio'),
            SizedBox(height: 14),
            SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 4)),
          ],
        ),
      ),
    );
  }
}

class _BootFailure extends StatelessWidget {
  const _BootFailure({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BrandMark(size: 56),
              const SizedBox(height: 18),
              Text('Startup failed', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                'The app could not open its local database or preferences. '
                'Your audio and models were not touched.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.outline),
                ),
                child: SelectableText(
                  '${error ?? 'Unknown error'}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
