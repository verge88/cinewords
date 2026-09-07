import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';

/// Слова перемешаны — нужно собрать предложение тапом, в правильном порядке.
/// При ошибке подсвечивается нужная позиция. Опциональный таймер.
class SentenceBuilderScreen extends StatefulWidget {
  const SentenceBuilderScreen({super.key});

  @override
  State<SentenceBuilderScreen> createState() => _SentenceBuilderScreenState();
}

class _SentenceBuilderScreenState extends State<SentenceBuilderScreen> {
  final _rand = Random();

  late List<_Word> _pool;
  late List<_Word> _placed;
  late List<String> _target;
  int? _hintIndex;
  bool _completed = false;
  bool _correct = false;
  Timer? _timer;
  int _seconds = 0;
  bool _timerOn = true;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    final s = ExerciseData
        .sentenceBank[_rand.nextInt(ExerciseData.sentenceBank.length)];
    final words = s.split(' ');
    _target = words;
    final shuffled = [
      for (int i = 0; i < words.length; i++) _Word(id: i, text: words[i]),
    ]..shuffle(_rand);
    setState(() {
      _pool = shuffled;
      _placed = [];
      _hintIndex = null;
      _completed = false;
      _correct = false;
      _seconds = 0;
    });
    _timer?.cancel();
    if (_timerOn) {
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => setState(() => _seconds++));
    }
  }

  void _pickFromPool(int i) {
    if (_completed) return;
    final word = _pool[i];
    final expected = _target[_placed.length];

    setState(() {
      if (word.text.toLowerCase() == expected.toLowerCase()) {
        _placed.add(word);
        _pool.removeAt(i);
        _hintIndex = null;
        if (_placed.length == _target.length) _finalize(true);
      } else {
        _hintIndex = _placed.length; // подсветить нужную позицию
      }
    });
  }

  void _undoLast() {
    if (_placed.isEmpty || _completed) return;
    setState(() {
      final w = _placed.removeLast();
      _pool.add(w);
      _hintIndex = null;
    });
  }

  void _finalize(bool correct) {
    _timer?.cancel();
    setState(() {
      _completed = true;
      _correct = correct;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Конструктор предложений'),
        actions: [
          if (_timerOn)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('$_seconds s',
                      style: tt.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.onTertiaryContainer)),
                ),
              ),
            ),
          IconButton(
            tooltip: _timerOn ? 'Выключить таймер' : 'Включить таймер',
            onPressed: () => setState(() {
              _timerOn = !_timerOn;
              _timer?.cancel();
              if (_timerOn) {
                _timer = Timer.periodic(const Duration(seconds: 1),
                    (_) => setState(() => _seconds++));
              }
            }),
            icon: Icon(_timerOn
                ? Icons.timer_outlined
                : Icons.timer_off_outlined),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Зона собранного предложения с подсветкой нужной позиции
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _completed && _correct
                      ? Colors.green
                      : cs.outlineVariant.withOpacity(0.3),
                  width: _completed && _correct ? 2 : 1,
                ),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (int i = 0; i < _placed.length; i++)
                    _PlacedChip(text: _placed[i].text, color: cs.primary),
                  if (!_completed && _hintIndex == _placed.length)
                    _HintSlot(needed: _target[_placed.length])
                        .animate()
                        .shake(hz: 4, duration: 400.ms),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Пул слов
            Expanded(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: List.generate(_pool.length, (i) {
                    return _PoolWord(
                      text: _pool[i].text,
                      onTap: () => _pickFromPool(i),
                    );
                  }),
                ),
              ),
            ),

            if (_completed)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(_correct ? Icons.check_circle : Icons.error,
                        color: _correct ? Colors.green : cs.error),
                    const SizedBox(width: 8),
                    Text(
                      _correct
                          ? 'Готово за $_seconds сек!'
                          : 'Подсказка: ${_target.join(' ')}',
                      style: tt.titleSmall?.copyWith(
                          color: _correct ? Colors.green : cs.error,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _undoLast,
                    icon: const Icon(Icons.undo_rounded),
                    label: const Text('Отменить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward_rounded),
                    label: const Text('Следующее'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _Word {
  final int id;
  final String text;
  _Word({required this.id, required this.text});
}

class _PlacedChip extends StatelessWidget {
  final String text;
  final Color color;
  const _PlacedChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _HintSlot extends StatelessWidget {
  final String needed;
  const _HintSlot({required this.needed});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cs.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error),
      ),
      child: Text(
        '? (${needed[0]}…)',
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: cs.error, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PoolWord extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _PoolWord({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: cs.onSecondaryContainer,
                fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
