import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../models/subtitle_line.dart';

class DualSubtitlesWidget extends StatelessWidget {
  final SubtitleLine? englishLine;
  final SubtitleLine? russianLine;
  final bool showTranslation;
  final void Function(String word, SubtitleLine line) onWordTap;
  final VoidCallback onReplay;
  final VoidCallback onPhraseAdd;

  const DualSubtitlesWidget({
    super.key,
    required this.englishLine,
    required this.russianLine,
    required this.showTranslation,
    required this.onWordTap,
    required this.onReplay,
    required this.onPhraseAdd,
  });

    @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final hasAnySub = englishLine != null || russianLine != null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 80),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: cs.outlineVariant.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // English subtitle with tappable words
                if (englishLine != null)
                  TappableSubtitleText(
                    line: englishLine!,
                    style: tt.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                      color: cs.onSurface,
                    ),
                    onWordTap: onWordTap,
                    accentColor: cs.primary,
                  )
                else
                  Text(
                    '♪  ...',
                    style: tt.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant.withOpacity(0.4),
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                // Russian translation
                if (showTranslation && hasAnySub) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _getTranslationText(),
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSecondaryContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Replay & Add Phrase buttons
          if (englishLine != null)
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: onReplay,
                  icon: const Icon(Icons.replay_rounded),
                  tooltip: 'Replay line',
                  style: IconButton.styleFrom(
                    backgroundColor: cs.primaryContainer.withOpacity(0.5),
                    foregroundColor: cs.primary,
                  ),
                ),
                const SizedBox(height: 8),
                IconButton(
                  onPressed: onPhraseAdd,
                  icon: const Icon(Icons.bookmark_add_outlined),
                  tooltip: 'Add Phrase',
                  style: IconButton.styleFrom(
                    backgroundColor: cs.tertiaryContainer.withOpacity(0.5),
                    foregroundColor: cs.tertiary,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _getTranslationText() {
    if (russianLine != null) return russianLine!.text;
    if (englishLine?.translation != null) return englishLine!.translation!;
    return '...';
  }

}

/// Renders subtitle text with individually tappable words.
///
/// Реализован через единый `Text.rich` с `TextSpan`-ами и
/// `TapGestureRecognizer`-ами вместо отдельных StatefulWidget на каждое слово.
/// Это даёт:
///   * 1 виджет на всю строку (вместо N виджетов на N слов);
///   * подсветка нажатого слова через `ValueListenableBuilder` —
///     перестраивается только сам RichText, а не родительское дерево;
///   * recognizers корректно освобождаются в `dispose()`.
class TappableSubtitleText extends StatefulWidget {
  final SubtitleLine line;
  final TextStyle style;
  final void Function(String word, SubtitleLine line) onWordTap;
  final Color accentColor;

  const TappableSubtitleText({
    super.key,
    required this.line,
    required this.style,
    required this.onWordTap,
    required this.accentColor,
  });

  @override
  State<TappableSubtitleText> createState() => _TappableSubtitleTextState();
}

class _TappableSubtitleTextState extends State<TappableSubtitleText> {
  // Регулярки в static final — компилируются один раз.
  static final RegExp _tokenRegex = RegExp(r"[\w']+|[^\w\s]+|\s+");
  static final RegExp _wordRegex = RegExp(r"^[\w']+$");

  // Индекс текущего "нажатого" слова (-1 если ничего не нажато).
  final ValueNotifier<int> _pressedIndex = ValueNotifier<int>(-1);

  // Кэш токенов и распознавателей жестов для текущей строки субтитров.
  List<String> _tokens = const [];
  List<bool> _isWordFlags = const [];
  List<TapGestureRecognizer?> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _rebuildTokens();
  }

  @override
  void didUpdateWidget(covariant TappableSubtitleText old) {
    super.didUpdateWidget(old);
    if (old.line.id != widget.line.id || old.line.text != widget.line.text) {
      _disposeRecognizers();
      _rebuildTokens();
      _pressedIndex.value = -1;
    }
  }

  void _rebuildTokens() {
    final raw = widget.line.text;
    final tokens = _tokenRegex.allMatches(raw).map((m) => m.group(0)!).toList();
    final flags = List<bool>.generate(
      tokens.length,
      (i) => _wordRegex.hasMatch(tokens[i]),
    );
    final recs = List<TapGestureRecognizer?>.generate(tokens.length, (i) {
      if (!flags[i]) return null;
      final rec = TapGestureRecognizer();
      rec.onTapDown = (_) {
        _pressedIndex.value = i;
      };
      rec.onTapUp = (_) {
        _pressedIndex.value = -1;
        widget.onWordTap(tokens[i], widget.line);
      };
      rec.onTapCancel = () {
        _pressedIndex.value = -1;
      };
      return rec;
    });
    _tokens = tokens;
    _isWordFlags = flags;
    _recognizers = recs;
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r?.dispose();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    _pressedIndex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _pressedIndex,
      builder: (context, pressed, _) {
        final pressedStyle = widget.style.copyWith(
          color: widget.accentColor,
          backgroundColor: widget.accentColor.withOpacity(0.15),
        );
        final spans = <TextSpan>[];
        for (int i = 0; i < _tokens.length; i++) {
          if (_isWordFlags[i]) {
            spans.add(TextSpan(
              text: _tokens[i],
              style: i == pressed ? pressedStyle : widget.style,
              recognizer: _recognizers[i],
            ));
          } else {
            spans.add(TextSpan(text: _tokens[i], style: widget.style));
          }
        }
        return Text.rich(TextSpan(children: spans));
      },
    );
  }
}
