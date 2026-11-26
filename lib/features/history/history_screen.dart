import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';
import '../player/player_panel.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            PageHeader(
              eyebrow: 'Library',
              title: 'History',
              subtitle: 'Every generated file, stored locally',
              trailing: IconButton(
                tooltip: 'Delete all history',
                onPressed: () => _clear(context, ref),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ),
            Expanded(
              child: history.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('History unavailable: $error'),
                  ),
                ),
                data: (entries) {
                  if (entries.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'No audio yet.\nGenerate speech in the Studio tab.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          title: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              '${entry.engineId.name} · ${entry.voiceId} · '
                              '${formatDuration(Duration(milliseconds: entry.durationMs))}\n'
                              '${formatDateTime(entry.createdAt)} · ${entry.format.extension.toUpperCase()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Play',
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
                              IconButton(
                                tooltip: 'Delete',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await ref
                                      .read(historyProvider.notifier)
                                      .delete(entry);
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all history?'),
        content: const Text(
          'This removes every history entry and its audio file from app storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(historyProvider.notifier).clear();
    }
  }
}
