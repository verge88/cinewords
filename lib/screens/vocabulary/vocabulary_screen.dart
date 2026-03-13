import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../models/word_card.dart';
import '../../services/tts_service.dart';
import '../../widgets/vocabulary_card.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isReviewMode = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final vocab = context.watch<VocabularyProvider>();

    if (_isReviewMode) {
      return _buildReviewMode(vocab);
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar.medium(
            title: Text('Vocabulary', style: tt.headlineMedium),
            actions: [
              if (vocab.reviewQueue.isNotEmpty || vocab.allWords.any((w) => w.status != 'mastered'))
                FilledButton.icon(
                  onPressed: () {
                    vocab.preparePractice();
                    setState(() => _isReviewMode = true);
                  },
                  icon: const Icon(Icons.school_rounded, size: 18),
                  label: Text(vocab.reviewQueue.isNotEmpty 
                      ? 'Review (${vocab.reviewQueue.length})' 
                      : 'Practice'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                ),
              const SizedBox(width: 12),
            ],
          ),

          // Stats bar
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  _StatBadge('New', vocab.newCount, cs.tertiary),
                  const SizedBox(width: 8),
                  _StatBadge('Learning', vocab.learningCount, cs.primary),
                  const SizedBox(width: 8),
                  _StatBadge('Review', vocab.reviewCount, cs.secondary),
                  const SizedBox(width: 8),
                  _StatBadge('Mastered', vocab.masteredCount, Colors.green),
                ],
              ),
            ).animate().fadeIn(),
          ),

          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(
              TabBar(
                controller: _tabController,
                tabs: const [
                  Tab(text: 'All'),
                  Tab(text: 'New'),
                  Tab(text: 'Learning'),
                  Tab(text: 'Mastered'),
                ],
                isScrollable: true,
                tabAlignment: TabAlignment.start,
              ),
              cs.surface,
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildWordList(vocab.allWords, vocab),
            _buildWordList(
                vocab.allWords.where((w) => w.status == 'new').toList(), vocab),
            _buildWordList(
                vocab.allWords
                    .where((w) => w.status == 'learning' || w.status == 'review')
                    .toList(),
                vocab),
            _buildWordList(
                vocab.allWords.where((w) => w.status == 'mastered').toList(), vocab),
          ],
        ),
      ),
    );
  }

  Widget _buildWordList(List<WordCard> words, VocabularyProvider vocab) {
    if (vocab.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (words.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.book_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No words yet',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Tap words in video subtitles to add them!',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: words.length,
      itemBuilder: (context, index) {
        final word = words[index];
        return Dismissible(
          key: Key(word.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) => vocab.deleteWord(word.id),
          child: VocabularyCard(
            wordCard: word,
            onSpeak: () => TtsService.speak(word.word),
          ).animate(delay: (index * 50).ms).fadeIn().slideX(begin: 0.03),
        );
      },
    );
  }

  // ─── REVIEW MODE (Flashcards) ───
  Widget _buildReviewMode(VocabularyProvider vocab) {
    final card = vocab.currentReviewCard;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => setState(() => _isReviewMode = false),
        ),
        title: Text(
          '${vocab.currentReviewIndex + 1} / ${vocab.reviewQueue.length}',
        ),
      ),
      body: card == null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 80, color: Colors.green),
                  const SizedBox(height: 16),
                  Text('All done!', style: tt.headlineSmall),
                  const SizedBox(height: 8),
                  Text('Great job! Come back later for more reviews.'),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => setState(() => _isReviewMode = false),
                    child: const Text('Back to Vocabulary'),
                  ),
                ],
              ),
            )
          : _ReviewCard(
              card: card,
              onRate: (quality) => vocab.reviewCurrentWord(quality),
            ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
}

class _StatBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatBadge(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color.withOpacity(0.8),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bgColor;

  _TabBarDelegate(this.tabBar, this.bgColor);

  @override
  Widget build(context, shrinkOffset, overlapsContent) =>
      Container(color: bgColor, child: tabBar);

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => false;
}

// ─── Flashcard Review Widget ───
class _ReviewCard extends StatefulWidget {
  final WordCard card;
  final void Function(int quality) onRate;

  const _ReviewCard({required this.card, required this.onRate});

  @override
  State<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends State<_ReviewCard> {
  bool _showAnswer = false;

  @override
  void didUpdateWidget(covariant _ReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _showAnswer = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final card = widget.card;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Spacer(),
          // Word
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Text(
                  card.word,
                  style: tt.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                if (card.phonetic != null) ...[
                  const SizedBox(height: 8),
                  Text(card.phonetic!,
                      style: tt.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
                ],
                const SizedBox(height: 16),

                // Context sentence
                if (card.contextSentence != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      card.contextSentence!,
                      style: tt.bodyMedium?.copyWith(
                          fontStyle: FontStyle.italic,
                          color: cs.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const SizedBox(height: 24),

                     // Answer (продолжение)
                if (_showAnswer)
                  Text(
                    card.translation ?? '—',
                    style: tt.headlineSmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ).animate().fadeIn().slideY(begin: 0.2)
                else
                  FilledButton.tonal(
                    onPressed: () => setState(() => _showAnswer = true),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(200, 48),
                    ),
                    child: const Text('Show Answer'),
                  ),
              ],
            ),
          ).animate().scale(begin: const Offset(0.95, 0.95), duration: 300.ms, curve: Curves.easeOut),

          const Spacer(),

          // Rating buttons (SM-2 quality 0-5)
          if (_showAnswer) ...[
            Text('How well did you remember?',
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Row(
              children: [
                _RateButton(
                  label: 'Again',
                  subtitle: '< 1m',
                  color: cs.error,
                  onTap: () => widget.onRate(0),
                ),
                const SizedBox(width: 8),
                _RateButton(
                  label: 'Hard',
                  subtitle: '1d',
                  color: cs.tertiary,
                  onTap: () => widget.onRate(2),
                ),
                const SizedBox(width: 8),
                _RateButton(
                  label: 'Good',
                  subtitle: '${card.intervalDays}d',
                  color: cs.primary,
                  onTap: () => widget.onRate(4),
                ),
                const SizedBox(width: 8),
                _RateButton(
                  label: 'Easy',
                  subtitle: '${(card.intervalDays * card.easeFactor).round()}d',
                  color: Colors.green,
                  onTap: () => widget.onRate(5),
                ),
              ],
            ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),
          ],

          const SizedBox(height: 24),

          // Speak button
          IconButton.filledTonal(
            onPressed: () => TtsService.speak(card.word),
            icon: const Icon(Icons.volume_up_rounded),
            iconSize: 28,
            tooltip: 'Listen',
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _RateButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _RateButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: color.withOpacity(0.7),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
