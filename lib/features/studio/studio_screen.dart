import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../../tts/models/engine_capabilities.dart';
import '../../tts/models/engine_id.dart';
import '../../tts/models/synthesis.dart';
import '../player/player_panel.dart';

class StudioScreen extends ConsumerStatefulWidget {
  const StudioScreen({super.key});

  @override
  ConsumerState<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends ConsumerState<StudioScreen> {
  final _textController = TextEditingController();
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final text = ref.read(studioProvider).text;
    _textController.text = text;
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(studioProvider);
    final controller = ref.read(studioProvider.notifier);
    final engineStatus = state.statuses[state.engineId];
    if (_textController.text != state.text) {
      _textController.value = TextEditingValue(
        text: state.text,
        selection: TextSelection.collapsed(offset: state.text.length),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            PageHeader(
              eyebrow: 'AmkyawDev',
              title: 'TTS Studio',
              subtitle: 'Hybrid speech synthesis · offline first',
              trailing: IconButton(
                tooltip: 'Refresh engine status',
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _EngineSelector(
                selected: state.engineId,
                statuses: state.statuses,
                onSelected: controller.selectEngine,
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'SCRIPT',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(letterSpacing: 2.4),
                          ),
                          const Spacer(),
                          Text(
                            '${state.text.length} / 5000',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _textController,
                        minLines: 5,
                        maxLines: 9,
                        maxLength: 5000,
                        onChanged: controller.setText,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          required maxLength,
                        }) => null,
                        decoration: const InputDecoration(
                          hintText:
                              'မင်္ဂလာပါ။ ဒီနေ့ ဘယ်လိုနေလဲ။\n'
                              'Type or paste your script…',
                          border: InputBorder.none,
                          filled: false,
                        ),
                      ),
                      const Divider(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 14,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _engineHint(state.engineId),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Voice',
                                isDense: true,
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value:
                                      state.voices.any(
                                        (voice) => voice.id == state.voiceId,
                                      )
                                      ? state.voiceId
                                      : null,
                                  hint: Text(
                                    state.loadingVoices
                                        ? 'Loading voices…'
                                        : 'No voices available',
                                  ),
                                  items: state.voices
                                      .map(
                                        (voice) => DropdownMenuItem(
                                          value: voice.id,
                                          child: Text(
                                            '${voice.name} · ${voice.languageCode}',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: state.loadingVoices
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            controller.selectVoice(value);
                                          }
                                        },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              '${state.speed.toStringAsFixed(1)}×',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('Speed'),
                          Expanded(
                            child: Slider(
                              value: state.speed,
                              min: 0.5,
                              max: 2,
                              divisions: 15,
                              onChanged: state.generating
                                  ? null
                                  : controller.setSpeed,
                            ),
                          ),
                        ],
                      ),
                      _EngineStatusLine(
                        status: engineStatus,
                        engineId: state.engineId,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (state.error != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ErrorBanner(message: state.error!),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: state.generating
                  ? OutlinedButton.icon(
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Cancel generation'),
                    )
                  : FilledButton.icon(
                      onPressed: state.text.trim().isEmpty
                          ? null
                          : controller.generate,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Generate Speech'),
                    ),
            ),
            if (state.generating) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: state.progress?.fraction,
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.progress?.label ?? 'Starting…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            if (state.result != null) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ResultCard(result: state.result!),
              ),
            ],
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Recent audio',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text(
                    'History tab',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const _RecentList(),
          ],
        ),
      ),
    );
  }

  String _engineHint(TtsEngineId id) {
    switch (id) {
      case TtsEngineId.piper:
        return 'Piper runs offline after a model download. The bundled catalogue is English (en_US-lessac) and does not synthesize Burmese.';
      case TtsEngineId.gemini:
        return 'Gemini uses your own API key and sends the script to Google. Burmese is listed as supported by Gemini 3.8 Flash TTS; quality is not verified by this app.';
      case TtsEngineId.vieneu:
        return 'VieNeu requires a separately deployed server. No VieNeu inference runs inside this app.';
      case TtsEngineId.system:
        return 'Uses the device speech engine. Some installed voices require a network connection.';
    }
  }
}

class _EngineSelector extends StatelessWidget {
  const _EngineSelector({
    required this.selected,
    required this.statuses,
    required this.onSelected,
  });

  final TtsEngineId selected;
  final Map<TtsEngineId, EngineStatus> statuses;
  final ValueChanged<TtsEngineId> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ENGINE',
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(letterSpacing: 2.4),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: TtsEngineId.values.map((id) {
            final ready = statuses[id]?.isReady ?? false;
            final isSelected = id == selected;
            return ChoiceChip(
              selected: isSelected,
              onSelected: (_) => onSelected(id),
              avatar: StatusDot(
                color: ready ? AppColors.success : AppColors.danger,
              ),
              label: Text(_label(id)),
              labelStyle: TextStyle(
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? AppColors.crimsonBright
                    : Theme.of(context).textTheme.bodyMedium?.color,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _label(TtsEngineId id) {
    switch (id) {
      case TtsEngineId.piper:
        return 'Piper';
      case TtsEngineId.gemini:
        return 'Gemini';
      case TtsEngineId.vieneu:
        return 'VieNeu';
      case TtsEngineId.system:
        return 'System';
    }
  }
}

class _EngineStatusLine extends StatelessWidget {
  const _EngineStatusLine({required this.status, required this.engineId});

  final EngineStatus? status;
  final TtsEngineId engineId;

  @override
  Widget build(BuildContext context) {
    final ready = status?.isReady ?? false;
    return Row(
      children: [
        StatusDot(color: ready ? AppColors.success : AppColors.danger),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            status?.message ?? 'Checking engine…',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Text(
          engineId == TtsEngineId.piper ? 'OFFLINE' : 'ONLINE',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: engineId == TtsEngineId.piper
                ? AppColors.success
                : AppColors.crimsonBright,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.result});

  final SynthesisResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final isCurrent = player.path == result.audioPath;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            IconButton.filledTonal(
              onPressed: () async {
                if (!isCurrent) {
                  await ref
                      .read(playerProvider.notifier)
                      .load(
                        result.audioPath,
                        title: 'Latest audio',
                        autoPlay: true,
                      );
                } else {
                  await ref.read(playerProvider.notifier).toggle();
                }
              },
              icon: Icon(
                isCurrent && player.playing
                    ? Icons.pause
                    : Icons.play_arrow_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latest audio',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${formatDuration(result.duration)} · ${result.format.extension.toUpperCase()} · ${result.engineId.name}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => showPlayerSheet(context),
              child: const Text('Open'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentList extends ConsumerWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(20),
        child: LinearProgressIndicator(),
      ),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(20),
        child: Text('History unavailable: $error'),
      ),
      data: (entries) {
        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              'Nothing generated yet. Your audio will appear here.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          );
        }
        return Column(
          children: entries.take(3).map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Card(
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.graphic_eq, size: 20),
                  title: Text(
                    entry.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${formatDateTime(entry.createdAt)} · ${formatDuration(Duration(milliseconds: entry.durationMs))}',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow),
                    onPressed: () async {
                      await ref
                          .read(playerProvider.notifier)
                          .load(
                            entry.audioPath,
                            title: entry.text,
                            autoPlay: true,
                          );
                      if (context.mounted) showPlayerSheet(context);
                    },
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
