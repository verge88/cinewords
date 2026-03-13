import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/subtitle_line.dart';

class DualSubtitlesWidget extends StatelessWidget {
  final SubtitleLine? englishLine;
  final SubtitleLine? russianLine;
  final bool showTranslation;
  final void Function(String word, SubtitleLine line) onWordTap;
  final VoidCallback onReplay;

  const DualSubtitlesWidget({
    super.key,
    required this.englishLine,
    required this.russianLine,
    required this.showTranslation,
    required this.onWordTap,
    required this.onReplay,
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
                  _TappableSubtitleText(
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

          // Replay button
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

/// Renders subtitle text with individually tappable words
class _TappableSubtitleText extends StatelessWidget {
  final SubtitleLine line;
  final TextStyle style;
  final void Function(String word, SubtitleLine line) onWordTap;
  final Color accentColor;

  const _TappableSubtitleText({
    required this.line,
    required this.style,
    required this.onWordTap,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    // Split into words while preserving spacing/punctuation for display
    final rawText = line.text;
    final wordRegex = RegExp(r"[\w']+|[^\w\s]+|\s+");
    final tokens = wordRegex.allMatches(rawText).map((m) => m.group(0)!).toList();

    return Wrap(
      children: tokens.map((token) {
        final isWord = RegExp(r"^[\w']+$").hasMatch(token);

        if (!isWord) {
          return Text(token, style: style);
        }

        return _HoverWord(
          word: token,
          style: style,
          accentColor: accentColor,
          onTap: () => onWordTap(token, line),
        );
      }).toList(),
    );
  }
}

class _HoverWord extends StatefulWidget {
  final String word;
  final TextStyle style;
  final Color accentColor;
  final VoidCallback onTap;

  const _HoverWord({
    required this.word,
    required this.style,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_HoverWord> createState() => _HoverWordState();
}

class _HoverWordState extends State<_HoverWord> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        decoration: BoxDecoration(
          color: _isPressed
              ? widget.accentColor.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: _isPressed
              ? Border(
                  bottom: BorderSide(
                    color: widget.accentColor,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Text(
          widget.word,
          style: widget.style.copyWith(
            color: _isPressed ? widget.accentColor : null,
          ),
        ),
      ),
    );
  }
}
