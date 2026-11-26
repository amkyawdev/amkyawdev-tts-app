import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';

class HubScreen extends StatelessWidget {
  const HubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            const PageHeader(
              eyebrow: 'Models',
              title: 'GGUF Hub',
              subtitle: 'Hugging Face discovery · compatibility first',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                color: AppColors.surfaceHigh,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'GGUF is a model container, not a universal TTS runtime. '
                          'A file is only runnable when its architecture and audio '
                          'tokenizer/decoder/vocoder are supported by a verified '
                          'runtime. This app never returns fake audio for an '
                          'unsupported model.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const _InfoCard(
              title: 'Planned / experimental in this build',
              body:
                  'Hugging Face repository inspection, GGUF metadata display, '
                  'download/import progress, cancellation and local inventory are '
                  'designed but not wired into this APK yet. The Hub tab is '
                  'intentionally honest instead of pretending they work.',
              color: AppColors.warning,
            ),
            const _InfoCard(
              title: 'Verified external runtime',
              body:
                  'llama.cpp documents TTS support through libmtmd for specific '
                  'architectures such as Qwen3-TTS, Pocket TTS, Soprano, LFM3-Audio, '
                  'Chatterbox, Drama 3, ZONOS3, Fish Audio S2 Pro, Kokoro and '
                  'others. It requires the matching mmproj companion and runs on '
                  'desktop/server; this Flutter app has no verified on-device '
                  'binding for it.',
              color: AppColors.crimsonBright,
            ),
            const _InfoCard(
              title: 'Not runnable without their own runtimes',
              body:
                  'OuteTTS (DAC decoder), Orpheus (SNAC codec), NeuTTS (NeuCodec '
                  'ONNX), Spark-TTS (BiCodec) and MOSS-TTS are not supported by '
                  'llama.cpp alone. Importing those GGUF files would not make them '
                  'synthesize speech in this app.',
              color: AppColors.warning,
            ),
            const _InfoCard(
              title: 'Text LLMs are not TTS models',
              body:
                  'A Llama/Qwen/Gemma GGUF is a text-generation model. It has no '
                  'audio decoder and cannot produce speech by itself.',
              color: AppColors.warning,
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Source of truth: llama.cpp docs/multimodal/tts.md and each '
                'model card. No generic GGUF TTS support is claimed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.body,
    required this.color,
  });

  final String title;
  final String body;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(body, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
