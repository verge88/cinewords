import 'package:flutter/material.dart';
import '../models/user_progress.dart';

/// Bento-сетка статистики 2x2 в едином тёмном стиле.
/// Используется на экране профиля.
class StatsBento extends StatelessWidget {
  final UserProgress progress;
  final int newCount;
  final int learningCount;

  const StatsBento({
    super.key,
    required this.progress,
    required this.newCount,
    required this.learningCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.bolt_rounded,
                label: 'Сегодня слов',
                value: '${progress.todayWords}',
                color: const Color(0xFF7C6CFF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BentoTile(
                icon: Icons.history_toggle_off_rounded,
                label: 'К повтору',
                value: '${progress.wordsToReview}',
                color: const Color(0xFFFFB74D),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: BentoTile(
                icon: Icons.school_rounded,
                label: 'Изучено',
                value: '${progress.totalWordsLearned}',
                color: const Color(0xFF4CAF50),
                valueColorOverride: const Color(0xFF66BB6A),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: BentoTile(
                icon: Icons.psychology_rounded,
                label: 'В процессе',
                value: '${learningCount + newCount}',
                color: const Color(0xFF00BFA5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Одна плитка bento — тёмный фон, цветная иконка, крупное значение.
class BentoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color? valueColorOverride;

  const BentoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.valueColorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Color bg = isDark ? const Color(0xFF16151C) : cs.surfaceContainerLow;
    final Color fg = isDark ? Colors.white : cs.onSurface;
    final Color fgDim =
        isDark ? Colors.white.withOpacity(0.6) : cs.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(22),
        border: isDark
            ? Border.all(color: Colors.white.withOpacity(0.07))
            : Border.all(color: cs.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.16 : 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: tt.headlineSmall?.copyWith(
              color: valueColorOverride != null && isDark
                  ? valueColorOverride
                  : fg,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: tt.bodySmall?.copyWith(color: fgDim),
          ),
        ],
      ),
    );
  }
}
