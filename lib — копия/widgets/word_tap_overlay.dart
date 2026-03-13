import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

class WordTapOverlay extends StatefulWidget {
  final String word;
  final String? contextSentence;
  final String? contextVideoId;
  final int? contextTimestampMs;
  final void Function(String word, String? translation) onAddToVocabulary;
  final VoidCallback onSpeak;

  const WordTapOverlay({
    super.key,
    required this.word,
    this.contextSentence,
    this.contextVideoId,
    this.contextTimestampMs,
    required this.onAddToVocabulary,
    required this.onSpeak,
  });

  @override
  State<WordTapOverlay> createState() => _WordTapOverlayState();
}

class _WordTapOverlayState extends State<WordTapOverlay> {
  String? _translation;
  bool _isLoadingTranslation = true;
  final _translationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTranslation();
  }

  Future<void> _loadTranslation() async {
    // Simple dictionary lookup — in production, use a proper
    // translation API (Google Translate, DeepL, etc.)
    // For now we use a placeholder approach
    try {
      // You could integrate `translator` package here:
      // final translator = GoogleTranslator();
      // final result = await translator.translate(widget.word, from: 'en', to: 'ru');
      // _translation = result.text;

      // Placeholder: show a prompt for manual translation
      await Future.delayed(const Duration(milliseconds: 500));
      _translation = null; // Will ask user to type
    } catch (e) {
      _translation = null;
    }

    if (mounted) {
      setState(() => _isLoadingTranslation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Word header
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.word,
                  style: tt.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
              ),
              // Speak button
              IconButton.filledTonal(
                onPressed: widget.onSpeak,
                icon: const Icon(Icons.volume_up_rounded),
              ),
            ],
          ).animate().fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 8),

          // Context sentence
          if (widget.contextSentence != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(16),
              ),
              child: RichText(
                text: TextSpan(
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                  children: _highlightWord(
                    widget.contextSentence!,
                    widget.word,
                    cs,
                    tt,
                  ),
                ),
              ),
            ).animate(delay: 100.ms).fadeIn(),

          const SizedBox(height: 16),

          // Translation field
          if (_isLoadingTranslation)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text('Translation',
                style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),

            if (_translation != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _translation!,
                  style: tt.bodyLarge?.copyWith(
                    color: cs.onSecondaryContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              TextField(
                controller: _translationController,
                decoration: InputDecoration(
                  hintText: 'Enter translation...',
                  prefixIcon: Icon(Icons.translate, color: cs.primary),
                ),
                autofocus: true,
              ),
          ],

          const SizedBox(height: 20),

          // Add to vocabulary button
          FilledButton.icon(
            onPressed: () {
              final translation =
                  _translation ?? _translationController.text.trim();
              widget.onAddToVocabulary(
                widget.word,
                translation.isNotEmpty ? translation : null,
              );
            },
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add to Vocabulary'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 52),
            ),
          ).animate(delay: 200.ms).fadeIn().slideY(begin: 0.1),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// Highlights the tapped word in the context sentence
  List<TextSpan> _highlightWord(
    String sentence,
    String word,
    ColorScheme cs,
    TextTheme tt,
  ) {
    final spans = <TextSpan>[];
    final lower = sentence.toLowerCase();
    final wordLower = word.toLowerCase();
    int start = 0;

    while (true) {
      final idx = lower.indexOf(wordLower, start);
      if (idx == -1) {
        spans.add(TextSpan(text: sentence.substring(start)));
        break;
      }

      if (idx > start) {
        spans.add(TextSpan(text: sentence.substring(start, idx)));
      }

      spans.add(TextSpan(
        text: sentence.substring(idx, idx + word.length),
        style: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
          backgroundColor: cs.primary.withOpacity(0.1),
        ),
      ));

      start = idx + word.length;
    }

    return spans;
  }

  @override
  void dispose() {
    _translationController.dispose();
    super.dispose();
  }
}
