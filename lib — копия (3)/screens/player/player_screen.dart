import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../providers/video_provider.dart';
import '../../models/video_item.dart';
import '../../models/subtitle_line.dart';
import '../../providers/player_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/stream_service.dart';
import '../../services/supabase_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/dual_subtitles_widget.dart';
import '../../widgets/word_tap_overlay.dart';
import '../../widgets/player/custom_video_controls.dart';
import '../../widgets/player/player_settings_sheet.dart';
import '../../services/movie_stream_service.dart';
import '../../services/movie_providers/provider_base.dart';

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
  bool _isExtracting = false;

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

    try {
      String url;
      Map<String, String>? headers;
      VideoItem effectiveVideo = widget.video;

      if (widget.video.sourceType == 'vidapi') {
        debugPrint('[Player] Resolving stream via MovieStreamService...');
        if (mounted) setState(() => _isExtracting = true);

        final tmdbId = int.tryParse(widget.video.youtubeId);
        if (tmdbId == null) {
          throw Exception('У фильма отсутствует TMDB id');
        }
        final stream = await MovieStreamService.fetchStream(
          tmdbId: tmdbId,
          imdbId: widget.video.imdbId,
        );
        if (!mounted) return;
        setState(() => _isExtracting = false);
        if (stream == null) {
          throw Exception(
              'Не удалось получить поток фильма. Возможно, он не доступен у Rivestream-провайдеров.');
        }
        url = stream.url;
        headers = stream.headers;

        if (mounted) {
          context.read<PlayerProvider>().setAvailableQualities(
                stream.qualities.isEmpty
                    ? ['Auto']
                    : stream.qualities.map((q) => q.quality).toList(),
              );
        }

        // Подмешиваем найденные провайдером субтитры в VideoItem.
        // Если их нет — PlayerProvider всё равно сходит в OpenSubtitles по TMDB id.
        final enSub = stream.subtitleFor('en');
        final ruSub = stream.subtitleFor('ru');
        effectiveVideo = widget.video.copyWith(
          subtitleUrl: enSub?.url,
          subtitleUrlRu: ruSub?.url,
        );
      } else if (widget.video.sourceType == 'direct' && widget.video.videoUrl != null) {
        debugPrint('[Player] Using direct stream URL...');
        url = widget.video.videoUrl!;
        if (mounted) context.read<PlayerProvider>().setAvailableQualities(['Auto']);
      } else {
        debugPrint('[Player] Getting stream URL for ${widget.video.youtubeId}...');

        final qualities = await _streamService.getAvailableQualities(widget.video.youtubeId);
        if (mounted) context.read<PlayerProvider>().setAvailableQualities(qualities);

        url = await _streamService.getPlayableUrl(widget.video.youtubeId);
      }

      // Загружаем субтитры (теперь уже зная URL, если их вернул провайдер)
      if (mounted) {
        context.read<PlayerProvider>().loadVideo(effectiveVideo);
      }

      debugPrint('[Player] Got stream URL, opening media...');

      await _player.open(Media(url, httpHeaders: headers), play: true);
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

  Future<void> _changeQuality(String? newQuality) async {
    if (!mounted) return;
    if (newQuality == context.read<PlayerProvider>().selectedQuality) return;
    
    context.read<PlayerProvider>().setSelectedQuality(newQuality);
    
    final pos = _player.state.position;
    final wasPlaying = _player.state.playing;
    
    try {
      String url;
      if (widget.video.sourceType == 'vidapi') {
        return; 
      } else if (widget.video.sourceType == 'direct' && widget.video.videoUrl != null) {
        url = widget.video.videoUrl!;
      } else {
        url = await _streamService.getPlayableUrl(widget.video.youtubeId, quality: newQuality);
      }
      await _player.open(Media(url), play: false);
      await _player.seek(pos);
      if (wasPlaying) {
        _player.play();
      }
    } catch (e) {
      debugPrint('[Player] Error changing quality: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to change quality: $e')));
      }
    }
  }

  void _showNewSettingsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => PlayerSettingsSheet(
        onQualityChanged: _changeQuality,
      ),
    );
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
          // Favorite toggle
          Consumer<VideoProvider>(
            builder: (context, vProvider, _) {
              final isFav = vProvider.isFavorite(widget.video.id);
              return IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_outline_rounded,
                  color: isFav ? Colors.red : null,
                ),
                onPressed: () => vProvider.toggleFavorite(widget.video),
                tooltip: 'Favorite',
              );
            },
          ),
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
      body: Stack(
        children: [
          Column(
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
              if (pp.isAutoTranslating)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  color: cs.tertiaryContainer,
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: cs.onTertiaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Auto-translating subtitles...',
                        style: TextStyle(
                          color: cs.onTertiaryContainer,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ).animate().fadeIn().slideY(),

              DualSubtitlesWidget(
                englishLine: pp.currentEnglishLine,
                russianLine: pp.currentRussianLine,
                showTranslation: pp.showTranslation,
                onWordTap: _onWordTap,
                onPhraseAdd: () {
                  final enLine = pp.currentEnglishLine;
                  final ruLine = pp.currentRussianLine;
                  if (enLine != null) {
                    _onPhraseAdd(enLine.text, ruLine?.text ?? enLine.translation, enLine);
                  }
                },
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

          // ── Floating Controls ──
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: _FloatingControls(player: _player, isPlaying: pp.isPlaying)
                .animate()
                .scale(delay: 400.ms, curve: Curves.easeOutBack)
                .fadeIn(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(PlayerProvider pp) {
    if (_loading) {
      final msg = _isExtracting
          ? 'Ищем поток через Rivestream Scraper…'
          : 'Loading video...';
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Text(
                msg,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
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
    return Video(
      controller: _videoController,
      controls: (state) => Stack(
        children: [
          CustomVideoControls(
            player: _player,
            title: widget.video.title,
            isFullscreen: isFullscreen(context),
            onToggleFullscreen: () {
              if (isFullscreen(context)) {
                state.exitFullscreen();
              } else {
                state.enterFullscreen();
              }
            },
            onSettingsTap: () {
              _showNewSettingsBottomSheet(context);
            },
            onBackTap: () {
              if (isFullscreen(context)) {
                state.exitFullscreen();
              } else {
                Navigator.of(context).pop();
              }
            },
          ),
          _SubtitleOverlay(
            pp: pp,
            videoState: state,
            onWordTap: _onWordTap,
            onReplay: () {
              final l = pp.currentEnglishLine;
              if (l != null) {
                _player.seek(Duration(milliseconds: l.startMs));
              }
            },
            onPhraseAdd: () {
              final enLine = pp.currentEnglishLine;
              final ruLine = pp.currentRussianLine;
              if (enLine != null) {
                _onPhraseAdd(
                    enLine.text, ruLine?.text ?? enLine.translation, enLine);
              }
            },
          ),
        ],
      ),
    );
  }

  ItemScrollController? _itemScrollController;
  SubtitleLine? _lastScrolledLine;

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

    _itemScrollController ??= ItemScrollController();

    // Auto-scroll logic
    final activeLine = pp.currentEnglishLine;
    if (activeLine != null && activeLine != _lastScrolledLine) {
      _lastScrolledLine = activeLine;
      final index = pp.englishSubs.indexOf(activeLine);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_itemScrollController!.isAttached) {
            _itemScrollController!.scrollTo(
              index: index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.3, // center-ish
            );
          }
        });
      }
    }

    return ScrollablePositionedList.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemScrollController: _itemScrollController,
      itemCount: pp.englishSubs.length,
      itemBuilder: (ctx, i) {
        final line = pp.englishSubs[i];
        final isActive = line == activeLine;
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
              // Pause auto-scroll briefly when user taps so they aren't jarred
              _lastScrolledLine = line; 
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
          const SizedBox(height: 16),
          // Container(
          //   padding: const EdgeInsets.all(16),
          //   decoration: BoxDecoration(
          //     color: cs.tertiaryContainer.withOpacity(0.3),
          //     borderRadius: BorderRadius.circular(20),
          //   ),
          //   child: Row(children: [
          //     Icon(Icons.lightbulb_outline_rounded,
          //         color: cs.tertiary),
          //     const SizedBox(width: 12),
          //     Expanded(
          //         child: Text(
          //             'Tap any word in subtitles to translate and save it!',
          //             style: tt.bodySmall
          //                 ?.copyWith(color: cs.onSurface))),
          //   ]),
          // ),
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
        onAddToVocabulary: (w, t, p) async {
          try {
            await context.read<VocabularyProvider>().addWord(
                word: w,
                translation: t,
                phonetic: p, 
                contextSentence: line.text,
                contextVideoId: widget.video.id,
                contextTimestampMs: line.startMs,
                type: 'word');
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

  void _onPhraseAdd(String phrase, String? translationFallback, SubtitleLine line) {
    _player.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => WordTapOverlay(
        word: phrase, // Using phrase as the word
        prefilledTranslation: translationFallback,
        contextSentence: line.text,
        contextVideoId: widget.video.id,
        contextTimestampMs: line.startMs,
        onAddToVocabulary: (w, t, p) async {
          try {
            await context.read<VocabularyProvider>().addWord(
                word: w,
                translation: t,
                phonetic: p, 
                contextSentence: line.text,
                contextVideoId: widget.video.id,
                contextTimestampMs: line.startMs,
                type: 'phrase');
            if (ctx.mounted) Navigator.pop(ctx);
            _player.play();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('Phrase added!'),
                  behavior: SnackBarBehavior.floating));
            }
          } catch (e) {
             if (mounted) {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Failed to add phrase: $e'),
                  backgroundColor: Theme.of(context).colorScheme.error,
                  behavior: SnackBarBehavior.floating));
             }
          }
        },
        onSpeak: () => TtsService.speak(phrase),
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

class _SubtitleOverlay extends StatelessWidget {
  final PlayerProvider pp;
  final VideoState videoState;
  final Function(String, SubtitleLine) onWordTap;
  final VoidCallback onReplay;
  final VoidCallback onPhraseAdd;

  const _SubtitleOverlay({
    required this.pp,
    required this.videoState,
    required this.onWordTap,
    required this.onReplay,
    required this.onPhraseAdd,
  });

  @override
  Widget build(BuildContext context) {
    // Only show if enabled
    if (!pp.onVideoSubtitlesEnabled) return const SizedBox.shrink();

    // Only show in fullscreen (approximate check: landscape mode in player usually means fullscreen or near-fullscreen)
    // A better way is to check the actual fullscreen state if we can, but since MaterialVideoControls 
    // handles it internally, we check if the current orientation is landscape.
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    if (!isLandscape) return const SizedBox.shrink();

    final en = pp.currentEnglishLine;
    final ru = pp.currentRussianLine;
    if (en == null && ru == null) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: pp.subtitleBottomPadding, 
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // English (Tappable)
          if (en != null)
            _OverlayTextWrapper(
              child: Padding(
                padding: EdgeInsets.all(12 * pp.subtitleScale),
                child: TappableSubtitleText(
                  line: en,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20 * pp.subtitleScale,
                    fontWeight: FontWeight.w700,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                  onWordTap: onWordTap,
                  accentColor: Colors.yellow,
                ),
              ),
            ),
          
          // Russian (Simple)
          if (pp.showTranslation && (ru != null || en?.translation != null))
            _OverlayTextWrapper(
              isRussian: true,
              child: Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: 16 * pp.subtitleScale,
                    vertical: 8 * pp.subtitleScale),
                child: Text(
                  ru?.text ?? en?.translation ?? '',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16 * pp.subtitleScale,
                    fontWeight: FontWeight.w500,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverlayTextWrapper extends StatelessWidget {
  final Widget child;
  final bool isRussian;
  const _OverlayTextWrapper({required this.child, this.isRussian = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isRussian ? 0.4 : 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _FloatingControls extends StatelessWidget {
  final Player player;
  final bool isPlaying;

  const _FloatingControls({required this.player, required this.isPlaying});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.85),
          borderRadius: BorderRadius.circular(40),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                final target = player.state.position - const Duration(seconds: 5);
                player.seek(target > Duration.zero ? target : Duration.zero);
              },
              icon: const Icon(Icons.replay_5_rounded),
              iconSize: 28,
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: () => player.playOrPause(),
              icon: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
              iconSize: 36,
              style: IconButton.styleFrom(
                fixedSize: const Size(64, 64),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                player.seek(player.state.position + const Duration(seconds: 5));
              },
              icon: const Icon(Icons.forward_5_rounded),
              iconSize: 28,
            ),
            const SizedBox(width: 8),
            PopupMenuButton<double>(
              initialValue: context.read<PlayerProvider>().subtitleScale,
              tooltip: 'Subtitle Size',
              icon: const Icon(Icons.format_size_rounded),
              onSelected: (scale) {
                context.read<PlayerProvider>().setSubtitleScale(scale);
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 0.8, child: Text('Small')),
                const PopupMenuItem(value: 1.0, child: Text('Medium')),
                const PopupMenuItem(value: 1.3, child: Text('Large')),
                const PopupMenuItem(value: 1.6, child: Text('Extra Large')),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: () => context.read<PlayerProvider>().toggleOnVideoSubtitles(),
              icon: Icon(
                context.watch<PlayerProvider>().onVideoSubtitlesEnabled
                    ? Icons.subtitles_rounded
                    : Icons.subtitles_off_rounded,
              ),
              color: context.watch<PlayerProvider>().onVideoSubtitlesEnabled
                  ? cs.primary
                  : cs.onSurfaceVariant.withOpacity(0.5),
              tooltip: 'Toggle On-Video Subtitles',
            ),
          ],
        ),
      ),
    );
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

