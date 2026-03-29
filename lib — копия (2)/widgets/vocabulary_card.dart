import 'package:flutter/material.dart';
import '../models/word_card.dart';

class VocabularyCard extends StatelessWidget {
  final WordCard wordCard;
  final VoidCallback onSpeak;

  const VocabularyCard({
    super.key,
    required this.wordCard,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _statusColor(cs).withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  wordCard.statusEmoji,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Word info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          wordCard.word,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _statusColor(cs).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          wordCard.status,
                          style: tt.labelSmall?.copyWith(
                            color: _statusColor(cs),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (wordCard.translation != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      wordCard.translation!,
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (wordCard.contextSentence != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      wordCard.contextSentence!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant.withOpacity(0.7),
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // Speak & repetition info
            Column(
              children: [
                IconButton(
                  onPressed: onSpeak,
                  icon: Icon(Icons.volume_up_rounded, color: cs.primary),
                  visualDensity: VisualDensity.compact,
                ),
                Text(
                  'x${wordCard.repetitionCount}',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme cs) {
    switch (wordCard.status) {
      case 'new': return cs.tertiary;
      case 'learning': return cs.primary;
      case 'review': return cs.secondary;
      case 'mastered': return Colors.green;
      default: return cs.outline;
    }
  }
}
