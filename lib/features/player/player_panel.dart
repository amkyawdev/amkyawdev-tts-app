import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';

Future<void> showPlayerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const PlayerPanel(),
  );
}

class PlayerPanel extends ConsumerWidget {
  const PlayerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final controller = ref.read(playerProvider.notifier);
    final deps = ref.read(depsProvider);
    final maxMs = player.duration.inMilliseconds.toDouble();
    final value = player.position.inMilliseconds
        .clamp(0, player.duration.inMilliseconds)
        .toDouble();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              player.title.isEmpty ? 'Audio player' : player.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              '${player.format.extension.toUpperCase()} · ${formatDuration(player.duration)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 96,
              child: CustomPaint(
                painter: _WaveformPainter(
                  samples: player.waveform,
                  progress: maxMs == 0 ? 0 : value / maxMs,
                ),
                size: const Size(double.infinity, 96),
              ),
            ),
            if (player.waveform.isEmpty)
              Text(
                'Waveform is available for WAV files only.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Slider(
              value: value,
              max: maxMs <= 0 ? 1 : maxMs,
              onChanged: maxMs <= 0
                  ? null
                  : (next) =>
                        controller.seek(Duration(milliseconds: next.round())),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(player.position)),
                Text(formatDuration(player.duration)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => controller.seek(
                    player.position - const Duration(seconds: 10),
                  ),
                  icon: const Icon(Icons.replay_10),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 38,
                  onPressed: player.path == null ? null : controller.toggle,
                  icon: Icon(
                    player.playing ? Icons.pause : Icons.play_arrow_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => controller.seek(
                    player.position + const Duration(seconds: 10),
                  ),
                  icon: const Icon(Icons.forward_10),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.speed, size: 18),
                Expanded(
                  child: Slider(
                    value: player.speed,
                    min: 0.5,
                    max: 2,
                    divisions: 15,
                    label: '${player.speed.toStringAsFixed(1)}×',
                    onChanged: controller.setSpeed,
                  ),
                ),
                Text('${player.speed.toStringAsFixed(1)}×'),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: player.path == null
                        ? null
                        : () => deps.exportService.share(player.path!),
                    icon: const Icon(Icons.ios_share),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: player.path == null
                        ? null
                        : () async {
                            final saved = await deps.exportService.saveCopy(
                              player.path!,
                            );
                            if (context.mounted && saved) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Audio saved.')),
                              );
                            }
                          },
                    icon: const Icon(Icons.download),
                    label: const Text('Save copy'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'WAV export is implemented. MP3 is disabled because no MP3 encoder is bundled.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.samples, required this.progress});

  final List<double> samples;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final baseline = size.height / 2;
    final paint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = AppColors.crimsonBright
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (samples.isEmpty) {
      canvas.drawLine(Offset(0, baseline), Offset(size.width, baseline), paint);
      return;
    }
    final step = size.width / samples.length;
    for (var i = 0; i < samples.length; i++) {
      final amplitude = (samples[i].clamp(0.0, 1.0) * (size.height / 2 - 4));
      final x = i * step + step / 2;
      final color = i / samples.length <= progress ? active : paint;
      canvas.drawLine(
        Offset(x, baseline - amplitude),
        Offset(x, baseline + amplitude),
        color,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.samples != samples;
}
