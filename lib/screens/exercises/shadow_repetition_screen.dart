import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';
import '../../services/tts_service.dart';

/// Shadow repetition: TTS читает фразу (можно медленно), пользователь повторяет
/// вслух, затем вписывает то что произнёс — сравниваем строки по Левенштейну.
/// (Без зависимости от speech_to_text, чтобы упражнение работало сразу.)
class ShadowRepetitionScreen extends StatefulWidget {
  const ShadowRepetitionScreen({super.key});

  @override
  State<ShadowRepetitionScreen> createState() => _ShadowRepetitionScreenState();
}

class _ShadowRepetitionScreenState extends State<ShadowRepetitionScreen> {
  int _index = 0;
  bool _slow = false;
  bool _checked = false;
  int _distance = 0;
  double _similarity = 0;
  final TextEditingController _input = TextEditingController();

  String get _phrase => ExerciseData.shadowPhrases[_index];

  Future<void> _playPhrase() async {
    await TtsService.setSpeechRate(_slow ? 0.3 : 0.45);
    await TtsService.speak(_phrase);
  }

  void _check() {
    final guess = _input.text.trim().toLowerCase();
    final target = _normalize(_phrase);
    final dist = _levenshtein(_normalize(guess), target);
    final maxLen = target.length == 0 ? 1 : target.length;
    setState(() {
      _checked = true;
      _distance = dist;
      _similarity = (1 - dist / maxLen).clamp(0.0, 1.0);
    });
  }

  String _normalize(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final prev = List<int>.filled(b.length + 1, 0);
    final curr = List<int>.filled(b.length + 1, 0);
    for (int j = 0; j <= b.length; j++) prev[j] = j;
    for (int i = 1; i <= a.length; i++) {
      curr[0] = i;
      for (int j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        curr[j] = [
          curr[j - 1] + 1,
          prev[j] + 1,
          prev[j - 1] + cost,
        ].reduce((v, e) => v < e ? v : e);
      }
      for (int j = 0; j <= b.length; j++) prev[j] = curr[j];
    }
    return prev[b.length];
  }

  void _next() {
    setState(() {
      _index = (_index + 1) % ExerciseData.shadowPhrases.length;
      _checked = false;
      _distance = 0;
      _similarity = 0;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Теневое повторение'),
        actions: [
          IconButton(
            tooltip: 'Следующая фраза',
            onPressed: _next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Шаг 1. Прослушайте фразу',
                style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: Text(_phrase,
                  style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700, height: 1.4)),
            ).animate(key: ValueKey(_index)).fadeIn().slideY(begin: 0.05),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _playPhrase,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Прослушать'),
                  ),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: Text(_slow ? 'Медленно' : 'Норма'),
                  avatar: Icon(_slow
                      ? Icons.slow_motion_video_rounded
                      : Icons.speed_rounded),
                  selected: _slow,
                  onSelected: (v) => setState(() => _slow = v),
                ),
              ],
            ),
            const SizedBox(height: 24),

            Text('Шаг 2. Повторите вслух, затем впишите что произнесли',
                style: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            TextField(
              controller: _input,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'То, что вы только что сказали...',
              ),
              onSubmitted: (_) => _check(),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _check,
              style:
                  FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text('Проверить'),
            ),

            if (_checked) ...[
              const SizedBox(height: 24),
              _ScoreCard(
                similarity: _similarity,
                distance: _distance,
                target: _phrase,
                guess: _input.text,
              ).animate().fadeIn().slideY(begin: 0.1),
              const Spacer(),
              FilledButton.icon(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                ),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Следующая'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _input.dispose();
    TtsService.stop();
    super.dispose();
  }
}

class _ScoreCard extends StatelessWidget {
  final double similarity;
  final int distance;
  final String target;
  final String guess;
  const _ScoreCard({
    required this.similarity,
    required this.distance,
    required this.target,
    required this.guess,
  });

  Color _color(BuildContext ctx) {
    if (similarity >= 0.85) return Colors.green;
    if (similarity >= 0.6) return Colors.orange;
    return Theme.of(ctx).colorScheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = _color(context);
    final pct = (similarity * 100).round();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(similarity >= 0.85 ? Icons.celebration : Icons.equalizer,
                  color: color),
              const SizedBox(width: 8),
              Text('Совпадение: $pct%',
                  style: tt.titleMedium?.copyWith(
                      color: color, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('Δ $distance',
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: similarity,
              minHeight: 8,
              color: color,
              backgroundColor: color.withOpacity(0.15),
            ),
          ),
        ],
      ),
    );
  }
}
