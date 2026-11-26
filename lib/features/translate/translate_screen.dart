import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../app.dart';
import '../../core/theme/app_theme.dart';
import '../../gguf/gguf_catalog.dart';
import '../../providers/app_providers.dart';
import '../../providers/translation_providers.dart';
import '../../translate/subtitle_document.dart';
import '../../translate/translation_engine.dart';
import '../../tts/models/tts_language.dart';
import '../models/translation_models_screen.dart';

/// Offline subtitle/text translation.
///
/// Local GGUF translation only: no online translation backend is configured,
/// so uploaded content never leaves the device.
class TranslateScreen extends ConsumerStatefulWidget {
  const TranslateScreen({super.key});

  @override
  ConsumerState<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends ConsumerState<TranslateScreen> {
  final _pasteController = TextEditingController();
  final _outputController = TextEditingController();
  bool _showPaste = false;

  @override
  void dispose() {
    _pasteController.dispose();
    _outputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(translationProvider);
    final controller = ref.read(translationProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final downloads = ref.watch(ggufDownloadsProvider);
    final model = ggufTranslationModelById(settings.translationModelId);
    final modelState = model == null ? null : downloads[model.id];
    if (state.outputText != null &&
        _outputController.text != state.outputText &&
        !state.isRunning) {
      _outputController.value = TextEditingValue(
        text: state.outputText!,
        selection: TextSelection.collapsed(offset: state.outputText!.length),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            PageHeader(
              eyebrow: 'Offline',
              title: 'Translate',
              subtitle: 'Subtitles and text → မြန်မာ · local model',
              trailing: IconButton(
                tooltip: 'Translation models',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TranslationModelsScreen(),
                  ),
                ),
                icon: const Icon(Icons.memory),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ModelStatusCard(model: model, state: modelState),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _LanguageRow(
                        sourceLanguage: state.sourceLanguage,
                        targetLanguage: state.targetLanguage,
                        enabled: !state.isRunning,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: state.isRunning ? null : _pickFile,
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Choose file'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: state.isRunning
                                  ? null
                                  : () => setState(
                                      () => _showPaste = !_showPaste,
                                    ),
                              icon: const Icon(Icons.edit_note),
                              label: const Text('Paste text'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'SRT, VTT or TXT · UTF-8, UTF-16 or Latin-1 · '
                        'max 4 MB',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_showPaste) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pasteController,
                          minLines: 3,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            hintText: 'Paste text to translate…',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: state.isRunning
                                ? null
                                : () {
                                    final text = _pasteController.text.trim();
                                    if (text.isEmpty) return;
                                    controller.loadText(text: text);
                                  },
                            child: const Text('Use this text'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (state.notice != null) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Banner(
                  message: state.notice!,
                  color: AppColors.warning,
                ),
              ),
            ],
            if (state.document != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PreviewCard(state: state),
              ),
            ],
            if (state.error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _Banner(message: state.error!, color: AppColors.danger),
              ),
            ],
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: state.isRunning
                  ? OutlinedButton.icon(
                      onPressed: controller.cancel,
                      icon: const Icon(Icons.stop_circle_outlined),
                      label: const Text('Cancel translation'),
                    )
                  : FilledButton.icon(
                      onPressed: state.document == null
                          ? null
                          : controller.translate,
                      icon: const Icon(Icons.translate),
                      label: const Text('Translate'),
                    ),
            ),
            if (state.isRunning) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _TranslatingCard(
                  progress: state.progress,
                  modelName: model?.name ?? 'Local model',
                  fileName: state.fileName ?? 'Pasted text',
                ),
              ),
            ],
            if (state.hasOutput && !state.isRunning) ...[
              const SizedBox(height: 16),
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
                              'Translated result',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Text(
                              'Editable',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _outputController,
                          minLines: 6,
                          maxLines: 16,
                          onChanged: controller.editOutput,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: 'Translation preview…',
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _export(
                                  context,
                                  _outputController.text,
                                  state,
                                ),
                                icon: const Icon(Icons.ios_share),
                                label: const Text('Share / save'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'Discard translation',
                              onPressed: controller.clearInput,
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Privacy: translation runs on this device with the selected '
                'GGUF model. No text, subtitle or translation is uploaded. '
                'Speech generation stays in the Studio tab and never uses GGUF.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choose a subtitle or text file',
      type: FileType.custom,
      allowedExtensions: ['srt', 'vtt', 'txt'],
    );
    final file = result.firstOrNull;
    if (file == null) return;
    final length = await file.length();
    if (length != null && length > 4 * 1024 * 1024) {
      _showError('That file is larger than 4 MB. Split it first.');
      return;
    }
    Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } catch (error) {
      _showError('The file could not be read: $error');
      return;
    }
    ref
        .read(translationProvider.notifier)
        .loadBytes(bytes: bytes, fileName: file.name);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export(
    BuildContext context,
    String content,
    TranslationState state,
  ) async {
    final base = state.fileName == null
        ? 'translation'
        : p.basenameWithoutExtension(state.fileName!);
    final extension = switch (state.format) {
      SubtitleFormat.srt => 'srt',
      SubtitleFormat.vtt => 'vtt',
      SubtitleFormat.plainText => 'txt',
    };
    final name = '${base.isEmpty ? 'translation' : base}.my.$extension';
    final deps = ref.read(depsProvider);
    final support = await deps.storage.supportDir();
    final dir = Directory(p.join(support.path, 'translations'));
    await dir.create(recursive: true);
    final file = File(
      p.join(dir.path, name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')),
    );
    await file.writeAsString(content, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: 'မြန်မာ translation'),
    );
  }
}

class _ModelStatusCard extends StatelessWidget {
  const _ModelStatusCard({required this.model, required this.state});

