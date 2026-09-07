import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';
import '../../services/tts_service.dart';

/// TTS читает предложение целиком, в тексте каждое N-е слово (по умолчанию 5-е)
/// заменено пропуском — пользователь вписывает слова на слух.
class DictationScreen extends StatefulWidget {
  const DictationScreen({super.key});

  @override
  State<DictationScreen> createState() => _DictationScreenState();
}

class _DictationScreenState extends State<DictationScreen> {
  int _index = 0;
  int _gapEvery = 5;
  bool _checked = false;

  late List<String> _words;
  late List<int> _gapIndexes;
  late Map<int, TextEditingController> _ctrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final s = ExerciseData.dictationItems[_index].sentence;
    _words = s.split(RegExp(r'\s+'));
    _gapIndexes = [
      for (int i = 0; i < _words.length; i++)
        if ((i + 1) % _gapEvery == 0) i,
    ];
    if (_gapIndexes.isEmpty && _words.isNotEmpty) {
      // Гарантируем хотя бы один пропуск
      _gapIndexes = [_words.length - 1];
    }
    _ctrl = {for (final i in _gapIndexes) i: TextEditingController()};
    _checked = false;
  }

  Future<void> _play() async {
    await TtsService.setSpeechRate(0.45);
    await TtsService.speak(ExerciseData.dictationItems[_index].sentence);
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _isFilledCorrect(int i) =>
      _norm(_ctrl[i]?.text ?? '') == _norm(_words[i]);

  void _check() => setState(() => _checked = true);

  void _next() {
    setState(() {
      _index = (_index + 1) % ExerciseData.dictationItems.length;
      for (final c in _ctrl.values) {
        c.dispose();
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final correctCount =
        _gapIndexes.where((i) => _isFilledCorrect(i)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Диктант с пробелами'),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Сложность',
            initialValue: _gapEvery,
            icon: const Icon(Icons.tune_rounded),
            onSelected: (v) {
              setState(() {
                _gapEvery = v;
                for (final c in _ctrl.values) c.dispose();
                _load();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Легко (каждое 7-е)')),
              PopupMenuItem(value: 5, child: Text('Средне (каждое 5-е)')),
              PopupMenuItem(value: 3, child: Text('Сложно (каждое 3-е)')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _play,
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Прослушать'),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: List.generate(_words.length, (i) {
                    if (_gapIndexes.contains(i)) {
                      return _GapField(
                        controller: _ctrl[i]!,
                        target: _words[i],
                        showCheck: _checked,
                      );
                    }
                    return Text(_words[i],
                        style: tt.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w500));
                  }),
                ),
              ).animate(key: ValueKey(_index)).fadeIn(),

              if (_checked) ...[
                const SizedBox(height: 16),
                Text(
                  'Верно: $correctCount / ${_gapIndexes.length}',
                  style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: correctCount == _gapIndexes.length
                          ? Colors.green
                          : cs.onSurface),
                ),
              ],
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _next,
                      child: const Text('Дальше'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _checked ? null : _check,
                      child: const Text('Проверить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final c in _ctrl.values) c.dispose();
    TtsService.stop();
    super.dispose();
  }
}

class _GapField extends StatelessWidget {
  final TextEditingController controller;
  final String target;
  final bool showCheck;

  const _GapField({
    required this.controller,
    required this.target,
    required this.showCheck,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final correct = controller.text.toLowerCase().replaceAll(
              RegExp(r'[^a-z0-9]'),
              '',
            ) ==
        target.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    Color border = cs.outlineVariant;
    if (showCheck) border = correct ? Colors.green : cs.error;

    return SizedBox(
      width: (target.length * 12.0).clamp(70, 180),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          filled: true,
          fillColor: showCheck
              ? (correct
                  ? Colors.green.withOpacity(0.08)
                  : cs.error.withOpacity(0.08))
              : cs.surfaceContainerHighest.withOpacity(0.3),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border, width: 1.4),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border, width: 1.4),
          ),
          hintText: showCheck && !correct ? target : '...',
          hintStyle: TextStyle(
            color: showCheck && !correct
                ? Colors.green
                : cs.onSurfaceVariant.withOpacity(0.5),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}
