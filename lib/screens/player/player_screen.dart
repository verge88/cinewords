import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../models/video_item.dart';
import '../../models/subtitle_line.dart';
import '../../providers/player_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/tts_service.dart';
import '../../widgets/dual_subtitles_widget.dart';
import '../../widgets/word_tap_overlay.dart';
import '../../widgets/youtube_player_widget.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;

  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final GlobalKey<YouTubePlayerWidgetState> _playerKey = GlobalKey();
  bool _showSubtitleList = false;

    @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Give the provider access to our WebView for subtitle fetching
      context.read<PlayerProvider>().setPlayerKey(_playerKey);
      context.read<PlayerProvider>().loadVideo(widget.video);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final playerProvider = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // Playback speed
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            tooltip: 'Playback speed',
            onSelected: (speed) {
              _playerKey.currentState?.setPlaybackRate(speed);
              playerProvider.setPlaybackSpeed(speed);
            },
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5]
                .map((s) => PopupMenuItem(
                      value: s,
                      child: Text(
                        '${s}x',
                        style: TextStyle(
                          fontWeight: playerProvider.playbackSpeed == s
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ))
                .toList(),
          ),
          // Toggle translation
          IconButton(
            icon: Icon(
              playerProvider.showTranslation
                  ? Icons.subtitles_rounded
                  : Icons.subtitles_off_rounded,
            ),
            tooltip: 'Toggle translation',
            onPressed: () => playerProvider.toggleTranslation(),
          ),
          // Subtitle list
          IconButton(
            icon: const Icon(Icons.list_rounded),
            tooltip: 'All subtitles',
            onPressed: () =>
                setState(() => _showSubtitleList = !_showSubtitleList),
          ),
        ],
      ),
      body: Column(
        children: [
          // ─── Video Player ───
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: YouTubePlayerWidget(
                key: _playerKey,
                videoId: widget.video.youtubeId,
                autoPlay: true,
                playbackRate: playerProvider.playbackSpeed,
                onPositionChanged: (pos) {
                  playerProvider.updatePosition(pos);
                },
                onPlayingChanged: (isPlaying) {
                  playerProvider.setPlaying(isPlaying);
                },
              ),
            ),
          ),

          // ─── Current Subtitles (Parallel) ───
          DualSubtitlesWidget(
            englishLine: playerProvider.currentEnglishLine,
            russianLine: playerProvider.currentRussianLine,
            showTranslation: playerProvider.showTranslation,
            onWordTap: (word, line) => _onWordTap(word, line),
            onReplay: () {
              final line = playerProvider.currentEnglishLine;
              if (line != null) {
                _playerKey.currentState?.seekTo(line.startMs / 1000.0);
              }
            },
          ).animate().fadeIn(),

                    // ─── Current Subtitles (Parallel) ───
          DualSubtitlesWidget(
            englishLine: playerProvider.currentEnglishLine,
            russianLine: playerProvider.currentRussianLine,
            showTranslation: playerProvider.showTranslation,
            onWordTap: (word, line) => _onWordTap(word, line),
            onReplay: () {
              final line = playerProvider.currentEnglishLine;
              if (line != null) {
                _playerKey.currentState?.seekTo(line.startMs / 1000.0);
              }
            },
          ).animate().fadeIn(),

          // ─── Loading / Error / Count indicator ───
          if (playerProvider.isLoadingSubs)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Loading subtitles...',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          else if (playerProvider.subtitleError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                playerProvider.subtitleError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            )
          else if (playerProvider.englishSubs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Text(
                '${playerProvider.englishSubs.length} subtitle lines loaded',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(0.6),
                ),
              ),
            ),


          // ─── Subtitle List / Transcript ───
          if (_showSubtitleList)
            Expanded(child: _buildSubtitleList(playerProvider))
          else
            Expanded(child: _buildBottomActions(playerProvider)),
        ],
      ),
    );
  }

  Widget _buildSubtitleList(PlayerProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final subs = provider.englishSubs;
    final ruSubs = provider.russianSubs;

    if (provider.isLoadingSubs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (subs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subtitles_off, size: 48, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('No subtitles available',
                style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: subs.length,
      itemBuilder: (context, index) {
        final line = subs[index];
        final isActive = line == provider.currentEnglishLine;
        final ruLine = index < ruSubs.length ? ruSubs[index] : null;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isActive
                ? cs.primaryContainer.withOpacity(0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Text(
              _formatMs(line.startMs),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            title: Text(
              line.text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
            ),
            subtitle: provider.showTranslation &&
                    (ruLine?.text ?? line.translation) != null
                ? Text(
                    ruLine?.text ?? line.translation ?? '',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                  )
                : null,
            onTap: () {
              _playerKey.currentState?.seekTo(line.startMs / 1000.0);
            },
          ),
        );
      },
    );
  }

  Widget _buildBottomActions(PlayerProvider provider) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.video.title,
              style: tt.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (widget.video.channelName != null) ...[
            const SizedBox(height: 4),
            Text(widget.video.channelName!,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),

          // Difficulty & stats
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _InfoChip(
                icon: Icons.signal_cellular_alt_rounded,
                label: widget.video.difficultyLabel,
                color: Color(widget.video.difficultyColorValue),
              ),
              _InfoChip(
                icon: Icons.timer_outlined,
                label: widget.video.formattedDuration,
                color: cs.secondary,
              ),
              _InfoChip(
                icon: Icons.text_fields_rounded,
                label: '${provider.englishSubs.length} lines',
                color: cs.tertiary,
              ),
            ],
          ),

          const Spacer(),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline_rounded, color: cs.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tap any word in the subtitles to see its translation and add it to your vocabulary!',
                    style: tt.bodySmall?.copyWith(color: cs.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onWordTap(String word, SubtitleLine line) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => WordTapOverlay(
        word: word,
        contextSentence: line.text,
        contextVideoId: widget.video.id,
        contextTimestampMs: line.startMs,
        onAddToVocabulary: (word, translation) {
          context.read<VocabularyProvider>().addWord(
                word: word,
                translation: translation,
                contextSentence: line.text,
                contextVideoId: widget.video.id,
                contextTimestampMs: line.startMs,
              );
          Navigator.pop(ctx);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$word" added to vocabulary!'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        onSpeak: () => TtsService.speak(word),
      ),
    );
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
