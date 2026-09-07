import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../services/exercise_data.dart';

/// Текст показывается целиком, затем слова по одному "выгорают".
/// Когда все слова исчезли — нужно вписать пропавшие по памяти.
class InvisibleWordsScreen extends StatefulWidget {
  const InvisibleWordsScreen({super.key});

  @override
  State<InvisibleWordsScreen> createState() => _InvisibleWordsScreenState();
}

class _InvisibleWordsScreenState extends State<InvisibleWordsScreen> {
  final _rand = Random();

  late ReaderText _text;
  late List<_Tok> _tokens;
  late List<int> _wordPositions; // indexes in _tokens that are words
  late Set<int> _hidden;
  late Map<int, TextEditingController> _ctrl;

  Timer? _decayTimer;
  bool _phaseRecall = false; // false = reading, true = fill blanks
  int _previewSeconds = 8;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _text = ExerciseData
        .readerTexts[_rand.nextInt(ExerciseData.readerTexts.length)];
    _tokens = _tokenize(_text.body);
    _wordPositions = [
      for (int i = 0; i < _tokens.length; i++)
        if (_tokens[i].isWord && _tokens[i].text.length > 2) i,
    ];
    _hidden = <int>{};
    _ctrl = {};
    _phaseRecall = false;
    _previewSeconds = 8;

    _decayTimer?.cancel();

    // Сначала отсчёт чтения, потом начинаем выгорать слова.
    _decayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_previewSeconds > 0) {
          _previewSeconds--;
        } else {
          _hideOneRandomWord();
        }
      });
      if (_hidden.length >= _wordPositions.length) {
        t.cancel();
        _enterRecall();
      }
    });
  }

  void _hideOneRandomWord() {
    final available =
        _wordPositions.where((i) => !_hidden.contains(i)).toList();
    if (available.isEmpty) return;
    available.shuffle(_rand);
    // Скрываем по 1 слову раз в тик
    _hidden.add(available.first);
  }

  void _enterRecall() {
    setState(() {
      _phaseRecall = true;
      for (final i in _hidden) {
        _ctrl[i] = TextEditingController();
      }
    });
  }

  void _stopAndShowAll() {
    _decayTimer?.cancel();
    setState(() {
      _hidden = _wordPositions.toSet();
    });
    _enterRecall();
  }

  String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  bool _isCorrect(int i) {
    final c = _ctrl[i];
    if (c == null) return false;
    return _norm(c.text) == _norm(_tokens[i].text);
  }

  void _restart() {
    for (final c in _ctrl.values) c.dispose();
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final hiddenTotal = _hidden.length;
    final correctNow = _phaseRecall
        ? _hidden.where(_isCorrect).length
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Слово-невидимка'),
        actions: [
          IconButton(
            tooltip: 'Заново',
            onPressed: _restart,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Статус
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _phaseRecall
                      ? cs.primaryContainer.withOpacity(0.4)
                      : cs.tertiaryContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(
                      _phaseRecall
                          ? Icons.psychology_rounded
                          : (_previewSeconds > 0
                              ? Icons.menu_book_rounded
                              : Icons.visibility_off_rounded),
                      color: cs.onSurface,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _phaseRecall
                            ? 'Восстановите $hiddenTotal слов(а) — верно: $correctNow'
                            : (_previewSeconds > 0
                                ? 'Читайте текст внимательно — $_previewSeconds с'
                                : 'Слова исчезают…'),
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.3)),
                    ),
                    child: _phaseRecall
                        ? _buildRecallText(cs, tt)
                        : _buildDecayingText(cs, tt),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              if (!_phaseRecall && _previewSeconds == 0)
                OutlinedButton.icon(
                  onPressed: _stopAndShowAll,
                  icon: const Icon(Icons.fast_forward_rounded),
                  label: const Text('Скрыть всё и проверить'),
                )
              else if (_phaseRecall)
                FilledButton.icon(
                  onPressed: _restart,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(
                      'Готово. Верно $correctNow / $hiddenTotal · Заново'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54)),
                ).animate().fadeIn(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDecayingText(ColorScheme cs, TextTheme tt) {
    return Text.rich(
      TextSpan(
        children: List.generate(_tokens.length, (i) {
          final tok = _tokens[i];
          if (!tok.isWord || !_hidden.contains(i)) {
            return TextSpan(
              text: tok.text,
              style: tt.titleMedium?.copyWith(height: 1.7),
            );
          }
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: tok.text.length * 9.0,
              height: 18,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            ).animate().fadeIn(duration: 350.ms).blurXY(end: 6, duration: 350.ms),
          );
        }),
      ),
    );
  }

  Widget _buildRecallText(ColorScheme cs, TextTheme tt) {
    return Text.rich(
      TextSpan(
        children: List.generate(_tokens.length, (i) {
          final tok = _tokens[i];
          if (!tok.isWord || !_hidden.contains(i)) {
            return TextSpan(
              text: tok.text,
              style: tt.titleMedium?.copyWith(height: 1.9),
            );
          }
          final ctrl = _ctrl[i];
          return WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: SizedBox(
              width: (tok.text.length * 11.0).clamp(56, 160),
              child: TextField(
                controller: ctrl,
                textAlign: TextAlign.center,
                style: tt.titleMedium
                    ?.copyWith(height: 1.0, fontWeight: FontWeight.w600),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 6, horizontal: 6),
                  filled: true,
                  fillColor: _isCorrect(i)
                      ? Colors.green.withOpacity(0.12)
                      : cs.surfaceContainerHighest.withOpacity(0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _isCorrect(i)
                          ? Colors.green
                          : cs.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: _isCorrect(i)
                          ? Colors.green
                          : cs.outlineVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  @override
  void dispose() {
    _decayTimer?.cancel();
    for (final c in _ctrl.values) c.dispose();
    super.dispose();
  }
}

class _Tok {
  final String text;
  final bool isWord;
  _Tok(this.text, this.isWord);
}

List<_Tok> _tokenize(String body) {
  final out = <_Tok>[];
  final regex = RegExp(r"[A-Za-z][A-Za-z'\-]*|[^A-Za-z]+");
  for (final m in regex.allMatches(body)) {
    final s = m.group(0)!;
    final isWord = RegExp(r'^[A-Za-z]').hasMatch(s);
    out.add(_Tok(s, isWord));
  }
  return out;
}
