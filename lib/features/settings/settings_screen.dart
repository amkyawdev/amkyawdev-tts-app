import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/errors/app_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../../services/secure_key_store.dart';
import '../../tts/engines/piper/piper_model_manifest.dart';
import '../../tts/models/engine_id.dart';
import '../about/about_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _geminiController = TextEditingController();
  final _vieneuUrlController = TextEditingController();
  final _vieneuTokenController = TextEditingController();
  bool _seededVieneu = false;

  @override
  void dispose() {
    _geminiController.dispose();
    _vieneuUrlController.dispose();
    _vieneuTokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final controller = ref.read(settingsProvider.notifier);
    final deps = ref.read(depsProvider);
    if (!_seededVieneu) {
      _seededVieneu = true;
      _vieneuUrlController.text = settings.vieneuBaseUrl;
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const PageHeader(
              eyebrow: 'Preferences',
              title: 'Settings',
              subtitle: 'Keys, defaults, storage and privacy',
            ),
            _Section(
              title: 'Appearance',
              children: [
                _ChoiceRow<ThemeMode>(
                  label: 'Theme',
                  value: settings.themeMode,
                  values: const {
                    ThemeMode.dark: 'Dark',
                    ThemeMode.system: 'System',
                    ThemeMode.light: 'Light',
                  },
                  onChanged: (value) =>
                      controller.update(settings.copyWith(themeMode: value)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Autoplay generated audio'),
                  value: settings.autoPlay,
                  onChanged: (value) =>
                      controller.update(settings.copyWith(autoPlay: value)),
                ),
                Row(
                  children: [
                    const Text('Default speed'),
                    Expanded(
                      child: Slider(
                        value: settings.speechRate,
                        min: 0.5,
                        max: 2,
                        divisions: 15,
                        label: '${settings.speechRate.toStringAsFixed(1)}×',
                        onChanged: (value) => controller.update(
                          settings.copyWith(speechRate: value),
                        ),
                      ),
                    ),
                    Text('${settings.speechRate.toStringAsFixed(1)}×'),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'Default engine',
              children: [
                _ChoiceRow<TtsEngineId>(
                  label: 'Engine',
                  value: settings.defaultEngine,
                  values: {
                    for (final id in TtsEngineId.values) id: _engineLabel(id),
                  },
                  onChanged: (value) => controller.update(
                    settings.copyWith(defaultEngine: value),
                  ),
                ),
                _ChoiceRow<String>(
                  label: 'Piper model',
                  value:
                      piperModelById(settings.piperModelId)?.id ??
                      piperModelManifest.first.id,
                  values: {
                    for (final model in piperModelManifest)
                      model.id:
                          '${model.name} · ${formatBytes(model.sizeBytes)}',
                  },
                  onChanged: (value) =>
                      controller.update(settings.copyWith(piperModelId: value)),
                ),
              ],
            ),
            _Section(
              title: 'Gemini API key',
              children: [
                FutureBuilder<String?>(
                  future: deps.secureKeys.read(SecureKeys.geminiApiKey),
                  builder: (context, snapshot) {
                    final stored =
                        snapshot.data != null && snapshot.data!.isNotEmpty;
                    return Row(
                      children: [
                        StatusDot(
                          color: stored ? AppColors.success : AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          stored
                              ? 'A key is stored in platform secure storage'
                              : 'No key stored',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _geminiController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Paste a Gemini API key',
                    hintText: 'Stored only on this device',
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: _saveGeminiKey,
                        child: const Text('Save key'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: _validateGeminiKey,
                      child: const Text('Validate'),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Delete stored key',
                      onPressed: _deleteGeminiKey,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'The key is never written to history, logs or the README. '
                  'Direct mobile API access is opt-in; a backend proxy can be '
                  'configured at build time with GEMINI_API_BASE_URL.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            _Section(
              title: 'VieNeu server',
              children: [
                TextField(
                  controller: _vieneuUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'Server URL',
                    hintText: 'http://192.168.1.20:8000',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _vieneuTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Optional bearer token',
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _saveVieneu,
                  child: const Text('Save VieNeu settings'),
                ),
                const SizedBox(height: 6),
                Text(
                  'VieNeu is an optional adapter to the official OpenAI-compatible '
                  'server. It does not run on-device in this app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            _Section(
              title: 'Storage',
              children: [
                FutureBuilder<int>(
                  future: deps.storage.audioBytes(),
                  builder: (context, snapshot) => Text(
                    'Audio: ${formatBytes(snapshot.data ?? 0)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 4),
                FutureBuilder<int>(
                  future: deps.storage.modelBytes(),
                  builder: (context, snapshot) => Text(
                    'Models: ${formatBytes(snapshot.data ?? 0)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearHistory,
                        child: const Text('Clear history'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _clearAudio,
                        child: const Text('Delete audio files'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            _Section(
              title: 'Privacy',
              children: [
                Text(
                  'Piper is fully offline after a model download. Gemini sends '
                  'the script and voice name to Google using your key. VieNeu '
                  'sends text to the server URL you configure. History is stored '
                  'in a local SQLite database and never includes API keys.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('About AmkyawDev TTS Studio'),
                  subtitle: const Text(
                    'Version, engine support and limitations',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AboutScreen(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _engineLabel(TtsEngineId id) {
    switch (id) {
      case TtsEngineId.piper:
        return 'Piper ONNX (offline)';
      case TtsEngineId.gemini:
        return 'Gemini TTS (cloud)';
      case TtsEngineId.vieneu:
        return 'VieNeu (server)';
      case TtsEngineId.system:
        return 'System TTS';
    }
  }

  Future<void> _saveGeminiKey() async {
    final value = _geminiController.text.trim();
    if (value.isEmpty) return;
    await ref
        .read(depsProvider)
        .secureKeys
        .write(SecureKeys.geminiApiKey, value);
    _geminiController.clear();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gemini key saved securely.')),
      );
      await ref.read(studioProvider.notifier).refresh();
    }
  }

  Future<void> _validateGeminiKey() async {
    final value = _geminiController.text.trim();
    if (value.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Paste a key first.')));
      return;
    }
    try {
      await ref.read(depsProvider).geminiClient.validateKey(value);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Gemini key accepted.')));
      }
    } on AppException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _deleteGeminiKey() async {
    await ref.read(depsProvider).secureKeys.delete(SecureKeys.geminiApiKey);
    if (mounted) {
      setState(() {});
      await ref.read(studioProvider.notifier).refresh();
    }
  }

  Future<void> _saveVieneu() async {
    await ref
        .read(settingsProvider.notifier)
        .update(
          ref
              .read(settingsProvider)
              .copyWith(vieneuBaseUrl: _vieneuUrlController.text.trim()),
        );
    final token = _vieneuTokenController.text.trim();
    if (token.isNotEmpty) {
      await ref
          .read(depsProvider)
          .secureKeys
          .write(SecureKeys.vieneuToken, token);
      _vieneuTokenController.clear();
    }
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('VieNeu settings saved.')));
      await ref.read(studioProvider.notifier).refresh();
    }
  }

  Future<void> _clearHistory() async {
    await ref.read(historyProvider.notifier).clear();
    if (mounted) setState(() {});
  }

  Future<void> _clearAudio() async {
    final deps = ref.read(depsProvider);
    final dir = await deps.storage.audioDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
      await dir.create(recursive: true);
    }
    if (mounted) setState(() {});
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(letterSpacing: 2.2),
              ),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.values,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> values;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            isExpanded: true,
            value: values.containsKey(value) ? value : null,
            items: values.entries
                .map(
                  (entry) => DropdownMenuItem<T>(
                    value: entry.key,
                    child: Text(entry.value, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}
