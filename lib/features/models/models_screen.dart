import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../providers/app_providers.dart';

class ModelsScreen extends ConsumerWidget {
  const ModelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(modelsProvider);
    final deps = ref.read(depsProvider);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const PageHeader(
              eyebrow: 'On-device',
              title: 'Model Manager',
              subtitle: 'Piper ONNX models · downloaded externally',
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                color: AppColors.surfaceHigh,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'The catalogue is English (en_US-lessac) and does not '
                          'synthesize Burmese. Models are downloaded on demand and '
                          'never bundled in the APK.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            models.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: LinearProgressIndicator(),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text('Could not read models: $error'),
              ),
              data: (state) => Column(
                children: state.models.map((status) {
                  final manifest = status.manifest;
                  final isActive = state.activeId == manifest.id;
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        manifest.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${manifest.language} · ${manifest.quality} · '
                                        '${formatBytes(manifest.sizeBytes)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                StatusDot(
                                  color: status.installed
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ],
                            ),
                            if (status.installed)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  'Installed · ${formatBytes(status.bytesOnDisk)}',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.success),
                                ),
                              ),
                            if (isActive) ...[
                              const SizedBox(height: 10),
                              LinearProgressIndicator(
                                value: state.progress,
                                minHeight: 6,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                state.progress == null
                                    ? 'Downloading…'
                                    : '${(state.progress! * 100).toStringAsFixed(0)}%',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (!status.installed)
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: state.activeId == null
                                          ? () => ref
                                                .read(modelsProvider.notifier)
                                                .download(manifest.id)
                                          : null,
                                      icon: const Icon(Icons.download),
                                      label: const Text('Download'),
                                    ),
                                  )
                                else
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => ref
                                          .read(modelsProvider.notifier)
                                          .delete(manifest.id),
                                      icon: const Icon(Icons.delete_outline),
                                      label: const Text('Delete'),
                                    ),
                                  ),
                                if (isActive) ...[
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => ref
                                        .read(modelsProvider.notifier)
                                        .cancel(),
                                    icon: const Icon(
                                      Icons.stop_circle_outlined,
                                    ),
                                    tooltip: 'Cancel download',
                                  ),
                                ],
                              ],
                            ),
                            if (state.error != null && isActive)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  state.error!,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppColors.danger),
                                ),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              manifest.notes,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FutureBuilder<int>(
                future: deps.storage.modelBytes(),
                builder: (context, snapshot) => Text(
                  'Model storage: ${formatBytes(snapshot.data ?? 0)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
