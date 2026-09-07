import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/datamuse_service.dart';
import '../../services/dictionary_service.dart';
import '../../services/tts_service.dart';
import '../../services/wiktionary_service.dart';

/// Экран полного словаря: бесплатный безлимитный поиск через Datamuse
/// + детальные определения из Wiktionary, перевод и добавление в SRS-словарь.
class FullDictionaryScreen extends StatefulWidget {
  const FullDictionaryScreen({super.key});

  @override
  State<FullDictionaryScreen> createState() => _FullDictionaryScreenState();
}

class _FullDictionaryScreenState extends State<FullDictionaryScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;

  DatamuseMode _mode = DatamuseMode.startsWith;
  List<DatamuseWord> _results = [];
  bool _loading = false;
  bool _isFirstLoad = true;

  @override
  void initState() {
    super.initState();
    // По умолчанию покажем популярные слова
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runSearch('the');
    });
  }

  void _onChanged(String s) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(s));
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    final r = await DatamuseService.search(query: query, mode: _mode, max: 60);
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
      _isFirstLoad = false;
    });
  }

  void _setMode(DatamuseMode m) {
    setState(() => _mode = m);
    _runSearch(_searchCtrl.text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // ─── Header & search ───
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text('Словарь', style: tt.headlineSmall),
                  ),
                  IconButton(
                    tooltip: 'Очистить',
                    onPressed: _searchCtrl.text.isEmpty
                        ? null
                        : () {
                            _searchCtrl.clear();
                            _runSearch('');
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                focusNode: _focus,
                autofocus: false,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _hintForMode(_mode),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                ),
                onChanged: _onChanged,
                onSubmitted: _runSearch,
              ),
            ),

            // ─── Mode chips ───
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  for (final m in DatamuseMode.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(_labelForMode(m)),
                        selected: _mode == m,
                        onSelected: (_) => _setMode(m),
                      ),
                    ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ─── Results ───
            Expanded(
              child: _buildResults(cs, tt),
            ),
          ],
        ),
      ),
    );
  }

  String _hintForMode(DatamuseMode m) {
    switch (m) {
      case DatamuseMode.startsWith:
        return 'Слова, начинающиеся с…';
      case DatamuseMode.meansLike:
        return 'Слова со схожим значением…';
      case DatamuseMode.synonyms:
        return 'Синонимы к…';
      case DatamuseMode.antonyms:
        return 'Антонимы к…';
      case DatamuseMode.rhymes:
        return 'Рифмы к…';
      case DatamuseMode.soundsLike:
        return 'Звучит похоже на…';
      case DatamuseMode.triggers:
        return 'Связанные с…';
    }
  }

  String _labelForMode(DatamuseMode m) {
    switch (m) {
      case DatamuseMode.startsWith:
        return 'Начинается с';
      case DatamuseMode.meansLike:
        return 'По смыслу';
      case DatamuseMode.synonyms:
        return 'Синонимы';
      case DatamuseMode.antonyms:
        return 'Антонимы';
      case DatamuseMode.rhymes:
        return 'Рифмы';
      case DatamuseMode.soundsLike:
        return 'Похоже звучит';
      case DatamuseMode.triggers:
        return 'Ассоциации';
    }
  }

  Widget _buildResults(ColorScheme cs, TextTheme tt) {
    if (_isFirstLoad && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_results.isEmpty && !_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded, size: 64, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(_searchCtrl.text.isEmpty
                ? 'Начните вводить слово для поиска'
                : 'Ничего не найдено'),
            const SizedBox(height: 4),
            Text(
              'Datamuse · Wiktionary — бесплатно, без ключа',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _results.length,
      itemBuilder: (ctx, i) {
        final w = _results[i];
        return _WordTile(
          word: w,
          onTap: () => _openDetails(w),
          onSpeak: () => TtsService.speak(w.word),
        ).animate(delay: (i * 16).ms).fadeIn().slideX(begin: 0.02);
      },
    );
  }

  void _openDetails(DatamuseWord word) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _WordDetailsSheet(word: word),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _focus.dispose();
    TtsService.stop();
    super.dispose();
  }
}

