import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';
import '../../services/tts_service.dart';

/// Tap to play one of two similar words; user guesses which one was said.
class MinimalPairsScreen extends StatefulWidget {
  const MinimalPairsScreen({super.key});

  @override
  State<MinimalPairsScreen> createState() => _MinimalPairsScreenState();
}

class _MinimalPairsScreenState extends State<MinimalPairsScreen> {
  final _rand = Random();
  late MinimalPair _pair;
  late bool _playA; // played word == _pair.a
  bool _answered = false;
  bool _correct = false;
  int _streak = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _next(initial: true);
  }

  Future<void> _next({bool initial = false}) async {
    setState(() {
      _pair = ExerciseData
          .minimalPairs[_rand.nextInt(ExerciseData.minimalPairs.length)];
      _playA = _rand.nextBool();
      _answered = false;
      _correct = false;
    });
    // Auto-play first time
    if (initial) {
      await Future.delayed(const Duration(milliseconds: 350));
      _playTarget();
    }
  }

  Future<void> _playTarget() async {
    await TtsService.setSpeechRate(0.4);
    await TtsService.speak(_playA ? _pair.a : _pair.b);
  }

  Future<void> _playWord(String w) async {
    await TtsService.setSpeechRate(0.4);
    await TtsService.speak(w);
  }

  void _choose(bool chooseA) {
    if (_answered) return;
    setState(() {
      _answered = true;
      _correct = chooseA == _playA;
      _total += 1;
      _streak = _correct ? _streak + 1 : 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Минимальные пары'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: cs.tertiary, size: 18),
                  const SizedBox(width: 4),
                  Text('$_streak',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700, color: cs.tertiary)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Spacer(),
            Text('Что вы услышали?',
                style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(_pair.contrast,
                style: tt.labelLarge?.copyWith(
                    color: cs.primary,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _playTarget,
              icon: const Icon(Icons.headset_rounded),
              label: const Text('Прослушать ещё раз'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(220, 54)),
            ),
            const SizedBox(height: 36),
            Row(
              children: [
                Expanded(
                  child: _PairCard(
                    word: _pair.a,
                    isAnswered: _answered,
                    isCorrect: _answered && _playA,
                    isWrongChoice: _answered && !_playA && !_correct,
                    onTap: () => _choose(true),
                    onSpeak: () => _playWord(_pair.a),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PairCard(
                    word: _pair.b,
                    isAnswered: _answered,
                    isCorrect: _answered && !_playA,
                    isWrongChoice: _answered && _playA && !_correct,
                    onTap: () => _choose(false),
                    onSpeak: () => _playWord(_pair.b),
                  ),
                ),
              ],
            ).animate(key: ValueKey('${_pair.a}-${_pair.b}-$_total')).fadeIn(),
            const Spacer(),
            if (_answered)
              FilledButton.icon(
                onPressed: () => _next(),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Следующая пара'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54)),
              ).animate().fadeIn().slideY(begin: 0.1)
            else
              const SizedBox(height: 54),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    TtsService.stop();
    super.dispose();
  }
}

class _PairCard extends StatelessWidget {
  final String word;
  final bool isAnswered;
  final bool isCorrect;
  final bool isWrongChoice;
  final VoidCallback onTap;
  final VoidCallback onSpeak;

  const _PairCard({
    required this.word,
    required this.isAnswered,
    required this.isCorrect,
    required this.isWrongChoice,
    required this.onTap,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Color bg = cs.surfaceContainerLow;
    Color border = cs.outlineVariant.withOpacity(0.3);
    Color text = cs.onSurface;
    if (isAnswered) {
      if (isCorrect) {
        bg = Colors.green.withOpacity(0.18);
        border = Colors.green;
        text = Colors.green;
      } else if (isWrongChoice) {
        bg = cs.error.withOpacity(0.18);
        border = cs.error;
        text = cs.error;
      }
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border, width: isAnswered ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(word,
                style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: text)),
            const SizedBox(height: 8),
            IconButton.filledTonal(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
