import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/video_item.dart';
import '../../models/subtitle_line.dart';
import '../../providers/player_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/stream_service.dart';
import '../../services/supabase_service.dart';
import '../../services/tts_service.dart';
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
  late final VideoController _videoController;
  final StreamService _streamService = StreamService();

  bool _loading = true;
  String? _error;
  bool _showSubList = false;
  
  final Stopwatch _watchStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    // Слушаем позицию для синхронизации субтитров
    _player.stream.position.listen((pos) {
      if (mounted) {
        context.read<PlayerProvider>().updatePosition(pos);
      }
    });

    // Слушаем состояние воспроизведения
    _player.stream.playing.listen((playing) {
      if (mounted) {
        if (playing) {
          _watchStopwatch.start();
        } else {
          _watchStopwatch.stop();
        }
        context.read<PlayerProvider>().setPlaying(playing);
      }
    });

    // Слушаем ошибки плеера
    _player.stream.error.listen((error) {
      debugPrint('[Player] Error: $error');
      if (mounted && error.isNotEmpty) {
        setState(() {
          _error = 'Playback error: $error';
        });
      }
    });

    // Используем addPostFrameCallback чтобы избежать setState during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    // Загружаем субтитры в фоне
    if (mounted) {
      context.read<PlayerProvider>().loadVideo(widget.video);
    }

    // Получаем URL потока через youtube_explode_dart
    try {
      debugPrint(
          '[Player] Getting stream URL for ${widget.video.youtubeId}...');
      final url =
          await _streamService.getPlayableUrl(widget.video.youtubeId);
      debugPrint('[Player] Got stream URL, opening media...');

      await _player.open(Media(url), play: true);
      debugPrint('[Player] Media opened successfully');

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[Player] Error loading video: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  void _openInYouTube() async {
    final url = Uri.parse(
        'https://www.youtube.com/watch?v=${widget.video.youtubeId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showProxyDialog() {
    final controller = TextEditingController();
    StreamService.getProxy().then((current) {
      controller.text = current ?? '';
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proxy Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter HTTP proxy address to bypass YouTube restrictions.\n'
              'Format: host:port (e.g. 192.168.1.1:8080)',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Proxy address',
                hintText: 'host:port',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
              keyboardType: TextInputType.url,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await StreamService.setProxy(null);
              await _streamService.recreateClient();
              if (ctx.mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Proxy disabled')),
              );
            },
            child: const Text('Clear'),
          ),
          FilledButton(
            onPressed: () async {
              final proxy = controller.text.trim();
              await StreamService.setProxy(proxy.isEmpty ? null : proxy);
              await _streamService.recreateClient();
              if (ctx.mounted) Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(proxy.isEmpty
                        ? 'Proxy disabled'
                        : 'Proxy set: $proxy')),
              );
              // Переповторить загрузку с новым прокси
              _load();
            },
            child: const Text('Save & Retry'),
          ),
        ],
      ),
    );
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
              pp.setPlaybackSpeed(s);
              _player.setRate(s);
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
          // Proxy settings
          IconButton(
            icon: const Icon(Icons.vpn_key_rounded),
            tooltip: 'Proxy',
            onPressed: _showProxyDialog,
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
              child: _buildPlayer(pp),
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
              if (l != null) {
                _player.seek(Duration(milliseconds: l.startMs));
              }
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

  Widget _buildPlayer(PlayerProvider pp) {
    if (_loading) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 12),
              Text('Loading video...',
                  style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style:
                    const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _showProxyDialog,
                    icon: const Icon(Icons.vpn_key, size: 18),
                    label: const Text('Proxy'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _openInYouTube,
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: const Text('YouTube'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // media_kit Video виджет
    return Video(controller: _videoController);
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
        final ruLine =
            i < pp.russianSubs.length ? pp.russianSubs[i] : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color:
                isActive ? cs.primaryContainer.withOpacity(0.5) : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListTile(
            dense: true,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            leading: Text(_fmt(line.startMs),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: cs.primary, fontWeight: FontWeight.w600)),
            title: Text(line.text,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal)),
            subtitle: pp.showTranslation &&
                    (ruLine?.text ?? line.translation) != null
                ? Text(ruLine?.text ?? line.translation ?? '',
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant))
                : null,
            onTap: () {
              _player.seek(Duration(milliseconds: line.startMs));
            },
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
              style: tt.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          if (widget.video.channelName != null) ...[
            const SizedBox(height: 4),
            Text(widget.video.channelName!,
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ],
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _Chip(
                Icons.signal_cellular_alt_rounded,
                widget.video.difficultyLabel,
                Color(widget.video.difficultyColorValue)),
            _Chip(Icons.timer_outlined,
                widget.video.formattedDuration, cs.secondary),
            _Chip(Icons.text_fields_rounded,
                '${pp.englishSubs.length} lines', cs.tertiary),
          ]),
          const Spacer(),
          // Controls
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton.filledTonal(
              onPressed: () {
                final pos = _player.state.position;
                final target = pos - const Duration(seconds: 5);
                _player
                    .seek(target > Duration.zero ? target : Duration.zero);
              },
              icon: const Icon(Icons.replay_5_rounded),
            ),
            const SizedBox(width: 16),
            IconButton.filled(
              onPressed: () {
                _player.playOrPause();
              },
              icon: Icon(
                  pp.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  size: 32),
              style:
                  IconButton.styleFrom(fixedSize: const Size(64, 64)),
            ),
            const SizedBox(width: 16),
            IconButton.filledTonal(
              onPressed: () {
                final pos = _player.state.position;
                _player.seek(pos + const Duration(seconds: 5));
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
              Icon(Icons.lightbulb_outline_rounded,
                  color: cs.tertiary),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      'Tap any word in subtitles to translate and save it!',
                      style: tt.bodySmall
                          ?.copyWith(color: cs.onSurface))),
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
        onAddToVocabulary: (w, t) async {
          try {
            await context.read<VocabularyProvider>().addWord(
                word: w,
                translation: t,
                contextSentence: line.text,
                contextVideoId: widget.video.id,
                contextTimestampMs: line.startMs);
            if (ctx.mounted) Navigator.pop(ctx);
            _player.play();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('"$w" added!'),
                  behavior: SnackBarBehavior.floating));
            }
          } catch (e) {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Failed to add "$w": $e'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  behavior: SnackBarBehavior.floating));
             }
          }
        },
        onSpeak: () => TtsService.speak(word),
      ),
    ).whenComplete(() => _player.play());
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    return '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _watchStopwatch.stop();
    final durationSec = _watchStopwatch.elapsed.inSeconds;
    final posMs = _player.state.position.inMilliseconds;
    if (durationSec > 10) { // Only log if watched for more than 10 seconds
      SupabaseService.updateWatchProgress(widget.video.id, posMs, durationSec).catchError((_) {});
    }

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
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12)),
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
