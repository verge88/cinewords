import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/subtitle_line.dart';
import '../../models/video_item.dart';
import '../../providers/player_provider.dart';
import '../../providers/video_provider.dart';
import '../../providers/vocabulary_provider.dart';
import '../../services/movie_stream_service.dart';
import '../../services/stream_service.dart';
import '../../services/supabase_service.dart';
import '../../services/tts_service.dart';
import '../../widgets/dual_subtitles_widget.dart' show TappableSubtitleText;
import '../../widgets/player/custom_video_controls.dart';
import '../../widgets/player/player_settings_sheet.dart';
import '../../widgets/word_tap_overlay.dart';

/// Высота, которую «съедает» плавающая таблетка управления снизу.
/// Контент под плеером получает такой же нижний паддинг, чтобы таблетка
/// ничего не перекрывала.
const double _kPillReserve = 96;

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

  // Провайдер захватываем один раз — обращаться к context из stream-колбэков
  // после dispose небезопасно.
  late final PlayerProvider _pp;

  final List<StreamSubscription<dynamic>> _subs = [];

  bool _loading = true;
  bool _isExtracting = false;
  String? _error;
  bool _showSubList = false;

  final Stopwatch _watchStopwatch = Stopwatch();

  ItemScrollController? _itemScrollController;
  SubtitleLine? _lastScrolledLine;

  @override
  void initState() {
    super.initState();
    _pp = context.read<PlayerProvider>();

    _player = Player();
    _videoController = VideoController(_player);

    _subs.add(_player.stream.position.listen((pos) {
      if (mounted) _pp.updatePosition(pos);
    }));

    _subs.add(_player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _watchStopwatch.start();
      } else {
        _watchStopwatch.stop();
      }
      _pp.setPlaying(playing);
    }));

    _subs.add(_player.stream.error.listen((error) {
      debugPrint('[Player] Error: $error');
      if (mounted && error.isNotEmpty) {
        setState(() => _error = 'Playback error: $error');
      }
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _watchStopwatch.stop();
    final durationSec = _watchStopwatch.elapsed.inSeconds;
    final posMs = _player.state.position.inMilliseconds;
    if (durationSec > 10) {
      SupabaseService.updateWatchProgress(widget.video.id, posMs, durationSec)
          .catchError((_) {});
    }

    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _streamService.dispose();
    super.dispose();
  }

  // ──────────────────────────────── loading ────────────────────────────────

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
          throw Exception('Не удалось получить поток фильма. '
              'Возможно, он недоступен у Rivestream-провайдеров.');
        }
        url = stream.url;
        headers = stream.headers;

        _pp.setAvailableQualities(
          stream.qualities.isEmpty
              ? const ['Auto']
              : stream.qualities.map((q) => q.quality).toList(),
        );

        final enSub = stream.subtitleFor('en');
        final ruSub = stream.subtitleFor('ru');
        effectiveVideo = widget.video.copyWith(
          subtitleUrl: enSub?.url,
          subtitleUrlRu: ruSub?.url,
        );
      } else if (widget.video.sourceType == 'direct' &&
          widget.video.videoUrl != null) {
        url = widget.video.videoUrl!;
        _pp.setAvailableQualities(const ['Auto']);
      } else {
        debugPrint('[Player] Getting stream for ${widget.video.youtubeId}...');
        final qualities =
            await _streamService.getAvailableQualities(widget.video.youtubeId);
        if (!mounted) return;
        _pp.setAvailableQualities(qualities);
        url = await _streamService.getPlayableUrl(widget.video.youtubeId);
      }

      if (!mounted) return;
      _pp.loadVideo(effectiveVideo);

      await _player.open(Media(url, httpHeaders: headers), play: true);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      debugPrint('[Player] Error loading video: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _isExtracting = false;
          _error = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _changeQuality(String? newQuality) async {
    if (!mounted || newQuality == _pp.selectedQuality) return;
    _pp.setSelectedQuality(newQuality);

    final pos = _player.state.position;
    final wasPlaying = _player.state.playing;

    try {
      String url;
      if (widget.video.sourceType == 'vidapi') {
        return;
      } else if (widget.video.sourceType == 'direct' &&
          widget.video.videoUrl != null) {
        url = widget.video.videoUrl!;
      } else {
        url = await _streamService.getPlayableUrl(widget.video.youtubeId,
            quality: newQuality);
      }
      await _player.open(Media(url), play: false);
      await _player.seek(pos);
      if (wasPlaying) _player.play();
    } catch (e) {
      debugPrint('[Player] Error changing quality: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось сменить качество: $e')),
        );
      }
    }
  }

  // ──────────────────────────────── actions ────────────────────────────────

  void _seekToLineStart() {
    final l = _pp.currentEnglishLine;
    if (l != null) _player.seek(Duration(milliseconds: l.startMs));
  }

  void _addCurrentPhrase() {
    final en = _pp.currentEnglishLine;
    if (en == null) return;
    final ru = _pp.currentRussianLine;
    _onPhraseAdd(en.text, ru?.text ?? en.translation, en);
  }

  void _seekRelative(int seconds) {
    final target = _player.state.position + Duration(seconds: seconds);
    final duration = _player.state.duration;
    if (target < Duration.zero) {
      _player.seek(Duration.zero);
    } else if (duration > Duration.zero && target > duration) {
      _player.seek(duration);
    } else {
      _player.seek(target);
    }
  }

  void _showSettingsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlayerSettingsSheet(onQualityChanged: _changeQuality),
    );
  }

  Future<void> _openInYouTube() async {
    final url =
        Uri.parse('https://www.youtube.com/watch?v=${widget.video.youtubeId}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showProxyDialog() {
    final controller = TextEditingController();
    StreamService.getProxy().then((current) => controller.text = current ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Настройки прокси'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'HTTP-прокси для обхода ограничений YouTube.\n'
              'Формат: host:port (например, 192.168.1.1:8080)',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Адрес прокси',
                hintText: 'host:port',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await StreamService.setProxy(null);
              await _streamService.recreateClient();
              if (ctx.mounted) Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Прокси отключён')),
              );
            },
            child: const Text('Сбросить'),
          ),
          FilledButton(
            onPressed: () async {
              final proxy = controller.text.trim();
              await StreamService.setProxy(proxy.isEmpty ? null : proxy);
              await _streamService.recreateClient();
              if (ctx.mounted) Navigator.pop(ctx);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(proxy.isEmpty
                      ? 'Прокси отключён'
                      : 'Прокси установлен: $proxy'),
                ),
              );
              _load();
            },
            child: const Text('Сохранить и повторить'),
          ),
        ],
      ),
    );
  }

  // ───────────────────────────────── build ─────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pp = context.watch<PlayerProvider>();
    final fullscreen = isFullscreen(context);

    return Scaffold(
      backgroundColor: cs.surface,
      // В неполноэкранном режиме заголовок не дублируем: он есть в блоке
      // информации под плеером. В AppBar остаётся только навигация и действия.
      appBar: AppBar(
        titleSpacing: 0,
        title: const SizedBox.shrink(),
        actions: [
          PopupMenuButton<double>(
            icon: const Icon(Icons.speed_rounded),
            tooltip: 'Скорость',
            onSelected: (s) {
              pp.setPlaybackSpeed(s);
              _player.setRate(s);
            },
            itemBuilder: (_) => [0.5, 0.75, 1.0, 1.25, 1.5]
                .map(
                  (s) => PopupMenuItem(
                    value: s,
                    child: Text(
                      '${s}x',
                      style: TextStyle(
                        fontWeight: pp.playbackSpeed == s
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          IconButton(
            tooltip: 'Перевод',
            icon: Icon(pp.showTranslation
                ? Icons.translate_rounded
                : Icons.g_translate_outlined),
            onPressed: pp.toggleTranslation,
          ),
          IconButton(
            tooltip: 'Транскрипт',
            icon: Icon(_showSubList
                ? Icons.movie_outlined
                : Icons.format_list_bulleted_rounded),
            onPressed: () => setState(() => _showSubList = !_showSubList),
          ),
          IconButton(
            tooltip: 'Прокси',
            icon: const Icon(Icons.vpn_key_rounded),
            onPressed: _showProxyDialog,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildPlayer(pp, fullscreen),
              ),
              if (pp.isAutoTranslating) _autoTranslateBanner(cs),
              _SubtitlePanel(
                englishLine: pp.currentEnglishLine,
                russianLine: pp.currentRussianLine,
                showTranslation: pp.showTranslation,
                onWordTap: _onWordTap,
              ).animate().fadeIn(duration: 200.ms),
              Expanded(child: _showSubList ? _subList(pp) : _info(pp)),
            ],
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: _FloatingControls(
              video: widget.video,
              isPlaying: pp.isPlaying,
              hasActiveLine: pp.currentEnglishLine != null,
              onPlayPause: _player.playOrPause,
              onSeekBack: () => _seekRelative(-5),
              onSeekForward: () => _seekRelative(5),
              onLineStart: _seekToLineStart,
              onAddPhrase: _addCurrentPhrase,
            )
                .animate()
                .scale(delay: 300.ms, curve: Curves.easeOutBack)
                .fadeIn(),
          ),
        ],
      ),
    );
  }

  Widget _autoTranslateBanner(ColorScheme cs) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: cs.tertiaryContainer,
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: cs.onTertiaryContainer),
          ),
          const SizedBox(width: 10),
          Text(
            'Переводим субтитры…',
            style: TextStyle(
              color: cs.onTertiaryContainer,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    ).animate().fadeIn().slideY();
  }

  Widget _buildPlayer(PlayerProvider pp, bool fullscreen) {
    if (_loading) {
      final msg = _isExtracting
          ? 'Ищем поток через Rivestream Scraper…'
          : 'Загружаем видео…';
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Container(
        color: Colors.black,
        padding: const EdgeInsets.all(12),
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white70, size: 40),
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Повторить'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _showProxyDialog,
                      icon: const Icon(Icons.vpn_key, size: 16),
                      label: const Text('Прокси'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openInYouTube,
                      icon: const Icon(Icons.open_in_new, size: 16),
                      label: const Text('YouTube'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Video(
      controller: _videoController,
      // Tear-off, а не свежее замыкание на каждый build: иначе Video
      // видит "новые" controls каждый кадр и лишний раз обновляет
      // videoViewParametersNotifier.
      controls: _videoControls,
    );
  }
/// Контролы плеера. Контекст берём через [Builder] — он находится ниже
  /// `FullscreenInheritedWidget`, поэтому `isFullscreen` даёт корректный
  /// ответ и во врезке, и в полноэкранном роуте.
  Widget _videoControls(VideoState state) {
    return Builder(
      builder: (ctx) {
        final fs = isFullscreen(ctx);
        return Stack(
          children: [
            Positioned.fill(
              child: CustomVideoControls(
                player: _player,
                title: widget.video.title,
                isFullscreen: fs,
                onToggleFullscreen: () => toggleFullscreen(ctx),
                onSettingsTap: _showSettingsSheet,
                onBackTap: () => fs
                    ? exitFullscreen(ctx)
                    : Navigator.of(ctx).maybePop(),
              ),
            ),
            // Субтитры поверх видео нужны только в fullscreen: во врезке
            // их показывает широкая панель под плеером.
            if (fs)
              _SubtitleOverlay(onWordTap: _onWordTap),
          ],
        );
      },
    );
  }
  Widget _subList(PlayerProvider pp) {
    final cs = Theme.of(context).colorScheme;
    if (pp.isLoadingSubs) {
      return const Center(child: CircularProgressIndicator());
    }
    if (pp.englishSubs.isEmpty) {
      return Center(
        child: Text(
          pp.subtitleError ?? 'Субтитры недоступны',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      );
    }

    _itemScrollController ??= ItemScrollController();

    final activeLine = pp.currentEnglishLine;
    if (activeLine != null && activeLine != _lastScrolledLine) {
      _lastScrolledLine = activeLine;
      final index = pp.englishSubs.indexOf(activeLine);
      if (index != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_itemScrollController?.isAttached ?? false) {
            _itemScrollController!.scrollTo(
              index: index,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              alignment: 0.3,
            );
          }
        });
      }
    }

    return ScrollablePositionedList.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, _kPillReserve),
      itemScrollController: _itemScrollController,
      itemCount: pp.englishSubs.length,
      itemBuilder: (ctx, i) {
        final line = pp.englishSubs[i];
        final isActive = line == activeLine;
        final ruLine = i < pp.russianSubs.length ? pp.russianSubs[i] : null;
        final translation = ruLine?.text ?? line.translation;

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: isActive ? cs.primaryContainer.withOpacity(0.5) : null,
            borderRadius: BorderRadius.circular(14),
          ),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            leading: Text(
              _fmt(line.startMs),
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: cs.primary, fontWeight: FontWeight.w600),
            ),
            title: Text(
              line.text,
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal),
            ),
            subtitle: pp.showTranslation && translation != null
                ? Text(
                    translation,
                    style: Theme.of(ctx)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  )
                : null,
            onTap: () {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, _kPillReserve),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.video.title,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.video.channelName != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.video.channelName!,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Chip(
                Icons.signal_cellular_alt_rounded,
                widget.video.difficultyLabel,
                Color(widget.video.difficultyColorValue),
              ),
              _Chip(Icons.timer_outlined, widget.video.formattedDuration,
                  cs.secondary),
              _Chip(Icons.text_fields_rounded,
                  '${pp.englishSubs.length} реплик', cs.tertiary),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────── vocabulary sheets ──────────────────────────

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
                  type: 'word',
                );
            if (ctx.mounted) Navigator.pop(ctx);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('«$w» добавлено'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Не удалось добавить «$w»: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onSpeak: () => TtsService.speak(word),
      ),
    ).whenComplete(() {
      if (mounted) _player.play();
    });
  }

  void _onPhraseAdd(
      String phrase, String? translationFallback, SubtitleLine line) {
    _player.pause();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => WordTapOverlay(
        word: phrase,
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
                  type: 'phrase',
                );
            if (ctx.mounted) Navigator.pop(ctx);
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Фраза добавлена'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Не удалось добавить фразу: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        onSpeak: () => TtsService.speak(phrase),
      ),
    ).whenComplete(() {
      if (mounted) _player.play();
    });
  }

  String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}

