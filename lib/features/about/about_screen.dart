import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'AmkyawDev TTS Studio',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Version 0.1.0 (build 1)',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          const _Block(
            title: 'Engine status in this build',
            body:
                'Piper ONNX: real offline inference code, English lessac model, '
                'downloaded on demand; device execution is not yet verified.\n\n'
                'Gemini TTS: real REST client for gemini-3.8-flash-tts; requires '
                'your own API key; cloud quality is not verified here.\n\n'
                'VieNeu: HTTP adapter to the official OpenAI-compatible server; '
                'no on-device inference.\n\n'
                'System TTS: platform speech engine file synthesis; Android WAV, '
                'iOS may produce CAF.\n\n'
                'GGUF Hub: planned/experimental. No generic GGUF TTS runtime is '
                'claimed or enabled.',
          ),
          const _Block(
            title: 'Known limitations',
            body:
                '• No Burmese offline voice is bundled; the Piper catalogue is English.\n'
                '• MP3 export is disabled because no MP3 encoder is bundled.\n'
                '• APK/AAB from CI are debug/test-signed unless all four Android '
                'signing secrets are configured.\n'
                '• Piper isolate inference and on-device playback have not been '
                'verified on a physical device in this environment.\n'
                '• The GGUF hub backend is not complete in this build.',
          ),
          const _Block(
            title: 'Licenses and upstream projects',
            body:
                'Flutter/Dart, Riverpod, just_audio, sqflite, flutter_secure_storage, '
                'share_plus, file_picker and archive retain their upstream licenses.\n\n'
                'sherpa-onnx is Apache-2.0. piper-phonemize and espeak-ng are '
                'GPL-3.0; review obligations before redistribution. Piper model '
                'cards carry their own dataset licenses.\n\n'
                'Gemini and VieNeu are external services with their own terms.',
          ),
          const _Block(
            title: 'Privacy',
            body:
                'API keys and tokens are stored in platform secure storage. They '
                'are never written to history, logs, screenshots or the README. '
                'Offline Piper generation does not upload text. Online engines send '
                'text only when you press Generate.',
          ),
          const SizedBox(height: 10),
          Text(
            'Repository: github.com/amkyawdev/amkyawdev-tts-app',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: AppColors.crimsonBright),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