  final GgufTranslationModel? model;
  final dynamic state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = state?.isComplete == true;
    final active = state?.isActive == true;
    return Card(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(
              installed ? Icons.verified : Icons.memory,
              color: installed ? AppColors.success : AppColors.warning,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    model?.name ?? 'No translation model selected',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    installed
                        ? 'Installed · offline translation ready'
                        : active
                        ? 'Downloading · open Translation models to follow progress'
                        : 'Not installed · download it to translate offline',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.state});

  final TranslationState state;

  @override
  Widget build(BuildContext context) {
    final document = state.document!;
    final theme = Theme.of(context);
    final isSubtitle = document.format != SubtitleFormat.plainText;
    final preview = isSubtitle
        ? document.cues
              .take(3)
              .map(
                (cue) => '${cue.identifier ?? ''}  ${cue.timing}\n${cue.text}',
              )
              .join('\n\n')
        : document.toPlainText();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.fileName ?? 'Pasted text',
                    style: theme.textTheme.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${state.format.name.toUpperCase()} · ${state.encoding}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isSubtitle
                  ? '${document.cueCount} cues · '
                        '${document.translatableCueCount} to translate'
                  : '${preview.length} characters',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                preview.isEmpty
                    ? 'Nothing to translate.'
                    : preview.length > 600
                    ? '${preview.substring(0, 600)}…'
                    : preview,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.color});

  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.enabled,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(translationProvider.notifier);
    return Row(
      children: [
        Expanded(
          child: _LanguageButton(
            label: 'FROM',
            language: sourceLanguage == 'auto'
                ? const TtsLanguage(
                    code: 'auto',
                    englishName: 'Detect automatically',
                    aliases: ['auto', 'detect'],
                  )
                : resolveTtsLanguage(sourceLanguage),
            onTap: !enabled
                ? null
                : () async {
                    final code = await _pickLanguage(
                      context,
                      includeAuto: true,
                      selected: sourceLanguage,
                    );
                    if (code != null) controller.setSource(code);
                  },
          ),
        ),
        IconButton(
          tooltip: 'Swap languages',
          onPressed: enabled && sourceLanguage != 'auto'
              ? controller.swapLanguages
              : null,
          icon: const Icon(Icons.swap_horiz),
        ),
        Expanded(
          child: _LanguageButton(
            label: 'TO',
            language: resolveTtsLanguage(targetLanguage),
            onTap: !enabled
                ? null
                : () async {
                    final code = await _pickLanguage(
                      context,
                      includeAuto: false,
                      selected: targetLanguage,
                    );
                    if (code != null) controller.setTarget(code);
                  },
          ),
        ),
      ],
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.label,
    required this.language,
    required this.onTap,
  });

  final String label;
  final TtsLanguage language;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: onTap != null,
      label: '$label ${language.label}. Tap to change.',
      excludeSemantics: true,
      child: Material(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  language.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const List<TtsLanguage> _translationLanguages = [
  TtsLanguage(
    code: 'my',
    englishName: 'Burmese',
    nativeName: 'မြန်မာ',
    aliases: ['myanmar', 'burmese'],
  ),
  TtsLanguage(code: 'en', englishName: 'English', nativeName: 'English'),
  TtsLanguage(code: 'zh', englishName: 'Chinese', nativeName: '中文'),
  TtsLanguage(code: 'ja', englishName: 'Japanese', nativeName: '日本語'),
  TtsLanguage(code: 'ko', englishName: 'Korean', nativeName: '한국어'),
  TtsLanguage(code: 'th', englishName: 'Thai', nativeName: 'ไทย'),
  TtsLanguage(code: 'vi', englishName: 'Vietnamese', nativeName: 'Tiếng Việt'),
  TtsLanguage(code: 'hi', englishName: 'Hindi', nativeName: 'हिन्दी'),
  TtsLanguage(code: 'bn', englishName: 'Bengali', nativeName: 'বাংলা'),
  TtsLanguage(code: 'ne', englishName: 'Nepali', nativeName: 'नेपाली'),
  TtsLanguage(code: 'si', englishName: 'Sinhala', nativeName: 'සිංහල'),
  TtsLanguage(code: 'km', englishName: 'Khmer', nativeName: 'ខ្មែរ'),
  TtsLanguage(code: 'lo', englishName: 'Lao', nativeName: 'ລາວ'),
  TtsLanguage(code: 'ms', englishName: 'Malay', nativeName: 'Bahasa Melayu'),
  TtsLanguage(
    code: 'id',
    englishName: 'Indonesian',
    nativeName: 'Bahasa Indonesia',
  ),
  TtsLanguage(code: 'fr', englishName: 'French', nativeName: 'Français'),
  TtsLanguage(code: 'de', englishName: 'German', nativeName: 'Deutsch'),
  TtsLanguage(code: 'es', englishName: 'Spanish', nativeName: 'Español'),
  TtsLanguage(code: 'pt', englishName: 'Portuguese', nativeName: 'Português'),
  TtsLanguage(code: 'ru', englishName: 'Russian', nativeName: 'Русский'),
  TtsLanguage(code: 'ar', englishName: 'Arabic', nativeName: 'العربية'),
  TtsLanguage(code: 'tr', englishName: 'Turkish', nativeName: 'Türkçe'),
  TtsLanguage(code: 'ta', englishName: 'Tamil', nativeName: 'தமிழ்'),
  TtsLanguage(code: 'ur', englishName: 'Urdu', nativeName: 'اردو'),
];

Future<String?> _pickLanguage(
  BuildContext context, {
  required bool includeAuto,
  required String selected,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        _TranslationLanguageSheet(includeAuto: includeAuto, selected: selected),
  );
}

class _TranslationLanguageSheet extends StatefulWidget {
  const _TranslationLanguageSheet({
    required this.includeAuto,
    required this.selected,
  });

  final bool includeAuto;
  final String selected;

  @override
  State<_TranslationLanguageSheet> createState() =>
      _TranslationLanguageSheetState();
}

class _TranslationLanguageSheetState extends State<_TranslationLanguageSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final entries = <TtsLanguage>[
      if (widget.includeAuto)
        const TtsLanguage(
          code: 'auto',
          englishName: 'Detect automatically',
          aliases: ['auto', 'detect', 'unknown'],
        ),
      ..._translationLanguages,
    ];
    final query = _query.toLowerCase().trim();
    final filtered = query.isEmpty
        ? entries
        : entries
              .where(
                (language) =>
                    language.searchableText.contains(query) ||
                    language.label.toLowerCase().contains(query),
              )
              .toList(growable: false);
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'မြန်မာ, Burmese, en, 日本語…',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No language matches “$_query”.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final language = filtered[index];
                      return ListTile(
                        title: Text(language.label),
                        subtitle: Text(language.code.toUpperCase()),
                        trailing: language.code == widget.selected
                            ? const Icon(Icons.check_circle)
                            : null,
                        onTap: () => Navigator.of(context).pop(language.code),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Real progress + an honest indeterminate animation when a chunk total is
/// unknown. Respects the platform "remove animations" accessibility setting.
class _TranslatingCard extends StatefulWidget {
  const _TranslatingCard({
    required this.progress,
    required this.modelName,
    required this.fileName,
  });

  final TranslationProgress? progress;
  final String modelName;
  final String fileName;

  @override
  State<_TranslatingCard> createState() => _TranslatingCardState();
}

class _TranslatingCardState extends State<_TranslatingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.progress;
    final fraction = progress?.fraction;
    final stage = switch (progress?.stage ?? TranslationStage.preparing) {
      TranslationStage.loadingModel => 'Loading model',
      TranslationStage.preparing => 'Preparing text',
      TranslationStage.translating => 'Translating',
      TranslationStage.saving => 'Saving',
      TranslationStage.completed => 'Complete',
      TranslationStage.failed => 'Failed',
      TranslationStage.cancelled => 'Cancelled',
      TranslationStage.idle => 'Waiting',
    };
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 26,
                  height: 26,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      final t = reduceMotion ? 0.6 : _controller.value;
                      return CustomPaint(
                        painter: _TranslatingGlyphPainter(
                          progress: t,
                          color: AppColors.crimsonBright,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ဘာသာပြန်နေသည်… · Translating…',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              borderRadius: BorderRadius.circular(999),
            ),
            const SizedBox(height: 8),
            Text(
              [
                stage,
                if (fraction != null) '${(fraction * 100).toStringAsFixed(0)}%',
                if (progress != null && progress.totalChunks > 0)
                  '${progress.completedChunks}/${progress.totalChunks} chunks',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.fileName} · ${widget.modelName}',
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (progress?.message != null) ...[
              const SizedBox(height: 4),
              Text(progress!.message, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _TranslatingGlyphPainter extends CustomPainter {
  const _TranslatingGlyphPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - 2;
    for (var i = 0; i < 3; i++) {
      final phase = (progress + i / 3) % 1;
      paint.color = color.withValues(alpha: 1 - phase);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * (0.45 + phase * 0.55)),
        -1.2,
        2.4,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_TranslatingGlyphPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
