import 'package:material_ui/material_ui.dart';

import '../../core/theme/app_theme.dart';
import '../../tts/models/tts_language.dart';
import '../../tts/voices/voice_catalog.dart';

/// Opens the searchable language picker and returns the chosen language code.
Future<String?> showLanguagePickerSheet(
  BuildContext context, {
  required List<LanguageOption> options,
  required String? selectedCode,
  List<String> recentCodes = const [],
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.92,
      child: LanguagePickerSheet(
        options: options,
        selectedCode: selectedCode,
        recentCodes: recentCodes,
      ),
    ),
  );
}

class LanguagePickerSheet extends StatefulWidget {
  const LanguagePickerSheet({
    super.key,
    required this.options,
    required this.selectedCode,
    this.recentCodes = const [],
  });

  final List<LanguageOption> options;
  final String? selectedCode;
  final List<String> recentCodes;

  @override
  State<LanguagePickerSheet> createState() => _LanguagePickerSheetState();
}

class _LanguagePickerSheetState extends State<LanguagePickerSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final value = _searchController.text;
    if (value == _query) return;
    setState(() => _query = value);
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocus.requestFocus();
  }

  List<LanguageOption> get _filtered {
    final query = _query.trim();
    if (query.isEmpty) return widget.options;
    return VoiceCatalog(widget.options.expand((o) => o.voices)).search(query);
  }

  List<LanguageOption> get _recent {
    if (_query.trim().isNotEmpty) return const [];
    final byCode = {
      for (final option in widget.options) option.language.code: option,
    };
    final seen = <String>{};
    final result = <LanguageOption>[];
    for (final code in widget.recentCodes) {
      final normalized = normalizeLanguageCode(code);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      final option = byCode[normalized];
      if (option != null) result.add(option);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;
    final recent = _recent;
    final recentCodes = recent.map((option) => option.language.code).toSet();
    final rest = recentCodes.isEmpty
        ? filtered
        : filtered
              .where((option) => !recentCodes.contains(option.language.code))
              .toList(growable: false);
    final selected = normalizeLanguageCode(widget.selectedCode);
    final hasQuery = _query.trim().isNotEmpty;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Choose language',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        '${widget.options.length} languages · '
                        '${widget.options.fold<int>(0, (sum, o) => sum + o.voiceCount)} voices',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Semantics(
              label: 'Search languages',
              textField: true,
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) {
                  if (filtered.length == 1) {
                    Navigator.of(context).pop(filtered.first.language.code);
                  }
                },
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Burmese, မြန်မာ, my-MM, 日本語…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: hasQuery
                      ? IconButton(
                          tooltip: 'Clear search',
                          onPressed: _clearSearch,
                          icon: const Icon(Icons.clear, size: 20),
                        )
                      : null,
                ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptySearchState(query: _query.trim(), onClear: _clearSearch)
                : ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.only(bottom: 16),
                    children: [
                      if (recent.isNotEmpty) ...[
                        const _SectionLabel('RECENTLY USED'),
                        for (final option in recent)
                          _LanguageTile(
                            option: option,
                            isSelected: option.language.code == selected,
                            onTap: () =>
                                Navigator.of(context).pop(option.language.code),
                          ),
                        const _SectionLabel('ALL LANGUAGES'),
                      ],
                      for (final option in rest)
                        _LanguageTile(
                          option: option,
                          isSelected: option.language.code == selected,
                          onTap: () =>
                              Navigator.of(context).pop(option.language.code),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final LanguageOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final language = option.language;
    final detail = <String>[
      if (language.hasNativeName) language.nativeName!,
      language.code.toUpperCase(),
      '${option.voiceCount} ${option.voiceCount == 1 ? 'voice' : 'voices'}',
    ].join(' · ');
    final hint = language.isMultilingual
        ? 'Follows the script you type'
        : language.isDeviceDefault
        ? 'The voice chosen by the system'
        : language.isUnknown
        ? 'This voice reports no locale'
        : null;

    return Semantics(
      selected: isSelected,
      button: true,
      label: '${language.label}, $detail${isSelected ? ', selected' : ''}',
      child: ListTile(
        onTap: onTap,
        selected: isSelected,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
        leading: Icon(
          isSelected
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked,
          color: isSelected ? AppColors.crimsonBright : AppColors.border,
        ),
        title: Text(
          language.englishName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(detail, style: theme.textTheme.bodySmall),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  hint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
        trailing: isSelected
            ? const Icon(Icons.check_circle, color: AppColors.success, size: 20)
            : null,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(letterSpacing: 2.2),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState({required this.query, required this.onClear});

  final String query;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.travel_explore, size: 36),
            const SizedBox(height: 12),
            Text(
              query.isEmpty
                  ? 'This engine reported no voices'
                  : 'No languages match “$query”',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'Search by language name, native name, locale code or an alias '
              'such as Burmese, မြန်မာ or my-MM.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            if (query.isNotEmpty)
              OutlinedButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.clear),
                label: const Text('Clear search'),
              ),
          ],
        ),
      ),
    );
  }
}
