import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../gguf/gguf_catalog.dart';
import '../../gguf/gguf_download_manager.dart';
import '../../providers/app_providers.dart';
import '../../providers/translation_providers.dart';

/// Local translation model manager.
///
/// GGUF is used here only for text translation. No entry can be selected as a
/// speech engine, and no model is labelled "ready" before its file is verified.
class TranslationModelsScreen extends ConsumerStatefulWidget {
  const TranslationModelsScreen({super.key});

  @override
  ConsumerState<TranslationModelsScreen> createState() =>
      _TranslationModelsScreenState();
}

enum _ModelFilter { all, installed, downloadable }

class _TranslationModelsScreenState
    extends ConsumerState<TranslationModelsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  _ModelFilter _filter = _ModelFilter.all;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (_searchController.text != _query) {
        setState(() => _query = _searchController.text);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final downloads = ref.watch(ggufDownloadsProvider);
    final settings = ref.watch(settingsProvider);
    final models = searchGgufTranslationModels(_query)
        .where((model) {
          final state = downloads[model.id];
          return switch (_filter) {
            _ModelFilter.all => true,
            _ModelFilter.installed => state?.isComplete ?? false,
            _ModelFilter.downloadable => !(state?.isComplete ?? false),
          };
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Translation models'),
        actions: [
          IconButton(
            tooltip: 'Refresh download state',
            onPressed: () => ref.read(ggufDownloadsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Card(
                color: AppColors.surfaceHigh,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.translate, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'GGUF models here run text translation only, fully '
                          'offline after download. English speech is never '
                          'generated from GGUF: use the Studio tab with Piper, '
                          'Gemini or VieNeu for speech.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search model, publisher, architecture, language',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: _searchController.clear,
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final filter in _ModelFilter.values)
                    ChoiceChip(
                      label: Text(switch (filter) {
                        _ModelFilter.all => 'All',
                        _ModelFilter.installed => 'Installed',
                        _ModelFilter.downloadable => 'Not installed',
                      }),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
            ),
            if (models.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No model matches “$_query”. Models are only listed when '
                  'their size, SHA-256 and architecture were verified against '
                  'the upstream repository.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            for (final model in models)
              _ModelCard(
                model: model,
                download:
                    downloads[model.id] ?? GgufDownloadState(modelId: model.id),
                isSelected: settings.translationModelId == model.id,
              ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Storage: app-specific folder '
                '(Android/data/<package>/files/gguf/models). Files are removed '
                'when you uninstall the app or delete the model here.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelCard extends ConsumerWidget {
  const _ModelCard({
    required this.model,
    required this.download,
    required this.isSelected,
  });

  final GgufTranslationModel model;
  final GgufDownloadState download;
  final bool isSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final assessment = assessTranslationModel(
      model: model,
      runtimeAvailable: true,
      runtimeArchitectures: translationRuntimeArchitectures,
      installed: download.isComplete,
    );
    final controller = ref.read(ggufDownloadsProvider.notifier);
    final statusColor = switch (assessment.readiness) {
      TranslationReadiness.ready => AppColors.success,
      TranslationReadiness.downloadOnly => AppColors.warning,
      TranslationReadiness.unsupported => AppColors.danger,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.name, style: theme.textTheme.titleMedium),
                        Text(
                          '${model.publisher} · ${model.repoId}',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(
                        Icons.check_circle,
                        color: AppColors.crimsonBright,
                        size: 18,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Badge(label: assessment.label, color: statusColor),
                  _Badge(label: model.quantization, color: AppColors.border),
                  _Badge(
                    label: '${model.architecture} · ctx ${model.contextLength}',
                    color: AppColors.border,
                  ),
                  _Badge(
                    label: formatBytes(model.totalBytes),
                    color: AppColors.border,
                  ),
                  _Badge(label: model.license, color: AppColors.border),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Languages: ${model.languages.join(', ')} · RAM ≈ '
                '${model.minRamMb} MB',
                style: theme.textTheme.bodySmall,
              ),
              if (download.isActive ||
                  download.status == GgufDownloadStatus.paused) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: download.fraction,
                  minHeight: 5,
                  borderRadius: BorderRadius.circular(999),
                ),
                const SizedBox(height: 6),
                Text(
                  download.status == GgufDownloadStatus.paused
                      ? 'Paused · ${formatBytes(download.receivedBytes)} of '
                            '${formatBytes(download.totalBytes)}'
                      : '${((download.fraction ?? 0) * 100).toStringAsFixed(0)}% · '
                            '${formatBytes(download.receivedBytes)} of '
                            '${formatBytes(download.totalBytes)} · file '
                            '${download.fileIndex}/${download.fileCount}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (download.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  download.error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!download.isComplete && !download.isActive)
                    FilledButton.icon(
                      onPressed: () => controller.start(model),
                      icon: const Icon(Icons.download),
                      label: Text(
                        download.status == GgufDownloadStatus.paused
                            ? 'Resume'
                            : 'Download',
                      ),
                    ),
                  if (download.isActive)
                    OutlinedButton.icon(
                      onPressed: controller.pause,
                      icon: const Icon(Icons.pause),
                      label: const Text('Pause'),
                    ),
                  if (download.isComplete) ...[
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        await ref
                            .read(settingsProvider.notifier)
                            .update(
                              ref
                                  .read(settingsProvider)
                                  .copyWith(translationModelId: model.id),
                            );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${model.name} selected for translation',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Use for translation'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final problem = await controller.manager?.verify(model);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              problem ??
                                  '${model.name}: header, size and SHA-256 '
                                      'verified.',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.verified_outlined),
                      label: const Text('Verify'),
                    ),
                    TextButton.icon(
                      onPressed: () => _confirmDelete(context, ref),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ],
                  if (download.status == GgufDownloadStatus.failed ||
                      download.status == GgufDownloadStatus.paused)
                    TextButton.icon(
                      onPressed: () => controller.cancel(model),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text('Clear download'),
                    ),
                  TextButton(
                    onPressed: () => _showDetails(context, model, assessment),
                    child: const Text('Details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${model.name}?'),
        content: Text(
          'This removes ${formatBytes(model.totalBytes)} from app storage. '
          'You can download it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(ggufDownloadsProvider.notifier).delete(model);
    }
  }

  void _showDetails(
    BuildContext context,
    GgufTranslationModel model,
    TranslationAssessment assessment,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                const BrandMark(size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    model.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(model.description),
            const SizedBox(height: 14),
            _DetailRow('Repository', model.repoId),
            _DetailRow('Architecture', model.architecture),
            _DetailRow('Quantization', model.quantization),
            _DetailRow('Context window', '${model.contextLength} tokens'),
            _DetailRow('Languages', model.languages.join(', ')),
            _DetailRow('License', model.license),
            _DetailRow('Approx. RAM', '${model.minRamMb} MB'),
            _DetailRow('Download size', formatBytes(model.totalBytes)),
            _DetailRow('Verified', model.verifiedAt),
            const SizedBox(height: 14),
            Text('Status', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(assessment.reason),
            if (assessment.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final warning in assessment.warnings) Text('• $warning'),
            ],
            const SizedBox(height: 14),
            Text('Files', style: Theme.of(context).textTheme.titleMedium),
            for (final file in model.files) ...[
              const SizedBox(height: 6),
              Text(
                '${file.name} · ${formatBytes(file.sizeBytes)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              SelectableText(
                file.sha256 ?? 'No SHA-256 published',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'Source and license: ${model.pageUrl()}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
