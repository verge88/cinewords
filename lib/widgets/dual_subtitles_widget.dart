import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/subtitle_line.dart';

/// Панель текущей реплики. Растянута на всю ширину плеера: боковые отступы
/// убраны, скругления заменены разделителями сверху и снизу, чтобы панель
/// читалась как продолжение видео, а не как отдельная карточка.
/// Кнопки повтора реплики и добавления фразы живут в нижней таблетке.
class DualSubtitlesWidget extends StatelessWidget {
  final SubtitleLine? englishLine;
  final SubtitleLine? russianLine;
  final bool showTranslation;
  final void Function(String word, SubtitleLine line) onWordTap;

  const DualSubtitlesWidget({
    super.key,
    required this.englishLine,
    required this.russianLine,
    required this.showTranslation,
    required this.onWordTap,
  });

  String get _translation {
    if (russianLine != null) return russianLine!.text;
    return englishLine?.translation ?? '...';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final hasAnySub = englishLine != null || russianLine != null;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (englishLine != null)
            TappableSubtitleText(
              line: englishLine!,
              style: tt.bodyLarge!.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.45,
                color: cs.onSurface,
              ),
              onWordTap: onWordTap,
              accentColor: cs.primary,
            )
          else
            Text(
              '♪  ...',
              style: tt.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          if (showTranslation && hasAnySub) ...[
            const SizedBox(height: 8),
            Text(
              _translation,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders subtitle text with individually tappable words.
///
/// Реализован через единый `Text.rich` с `TextSpan`-ами и
/// `TapGestureRecognizer`-ами вместо отдельных StatefulWidget на каждое слово.
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
  static final RegExp _tokenRegex = RegExp(r"[\w']+|[^\w\s]+|\s+");
  static final RegExp _wordRegex = RegExp(r"^[\w']+$");

  final ValueNotifier<int> _pressedIndex = ValueNotifier<int>(-1);

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
      rec.onTapDown = (_) => _pressedIndex.value = i;
      rec.onTapUp = (_) {
        _pressedIndex.value = -1;
        widget.onWordTap(tokens[i], widget.line);
      };
      rec.onTapCancel = () => _pressedIndex.value = -1;
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
          backgroundColor: widget.accentColor.withValues(alpha: 0.15),
        );
        final spans = <TextSpan>[
          for (int i = 0; i < _tokens.length; i++)
            if (_isWordFlags[i])
              TextSpan(
                text: _tokens[i],
                style: i == pressed ? pressedStyle : widget.style,
                recognizer: _recognizers[i],
              )
            else
              TextSpan(text: _tokens[i], style: widget.style),
        ];
        return Text.rich(TextSpan(children: spans));
      },
    );
  }
}