// ─────────────────────────── панель реплик (full width) ───────────────────────

/// Панель текущей реплики. Занимает всю ширину плеера, без внутренних кнопок —
/// перемотка к началу реплики и сохранение фразы вынесены в нижнюю таблетку.
class _SubtitlePanel extends StatelessWidget {
  final SubtitleLine? englishLine;
  final SubtitleLine? russianLine;
  final bool showTranslation;
  final void Function(String word, SubtitleLine line) onWordTap;

  const _SubtitlePanel({
    required this.englishLine,
    required this.russianLine,
    required this.showTranslation,
    required this.onWordTap,
  });

  String? get _translation {
    if (russianLine != null) return russianLine!.text;
    return englishLine?.translation;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final translation = _translation;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
          bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
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
                height: 1.35,
                color: cs.onSurface,
              ),
              onWordTap: onWordTap,
              accentColor: cs.primary,
            )
          else
            Text(
              '♪  …',
              style: tt.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant.withOpacity(0.4),
                fontStyle: FontStyle.italic,
              ),
            ),
          if (showTranslation && englishLine != null && translation != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.secondaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                translation,
                style: tt.bodyMedium
                    ?.copyWith(color: cs.onSecondaryContainer, height: 1.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────── субтитры поверх видео (fullscreen) ──────────────────

class _SubtitleOverlay extends StatelessWidget {
  final void Function(String word, SubtitleLine line) onWordTap;

  const _SubtitleOverlay({required this.onWordTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, pp, _) {
        if (!pp.onVideoSubtitlesEnabled) return const SizedBox.shrink();

        final en = pp.currentEnglishLine;
        final ru = pp.currentRussianLine;
        if (en == null && ru == null) return const SizedBox.shrink();

        final scale = pp.subtitleScale;
        final translation = ru?.text ?? en?.translation;

        return Positioned(
          left: 16,
          right: 16,
          bottom: pp.subtitleBottomPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (en != null)
                _OverlayTextWrapper(
                  child: Padding(
                    padding: EdgeInsets.all(10 * scale),
                    child: TappableSubtitleText(
                      line: en,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20 * scale,
                        fontWeight: FontWeight.w700,
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black)
                        ],
                      ),
                      onWordTap: onWordTap,
                      accentColor: Colors.yellow,
                    ),
                  ),
                ),
              if (pp.showTranslation && translation != null)
                _OverlayTextWrapper(
                  isRussian: true,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: 14 * scale, vertical: 7 * scale),
                    child: Text(
                      translation,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16 * scale,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(blurRadius: 4, color: Colors.black)
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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

// ────────────────────────── нижняя таблетка управления ──────────────────────

/// Компактная таблетка: начало реплики · −5s · play/pause · +5s ·
/// сохранить фразу · избранное.
/// Кнопки размера субтитров и их включения перенесены в PlayerSettingsSheet.
class _FloatingControls extends StatelessWidget {
  final VideoItem video;
  final bool isPlaying;
  final bool hasActiveLine;
  final VoidCallback onPlayPause;
  final VoidCallback onSeekBack;
  final VoidCallback onSeekForward;
  final VoidCallback onLineStart;
  final VoidCallback onAddPhrase;

  const _FloatingControls({
    required this.video,
    required this.isPlaying,
    required this.hasActiveLine,
    required this.onPlayPause,
    required this.onSeekBack,
    required this.onSeekForward,
    required this.onLineStart,
    required this.onAddPhrase,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Material(
        elevation: 6,
        shadowColor: Colors.black.withOpacity(0.25),
        color: cs.surfaceContainerHighest.withOpacity(0.92),
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          // Если экран узкий — таблетка скроллится по горизонтали
          // вместо overflow.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PillButton(
                  icon: Icons.replay_rounded,
                  tooltip: 'К началу реплики',
                  onPressed: hasActiveLine ? onLineStart : null,
                  color: cs.primary,
                ),
                _PillButton(
                  icon: Icons.replay_5_rounded,
                  tooltip: '−5 сек',
                  onPressed: onSeekBack,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: IconButton.filled(
                    onPressed: onPlayPause,
                    iconSize: 26,
                    icon: Icon(isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                    style: IconButton.styleFrom(
                      fixedSize: const Size(48, 48),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
                _PillButton(
                  icon: Icons.forward_5_rounded,
                  tooltip: '+5 сек',
                  onPressed: onSeekForward,
                ),
                _PillButton(
                  icon: Icons.bookmark_add_outlined,
                  tooltip: 'Сохранить фразу',
                  onPressed: hasActiveLine ? onAddPhrase : null,
                  color: cs.tertiary,
                ),
                Consumer<VideoProvider>(
                  builder: (context, vp, _) {
                    final isFav = vp.isFavorite(video.id);
                    return _PillButton(
                      icon: isFav
                          ? Icons.favorite_rounded
                          : Icons.favorite_outline_rounded,
                      tooltip: isFav ? 'Убрать из избранного' : 'В избранное',
                      onPressed: () => vp.toggleFavorite(video),
                      color: isFav ? Colors.redAccent : null,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  const _PillButton({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      iconSize: 22,
      color: color,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
