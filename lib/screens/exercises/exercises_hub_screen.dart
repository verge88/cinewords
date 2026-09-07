import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/vocabulary_provider.dart';
import 'semantic_clusters_screen.dart';
import 'definition_to_word_screen.dart';
import 'shadow_repetition_screen.dart';
import 'dictation_screen.dart';
import 'minimal_pairs_screen.dart';
import 'sentence_builder_screen.dart';
import 'tense_transformation_screen.dart';
import 'cloze_screen.dart';
import 'tap_reader_screen.dart';
import 'invisible_words_screen.dart';

class _ExerciseGroup {
  final String title;
  final List<_ExerciseInfo> items;
  const _ExerciseGroup(this.title, this.items);
}

class _ExerciseInfo {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
  const _ExerciseInfo({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.builder,
  });
}

class ExercisesHubScreen extends StatelessWidget {
  const ExercisesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final groups = <_ExerciseGroup>[
      _ExerciseGroup('Словарный запас', [
        _ExerciseInfo(
          title: 'Интервальное повторение',
          description: 'SRS: карточки с алгоритмом SM-2',
          icon: Icons.style_rounded,
          color: cs.primary,
          builder: (_) => _OpenReviewMode(),
        ),
        _ExerciseInfo(
          title: 'Семантические кластеры',
          description: 'Сгруппируй слова по теме',
          icon: Icons.bubble_chart_rounded,
          color: cs.secondary,
          builder: (_) => const SemanticClustersScreen(),
        ),
        _ExerciseInfo(
          title: 'Определение → слово',
          description: 'Угадай слово по определению (Wiktionary)',
          icon: Icons.menu_book_rounded,
          color: cs.tertiary,
          builder: (_) => const DefinitionToWordScreen(),
        ),
      ]),
      _ExerciseGroup('Аудирование и произношение', [
        _ExerciseInfo(
          title: 'Теневое повторение',
          description: 'Повтори за TTS',
          icon: Icons.record_voice_over_rounded,
          color: Colors.orange,
          builder: (_) => const ShadowRepetitionScreen(),
        ),
        _ExerciseInfo(
          title: 'Диктант с пробелами',
          description: 'Впиши пропущенные слова',
          icon: Icons.edit_note_rounded,
          color: Colors.indigo,
          builder: (_) => const DictationScreen(),
        ),
        _ExerciseInfo(
          title: 'Минимальные пары',
          description: 'ship/sheep, bit/beat',
          icon: Icons.compare_arrows_rounded,
          color: Colors.teal,
          builder: (_) => const MinimalPairsScreen(),
        ),
      ]),
      _ExerciseGroup('Грамматика', [
        _ExerciseInfo(
          title: 'Конструктор предложений',
          description: 'Расставь слова по порядку',
          icon: Icons.reorder_rounded,
          color: Colors.deepPurple,
          builder: (_) => const SentenceBuilderScreen(),
        ),
        _ExerciseInfo(
          title: 'Трансформация времён',
          description: 'Перепиши предложение в другом времени',
          icon: Icons.swap_horiz_rounded,
          color: Colors.pink,
          builder: (_) => const TenseTransformationScreen(),
        ),
        _ExerciseInfo(
          title: 'Заполни пропуск',
          description: 'Cloze: 4 варианта, один верный',
          icon: Icons.short_text_rounded,
          color: Colors.amber,
          builder: (_) => const ClozeScreen(),
        ),
      ]),
      _ExerciseGroup('Чтение и контекст', [
        _ExerciseInfo(
          title: 'Читалка с тапом на слово',
          description: 'Тап → определение, добавление в SRS',
          icon: Icons.touch_app_rounded,
          color: Colors.lightBlue,
          builder: (_) => const TapReaderScreen(),
        ),
        _ExerciseInfo(
          title: 'Слово-невидимка',
          description: 'Восстанови исчезающие слова по памяти',
          icon: Icons.visibility_off_rounded,
          color: Colors.redAccent,
          builder: (_) => const InvisibleWordsScreen(),
        ),
      ]),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Упражнения', style: tt.headlineSmall),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        itemCount: groups.length,
        itemBuilder: (context, gi) {
          final group = groups[gi];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 16, bottom: 12, left: 4),
                child: Text(
                  group.title.toUpperCase(),
                  style: tt.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...group.items.asMap().entries.map((e) {
                final idx = e.key;
                final info = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExerciseTile(info: info)
                      .animate(delay: ((gi * 100) + idx * 60).ms)
                      .fadeIn()
                      .slideX(begin: 0.05),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  final _ExerciseInfo info;
  const _ExerciseTile({required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: info.builder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: info.color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(info.icon, color: info.color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(info.title,
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(info.description,
                        style: tt.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Перенаправляет на VocabularyScreen и сразу открывает review-режим (SRS).
class _OpenReviewMode extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vocab = context.read<VocabularyProvider>();
      vocab.preparePractice();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Откройте раздел Words, чтобы продолжить SRS-сессию'),
        ),
      );
    });
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
