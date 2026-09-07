import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/exercise_data.dart';
import '../../services/tts_service.dart';
import '../../widgets/word_tap_overlay.dart';

/// RichText + TapGestureRecognizer на каждом слове.
/// Tap → bottom sheet с определением (через Wiktionary/перевод) и кнопкой
/// "Добавить в словарь" (использует существующий VocabularyProvider).
class TapReaderScreen extends StatefulWidget {
  const TapReaderScreen({super.key});

  @override
  State<TapReaderScreen> createState() => _TapReaderScreenState();
}

class _TapReaderScreenState extends State<TapReaderScreen> {
  int _index = 0;
  final Set<String> _added = {};

  ReaderText get _text => ExerciseData.readerTexts[_index];

  void _next() {
    setState(() {
      _index = (_index + 1) % ExerciseData.readerTexts.length;
    });
  }

  void _onWordTap(String word) {
    final clean = word.replaceAll(RegExp(r"[^A-Za-z'\-]"), '');
    if (clean.isEmpty) return;

    final sentence = _findSentence(_text.body, word);
    final vocab = context.read<VocabularyProvider>();
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => WordTapOverlay(
        word: clean,
        contextSentence: sentence,
        onSpeak: () => TtsService.speak(clean),
        onAddToVocabulary: (w, tr, ph) async {
          await vocab.addWord(
            word: w,
            translation: tr,
            phonetic: ph,
            contextSentence: sentence,
          );
          if (!mounted) return;
          setState(() => _added.add(clean.toLowerCase()));
          if (Navigator.canPop(ctx)) Navigator.of(ctx).pop();
          messenger.showSnackBar(
            SnackBar(content: Text('"$w" добавлено в словарь')),
          );
        },
      ),
    );
  }

  String _findSentence(String body, String word) {
    final sentences = body.split(RegExp(r'(?<=[.!?])\s+'));
    final lw = word.toLowerCase();
    for (final s in sentences) {
      if (s.toLowerCase().contains(lw)) return s;
    }
    return body;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final tokens = _tokenize(_text.body);

    return Scaffold(
      appBar: AppBar(
        title: Text(_text.title),
        actions: [
          IconButton(
            tooltip: 'Следующий текст',
            onPressed: _next,
            icon: const Icon(Icons.skip_next_rounded),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.tertiaryContainer.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.touch_app_rounded,
                      color: cs.onTertiaryContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Тапните любое слово, чтобы увидеть определение и добавить его в SRS.',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onTertiaryContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                children: tokens.map((tok) {
                  if (tok.isWord) {
                    final added = _added.contains(tok.text.toLowerCase());
                    return WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: GestureDetector(
                        onTap: () => _onWordTap(tok.text),
                        onLongPress: () => TtsService.speak(tok.text),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: added
                                ? cs.primary.withOpacity(0.15)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tok.text,
                            style: tt.titleMedium?.copyWith(
                              height: 1.65,
                              fontWeight: FontWeight.w500,
                              color: added ? cs.primary : cs.onSurface,
                              decoration:
                                  added ? TextDecoration.underline : null,
                              decorationColor: cs.primary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }
                  return TextSpan(
                    text: tok.text,
                    style: tt.titleMedium?.copyWith(height: 1.65),
                  );
                }).toList(),
              ),
            ).animate(key: ValueKey(_text.title)).fadeIn(),
          ],
        ),
      ),
    );
  }
}

class _Token {
  final String text;
  final bool isWord;
  _Token(this.text, this.isWord);
}

List<_Token> _tokenize(String body) {
  // Split into words and non-words while preserving punctuation/whitespace.
  final out = <_Token>[];
  final regex = RegExp(r"[A-Za-z][A-Za-z'\-]*|[^A-Za-z]+");
  for (final m in regex.allMatches(body)) {
    final s = m.group(0)!;
    final isWord = RegExp(r'^[A-Za-z]').hasMatch(s);
    out.add(_Token(s, isWord));
  }
  return out;
}
