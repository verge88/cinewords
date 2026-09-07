import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';

class TenseTransformationScreen extends StatefulWidget {
  const TenseTransformationScreen({super.key});

  @override
  State<TenseTransformationScreen> createState() =>
      _TenseTransformationScreenState();
}

class _TenseTransformationScreenState extends State<TenseTransformationScreen> {
  final _rand = Random();
  final TextEditingController _input = TextEditingController();

  late TenseItem _item;
  bool _checked = false;
  bool _correct = false;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    setState(() {
      _item = ExerciseData
          .tenseItems[_rand.nextInt(ExerciseData.tenseItems.length)];
      _input.clear();
      _checked = false;
      _correct = false;
      _showHint = false;
    });
  }

  String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'[.!?,]'), '')
      .trim();

  void _check() {
    final guess = _norm(_input.text);
    final ok = _item.answers.any((a) => _norm(a) == guess);
    setState(() {
      _checked = true;
      _correct = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Трансформация времён'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Шапка: from → to
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TensePill(label: _item.from, color: cs.secondary),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward_rounded),
                ),
                _TensePill(label: _item.to, color: cs.primary),
              ],
            ),
            const SizedBox(height: 20),

            // База
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: Text(_item.base,
                  style: tt.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600, height: 1.4)),
            ).animate(key: ValueKey(_item.base)).fadeIn(),

            const SizedBox(height: 20),
            TextField(
              controller: _input,
              maxLines: 2,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Перепишите в ${_item.to}',
                fillColor: _checked
                    ? (_correct
                        ? Colors.green.withOpacity(0.08)
                        : cs.error.withOpacity(0.08))
                    : null,
                filled: _checked,
                suffixIcon: _checked
                    ? Icon(_correct ? Icons.check_circle : Icons.error,
                        color: _correct ? Colors.green : cs.error)
                    : null,
              ),
              onSubmitted: (_) => _check(),
            ),
            const SizedBox(height: 8),
            if (_showHint || (_checked && !_correct)) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lightbulb_outline_rounded,
                        color: cs.onTertiaryContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _item.answers.first,
                        style: tt.bodyLarge?.copyWith(
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(),
            ],

            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showHint = true),
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    label: const Text('Подсказка'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _checked
                      ? FilledButton.icon(
                          onPressed: _next,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Дальше'),
                        )
                      : FilledButton(
                          onPressed: _check,
                          child: const Text('Проверить'),
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
    _input.dispose();
    super.dispose();
  }
}

class _TensePill extends StatelessWidget {
  final String label;
  final Color color;
  const _TensePill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5)),
    );
  }
}
