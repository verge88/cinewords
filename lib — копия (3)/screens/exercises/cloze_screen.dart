import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';

class ClozeScreen extends StatefulWidget {
  const ClozeScreen({super.key});

  @override
  State<ClozeScreen> createState() => _ClozeScreenState();
}

class _ClozeScreenState extends State<ClozeScreen> {
  final _rand = Random();
  late ClozeItem _item;
  int? _selected;
  int _correctStreak = 0;

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    setState(() {
      _item = ExerciseData
          .clozeItems[_rand.nextInt(ExerciseData.clozeItems.length)];
      _selected = null;
    });
  }

  void _choose(int i) {
    if (_selected != null) return;
    setState(() {
      _selected = i;
      if (i == _item.correctIndex) {
        _correctStreak += 1;
      } else {
        _correctStreak = 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final parts = _item.sentence.split('___');
    final left = parts.isNotEmpty ? parts[0] : '';
    final right = parts.length > 1 ? parts[1] : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Заполни пропуск'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded,
                      color: cs.tertiary, size: 18),
                  const SizedBox(width: 4),
                  Text('$_correctStreak',
                      style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.tertiary)),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(24),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: tt.headlineSmall?.copyWith(
                        height: 1.5, color: cs.onSurface),
                    children: [
                      TextSpan(text: left),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: _GapBox(
                          text: _selected == null
                              ? '_____'
                              : _item.options[_selected!],
                          color: _selected == null
                              ? cs.primary
                              : (_selected == _item.correctIndex
                                  ? Colors.green
                                  : cs.error),
                        ),
                      ),
                      TextSpan(text: right),
                    ],
                  ),
                ),
              ).animate(key: ValueKey(_item.sentence)).fadeIn(),
              const SizedBox(height: 24),
              ...List.generate(_item.options.length, (i) {
                final opt = _item.options[i];
                Color bg = cs.surfaceContainerLow;
                Color fg = cs.onSurface;
                Color border = cs.outlineVariant.withOpacity(0.3);
                if (_selected != null) {
                  if (i == _item.correctIndex) {
                    bg = Colors.green.withOpacity(0.15);
                    fg = Colors.green;
                    border = Colors.green;
                  } else if (i == _selected) {
                    bg = cs.error.withOpacity(0.15);
                    fg = cs.error;
                    border = cs.error;
                  }
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: bg,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      onTap: () => _choose(i),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: border,
                            width: _selected != null ? 1.6 : 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                            vertical: 18, horizontal: 20),
                        child: Center(
                          child: Text(opt,
                              style: tt.titleMedium?.copyWith(
                                  color: fg, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const Spacer(),
              if (_selected != null)
                FilledButton.icon(
                  onPressed: _next,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('Следующее'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                ).animate().fadeIn().slideY(begin: 0.1),
            ],
          ),
        ),
      ),
    );
  }
}

class _GapBox extends StatelessWidget {
  final String text;
  final Color color;
  const _GapBox({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color, fontWeight: FontWeight.w800)),
    );
  }
}
