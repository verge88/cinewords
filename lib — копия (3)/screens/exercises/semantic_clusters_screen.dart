import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';
import '../../services/tts_service.dart';

class SemanticClustersScreen extends StatefulWidget {
  const SemanticClustersScreen({super.key});

  @override
  State<SemanticClustersScreen> createState() => _SemanticClustersScreenState();
}

class _SemanticClustersScreenState extends State<SemanticClustersScreen> {
  late ClusterSet _set;
  late List<String> _pool;
  late Map<String, List<String>> _placed;

  int _setIndex = 0;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _loadSet(_setIndex);
  }

  void _loadSet(int i) {
    _set = ExerciseData.clusterSets[i % ExerciseData.clusterSets.length];
    final all = <String>[];
    for (final c in _set.clusters) {
      all.addAll(c.words);
    }
    all.shuffle();
    _pool = all;
    _placed = {for (final c in _set.clusters) c.name: <String>[]};
    _checked = false;
  }

  void _check() {
    setState(() => _checked = true);
  }

  bool _isCorrect(String cluster, String word) {
    final c = _set.clusters.firstWhere((x) => x.name == cluster);
    return c.words.contains(word);
  }

  int _correctCount() {
    int n = 0;
    for (final entry in _placed.entries) {
      for (final w in entry.value) {
        if (_isCorrect(entry.key, w)) n++;
      }
    }
    return n;
  }

  int _total() => _set.clusters.fold(0, (s, c) => s + c.words.length);

  void _next() {
    setState(() {
      _setIndex = (_setIndex + 1) % ExerciseData.clusterSets.length;
      _loadSet(_setIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Семантические кластеры'),
        actions: [
          IconButton(
            tooltip: 'Сбросить',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => setState(() => _loadSet(_setIndex)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(_set.title,
                style:
                    tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),

            // Пул слов
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: DragTarget<String>(
                onAcceptWithDetails: (details) {
                  setState(() {
                    _placed.forEach((_, list) => list.remove(details.data));
                    if (!_pool.contains(details.data)) {
                      _pool.add(details.data);
                    }
                  });
                },
                builder: (ctx, _, __) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: _pool.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text('Все слова разложены 👇',
                                style: tt.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant)),
                          )
                        ]
                      : _pool.map((w) => _DraggableWord(word: w)).toList(),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Кластеры
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.85,
                children: _set.clusters.map((c) {
                  final words = _placed[c.name] ?? const [];
                  return DragTarget<String>(
                    onAcceptWithDetails: (details) {
                      setState(() {
                        _pool.remove(details.data);
                        _placed.forEach(
                            (_, list) => list.remove(details.data));
                        _placed[c.name]!.add(details.data);
                      });
                    },
                    builder: (ctx, candidate, __) {
                      final hovering = candidate.isNotEmpty;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: hovering
                              ? cs.primaryContainer.withOpacity(0.4)
                              : cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hovering
                                ? cs.primary
                                : cs.outlineVariant.withOpacity(0.3),
                            width: hovering ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(c.emoji,
                                    style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 6),
                                Text(c.name,
                                    style: tt.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w700)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: SingleChildScrollView(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: words.map((w) {
                                    final correct = _isCorrect(c.name, w);
                                    Color bg = cs.primary.withOpacity(0.15);
                                    Color fg = cs.primary;
                                    if (_checked) {
                                      bg = correct
                                          ? Colors.green.withOpacity(0.18)
                                          : Colors.red.withOpacity(0.18);
                                      fg = correct ? Colors.green : Colors.red;
                                    }
                                    return _DraggableWord(
                                      word: w,
                                      background: bg,
                                      foreground: fg,
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 12),

            if (_checked)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Верно: ${_correctCount()} / ${_total()}',
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _correctCount() == _total()
                        ? Colors.green
                        : cs.onSurface,
                  ),
                ).animate().fadeIn(),
              ),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _checked ? _next : null,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Дальше'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pool.isEmpty && !_checked ? _check : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Проверить'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DraggableWord extends StatelessWidget {
  final String word;
  final Color? background;
  final Color? foreground;

  const _DraggableWord({
    required this.word,
    this.background,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = background ?? cs.secondaryContainer;
    final fg = foreground ?? cs.onSecondaryContainer;
    final chip = _Chip(text: word, bg: bg, fg: fg);

    return Draggable<String>(
      data: word,
      feedback: Material(
        color: Colors.transparent,
        child: _Chip(text: word, bg: cs.primary, fg: cs.onPrimary),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(
        onLongPress: () => TtsService.speak(word),
        child: chip,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const _Chip({required this.text, required this.bg, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: fg, fontWeight: FontWeight.w600),
      ),
    );
  }
}