// ─────────────────────────── ROW TILE ───────────────────────────
class _WordTile extends StatelessWidget {
  final DatamuseWord word;
  final VoidCallback onTap;
  final VoidCallback onSpeak;

  const _WordTile({
    required this.word,
    required this.onTap,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final firstDef = word.definitions.isNotEmpty
        ? word.definitions.first
        : null;
    final pos = word.partsOfSpeech.isNotEmpty
        ? word.partsOfSpeech.join(' · ')
        : (firstDef?.pos ?? '');
    final freq = word.frequency;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Flexible(
                        child: Text(
                          word.word,
                          style: tt.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (pos.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(pos,
                            style: tt.labelSmall?.copyWith(
                                color: cs.primary,
                                fontStyle: FontStyle.italic,
                                letterSpacing: 0.3)),
                      ],
                    ],
                  ),
                  if (firstDef != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      firstDef.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                  if (freq != null) ...[
                    const SizedBox(height: 6),
                    _FrequencyBar(freq: freq),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_rounded, size: 20),
              tooltip: 'Произношение',
            ),
          ],
        ),
      ),
    );
  }
}

class _FrequencyBar extends StatelessWidget {
  final double freq; // per million
  const _FrequencyBar({required this.freq});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Лог-нормализация: 0.01 → 0.0, ~1000 → 1.0
    final v = (freq <= 0)
        ? 0.0
        : ((freq.clamp(0.01, 1000.0)).toDouble())
            .toDouble()
            .let((x) => (x.bitLogish() / 5.0).clamp(0.05, 1.0));
    return Row(
      children: [
        Icon(Icons.bar_chart_rounded,
            size: 14, color: cs.onSurfaceVariant.withOpacity(0.7)),
        const SizedBox(width: 4),
        SizedBox(
          width: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: v,
              minHeight: 4,
              color: cs.tertiary,
              backgroundColor: cs.tertiary.withOpacity(0.15),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(_formatFreq(freq),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }

  String _formatFreq(double f) {
    if (f >= 100) return '${f.toStringAsFixed(0)}/M';
    if (f >= 1) return '${f.toStringAsFixed(1)}/M';
    return '${(f * 1000).toStringAsFixed(0)}/B';
  }
}

extension _NumX on double {
  double bitLogish() {
    // crude log10-like for [0.01..1000]
    if (this <= 0) return 0;
    double v = this;
    int e = 0;
    while (v >= 10) {
      v /= 10;
      e++;
    }
    while (v < 1 && e > -3) {
      v *= 10;
      e--;
    }
    return e + (v - 1) / 9.0; // ~ log10
  }
}

extension _LetExt<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

// ────────────────────────── DETAILS SHEET ──────────────────────────
class _WordDetailsSheet extends StatefulWidget {
  final DatamuseWord word;
  const _WordDetailsSheet({required this.word});

  @override
  State<_WordDetailsSheet> createState() => _WordDetailsSheetState();
}

class _WordDetailsSheetState extends State<_WordDetailsSheet> {
  bool _loadingExtra = true;
  List<WiktionaryDefinition> _wikDefs = [];
  String? _phonetic;
  String? _translation;
  List<DatamuseWord> _synonyms = const [];
  List<DatamuseWord> _antonyms = const [];

  @override
  void initState() {
    super.initState();
    _loadExtra();
  }

  Future<void> _loadExtra() async {
    final w = widget.word.word;
    final results = await Future.wait<dynamic>([
      WiktionaryService.lookup(w),
      DictionaryService.lookupWord(w),
      DatamuseService.search(query: w, mode: DatamuseMode.synonyms, max: 12),
      DatamuseService.search(query: w, mode: DatamuseMode.antonyms, max: 8),
    ]);
    if (!mounted) return;
    setState(() {
      _wikDefs = results[0] as List<WiktionaryDefinition>;
      final dr = results[1] as DictionaryResult;
      _phonetic = dr.phonetic;
      _translation = dr.translation;
      _synonyms = results[2] as List<DatamuseWord>;
      _antonyms = results[3] as List<DatamuseWord>;
      _loadingExtra = false;
    });
  }

  Future<void> _addToVocab() async {
    final vocab = context.read<VocabularyProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await vocab.addWord(
        word: widget.word.word,
        translation: _translation,
        phonetic: _phonetic,
      );
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(content: Text('"${widget.word.word}" добавлено в словарь')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final w = widget.word;

    final allDefs = <DatamuseDef>[];
    // Datamuse определения первыми
    allDefs.addAll(w.definitions);
    // Затем уникальные из Wiktionary
    for (final wd in _wikDefs) {
      if (!allDefs.any((d) => d.text == wd.definition)) {
        allDefs.add(DatamuseDef(pos: wd.partOfSpeech, text: wd.definition));
      }
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(w.word,
                          style: tt.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      if (_phonetic != null && _phonetic!.isNotEmpty)
                        Text(_phonetic!,
                            style: tt.bodyLarge?.copyWith(
                                color: cs.primary.withOpacity(0.8),
                                fontStyle: FontStyle.italic))
                      else if (w.arpabet != null)
                        Text('/${w.arpabet}/',
                            style: tt.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontStyle: FontStyle.italic)),
                      const SizedBox(height: 4),
                      if (w.partsOfSpeech.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: w.partsOfSpeech
                              .map((p) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: cs.primaryContainer,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(p,
                                        style: tt.labelSmall?.copyWith(
                                            color: cs.onPrimaryContainer)),
                                  ))
                              .toList(),
                        ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: () => TtsService.speak(w.word),
                  icon: const Icon(Icons.volume_up_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Translation block
            if (_translation != null && _translation!.isNotEmpty) ...[
              _SectionTitle('Перевод'),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(_translation!,
                    style: tt.bodyLarge?.copyWith(
                        color: cs.onSecondaryContainer,
                        fontWeight: FontWeight.w500)),
              ),
              const SizedBox(height: 16),
            ],

            // Definitions
            _SectionTitle('Определения'),
            if (_loadingExtra && allDefs.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (allDefs.isEmpty)
              Text('Определения не найдены',
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant))
            else
              ...allDefs.take(8).map((d) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6, right: 8),
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: cs.primary, shape: BoxShape.circle),
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: tt.bodyMedium?.copyWith(
                                  color: cs.onSurface, height: 1.4),
                              children: [
                                if (d.pos.isNotEmpty)
                                  TextSpan(
                                    text: '${d.pos}  ',
                                    style: tt.labelSmall?.copyWith(
                                        color: cs.primary,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w700),
                                  ),
                                TextSpan(text: d.text),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )),

            // Examples (Wiktionary)
            if (_wikDefs.any((d) => d.examples.isNotEmpty)) ...[
              const SizedBox(height: 12),
              _SectionTitle('Примеры'),
              ..._wikDefs
                  .expand((d) => d.examples)
                  .take(4)
                  .map((ex) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('"$ex"',
                              style: tt.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: cs.onSurfaceVariant)),
                        ),
                      )),
            ],

            // Synonyms
            if (_synonyms.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionTitle('Синонимы'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _synonyms
                    .map((s) => _RelatedChip(
                          text: s.word,
                          onTap: () {
                            Navigator.pop(context);
                            // Откроем новый экран сразу же — пушнем в стек
                            // (так получается история навигации)
                            // Для простоты: показываем ещё одну детальную карточку
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (_) =>
                                  _WordDetailsSheet(word: s),
                            );
                          },
                        ))
                    .toList(),
              ),
            ],

            // Antonyms
            if (_antonyms.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SectionTitle('Антонимы'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _antonyms
                    .map((s) => _RelatedChip(
                          text: s.word,
                          color: cs.errorContainer,
                          onTap: () {
                            Navigator.pop(context);
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              useSafeArea: true,
                              builder: (_) =>
                                  _WordDetailsSheet(word: s),
                            );
                          },
                        ))
                    .toList(),
              ),
            ],

            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addToVocab,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить в словарь'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RelatedChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final Color? color;

  const _RelatedChip({
    required this.text,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = color ?? cs.primaryContainer;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: color != null
                    ? cs.onErrorContainer
                    : cs.onPrimaryContainer,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
