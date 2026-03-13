import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/video_item.dart';
import '../../models/subtitle_line.dart';
import '../../providers/player_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/tts_service.dart';
import '../../services/stream_service.dart';
import '../../widgets/dual_subtitles_widget.dart';
import '../../widgets/word_tap_overlay.dart';

class PlayerScreen extends StatefulWidget {
  final VideoItem video;
  const PlayerScreen({super.key, required this.video});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {

  late final Player _player;
  late final VideoController _controller;
  final StreamService _streamService = StreamService();

  bool _loading = true;
  String? _error;
  bool _showSubList = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);

    _player.stream.position.listen((p) {
      if (mounted) context.read<PlayerProvider>().updatePosition(p);
    });
    _player.stream.playing.listen((v) {
      if (mounted) context.read<PlayerProvider>().setPlaying(v);
    });

    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    // Load subtitles (independent of video stream)
    context.read<PlayerProvider>().loadVideo(widget.video);

    // Get direct stream URL
    try {
      final url = await _streamService.getPlayableUrl(widget.video.youtubeId);
      await _player.open(Media(url));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pp = context.watch<PlayerProvider>();

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(widget.video.title,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          // Speed
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            onSelected: (s) {
              _player.setRate(s);
              pp.setPlaybackSpeed(s);
            },
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5]
                .map((s) => PopupMenuItem(
                value: s,
                child: Text('${s}x',
                    style: TextStyle(
                        fontWeight: pp.playbackSpeed == s
                            ? FontWeight.bold
                            : FontWeight.normal))))
                .toList(),
          ),
          // Language
          // if (pp.availableLanguages.isNotEmpty)
          //   PopupMenuButton<String>(
          //     icon: const Icon(Icons.translate_rounded),
          //     onSelected: (l) => pp.switchSubtitleLanguage(l),
          //     itemBuilder: (_) => pp.availableLanguages
          //         .map((i) => PopupMenuItem(
          //         value: i.languageCode,
          //         child: Text(
          //             '${i.language}${i.isGenerated ? " (auto)" : ""}')))
          //         .toList(),
          //   ),
          // Translation toggle
          IconButton(
            icon: Icon(pp.showTranslation
                ? Icons.subtitles_rounded
                : Icons.subtitles_off_rounded),
            onPressed: () => pp.toggleTranslation(),
          ),
          // Transcript list
          IconButton(
            icon: const Icon(Icons.list_rounded),
            onPressed: () => setState(() => _showSubList = !_showSubList),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Player ──
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(24)),
              child: _buildPlayer(),
            ),
          ),

          // ── Subtitles ──
          DualSubtitlesWidget(
            englishLine: pp.currentEnglishLine,
            russianLine: pp.currentRussianLine,
            showTranslation: pp.showTranslation,
            onWordTap: _onWordTap,
            onReplay: () {
              final l = pp.currentEnglishLine;
              if (l != null) _player.seek(Duration(milliseconds: l.startMs));
            },
          ).animate().fadeIn(),

          // ── Bottom ──
          Expanded(
            child: _showSubList ? _subList(pp) : _info(pp),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer() {
    if (_loading) {
      return Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }
    if (_error != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 32,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 12),
              Text('Failed to load video stream',
                  style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _openInYouTube(),
                    icon: const Icon(Icons.open_in_new),
                    label: const Text('Open in YouTube'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                  ),
                ],
              )


            ],
          ),
        ),
      );
    }
    return Video(controller: _controller, controls: MaterialVideoControls);
  }

  void _openInYouTube() async {
    final uri = Uri.parse(
        'https://www.youtube.com/watch?v=${widget.video.youtubeId}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }


  Widget _subList(PlayerProvider pp) {
    final cs = Theme.of(context).colorScheme;
    if (pp.isLoadingSubs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pp.englishSubs.isEmpty) {
      return Center(
          child: Text('No subtitles available',
              style: Theme.of(context).textTheme.titleMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: pp.englishSubs.length,
      itemBuilder: (ctx, i) {
        final line = pp.englishSubs[i];
        final isActive = line == pp.currentEnglishLine;
        final ruLine = i < pp.russianSubs.length ? pp.russianSubs[i] : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isActive ? cs.primaryContainer.withOpacity(0.5) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            dense: true,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Text(_fmt(line.startMs),
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.primary, fontWeight: FontWeight.w600)),
            title: Text(line.text,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight:
                    isActive ? FontWeight.w600 : FontWeight.normal)),
            subtitle: pp.showTranslation && (ruLine?.text ?? line.translation) != null
                ? Text(ruLine?.text ?? line.translation ?? '',
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
                : null,
            onTap: () =>
                _player.seek(Duration(milliseconds: line.startMs)),
          ),
        );
      },
    );
  }

  Widget _info(PlayerProvider pp) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.video.title,
              style: tt.titleLarge, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (widget.video.channelName != null) ...[
            const SizedBox(height: 4),
            Text(widget.video.channelName!,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Chip(Icons.signal_cellular_alt_rounded,
                widget.video.difficultyLabel, Color(widget.video.difficultyColorValue)),
            _Chip(Icons.timer_outlined, widget.video.formattedDuration, cs.secondary),
            _Chip(Icons.text_fields_rounded, '${pp.englishSubs.length} lines',
                cs.tertiary),
          ]),
          const Spacer(),
          // Controls
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(
              onPressed: () {
                final ms = pp.position.inMilliseconds - 5000;
                _player.seek(Duration(milliseconds: ms.clamp(0, 999999999)));
              },
              icon: const Icon(Icons.replay_5_rounded),
            ),
            const SizedBox(width: 16),
            IconButton.filled(
              onPressed: () => pp.isPlaying ? _player.pause() : _player.play(),
              icon: Icon(pp.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 32),
              style: IconButton.styleFrom(fixedSize: const Size(64, 64)),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              onPressed: () {
                final ms = pp.position.inMilliseconds + 5000;
                _player.seek(Duration(milliseconds: ms));
              },
              icon: const Icon(Icons.forward_5_rounded),
            ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.tertiaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(children: [
              Icon(Icons.lightbulb_outline_rounded, color: cs.tertiary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Tap any word in subtitles to translate and save it!',
                      style: tt.bodySmall?.copyWith(color: cs.onSurface))),
            ]),
          ),
        ],
      ),
    );
  }

  void _onWordTap(String word, SubtitleLine line) {
    _player.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => WordTapOverlay(
        word: word,
        contextSentence: line.text,
        contextVideoId: widget.video.id,
        contextTimestampMs: line.startMs,
        onAddToVocabulary: (w, t) {
          context.read<VocabularyProvider>().addWord(
              word: w,
              translation: t,
              contextSentence: line.text,
              contextVideoId: widget.video.id,
              contextTimestampMs: line.startMs);
          Navigator.pop(ctx);
          _player.play();
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('"$w" added!'), behavior: SnackBarBehavior.floating));
        },
        onSpeak: () => TtsService.speak(word),
      ),
    ).whenComplete(() => _player.play());
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  void _openInYouTubeApp() async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=${widget.video.youtubeId}');
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    _streamService.dispose();
    super.dispose();
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _Chip(this.icon, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
