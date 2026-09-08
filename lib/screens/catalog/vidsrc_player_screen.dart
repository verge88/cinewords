import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../models/movie.dart';
import '../../models/subtitle_line.dart';
import '../../models/video_item.dart';
import '../../providers/player_provider.dart';

/// Название класса сохранено для обратной совместимости.
///
/// Фактически экран теперь использует VidSpark:
/// https://vidspark.to/movie/$id
///
/// Видео отображается через iframe, а CineWords получает позицию
/// воспроизведения через VidSpark postMessage API.
class VidsrcPlayerScreen extends StatefulWidget {
  final Movie movie;

  /// false — только видеоплеер;
  /// true — видеоплеер, управление CineWords и список реплик.
  final bool showReplicas;

  const VidsrcPlayerScreen({
    super.key,
    required this.movie,
    this.showReplicas = false,
  });

  @override
  State<VidsrcPlayerScreen> createState() => _VidsrcPlayerScreenState();
}

class _VidsrcPlayerScreenState extends State<VidsrcPlayerScreen> {
  static const String _vidSparkOrigin = 'https://vidspark.to';
  static const String _themeColor = '7C3AED';

  InAppWebViewController? _controller;

  late final PlayerProvider _playerProvider;
  late final VideoItem _video;

  Timer? _positionTimer;
  final Stopwatch _positionStopwatch = Stopwatch();

  Duration _eventPosition = Duration.zero;
  Duration _duration = Duration.zero;

  bool _isPlaying = false;
  bool _playerReady = false;

  double _progress = 0;
  String? _error;

  Uri? get _embedUri {
    final imdbId = widget.movie.imdbId?.trim();
    final tmdbId = widget.movie.tmdbId;

    final String id;

    if (imdbId != null && imdbId.isNotEmpty) {
      id = imdbId;
    } else if (tmdbId != null) {
      id = tmdbId.toString();
    } else {
      return null;
    }

    return Uri.https(
      'vidspark.to',
      '/movie/$id',
      const {
        'theme': _themeColor,
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _playerProvider = context.read<PlayerProvider>();
    _video = widget.movie.toVideoItem();

    if (widget.showReplicas) {
      _playerProvider.prepareVideo(
        _video,
        notify: false,
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _playerProvider.loadVideo(_video);
      });

      // VidSpark отправляет timeupdate примерно раз в секунду.
      // Между событиями обновляем позицию локально, чтобы текущая
      // реплика переключалась плавно.
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) {
          if (!mounted || !_positionStopwatch.isRunning) {
            return;
          }

          _playerProvider.updatePosition(
            _eventPosition + _positionStopwatch.elapsed,
          );
        },
      );
    }
  }

  /// Локальная HTML-обёртка необходима, потому что VidSpark API
  /// предназначен для iframe:
  ///
  /// iframe.contentWindow.postMessage(...)
  ///
  /// Обёртка также позволяет проверять source и origin событий.
  String _buildPlayerHtml(Uri uri) {
    final escapedUrl = const HtmlEscape(
      HtmlEscapeMode.attribute,
    ).convert(uri.toString());

    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">

  <meta
    name="viewport"
    content="width=device-width,
             initial-scale=1,
             maximum-scale=1,
             user-scalable=no"
  >

  <style>
    html,
    body {
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      overflow: hidden;
      background: #000000;
    }

    #vidspark-player {
      display: block;
      width: 100%;
      height: 100%;
      margin: 0;
      padding: 0;
      border: 0;
      background: #000000;
    }
  </style>
</head>

<body>
  <iframe
    id="vidspark-player"
    src="$escapedUrl"
    title="VidSpark player"
    allow="autoplay; fullscreen; picture-in-picture; encrypted-media"
    allowfullscreen
    referrerpolicy="origin"
  ></iframe>

  <script>
    (() => {
      const VIDSPARK_ORIGIN = 'https://vidspark.to';
      const playerFrame = document.getElementById('vidspark-player');

      function sendToFlutter(handlerName, payload) {
        if (
          window.flutter_inappwebview &&
          typeof window.flutter_inappwebview.callHandler === 'function'
        ) {
          window.flutter_inappwebview.callHandler(
            handlerName,
            JSON.stringify(payload)
          );
        }
      }

      window.addEventListener('message', (event) => {
        const message = event.data;

        if (event.source !== playerFrame.contentWindow) {
          return;
        }

        if (event.origin !== VIDSPARK_ORIGIN) {
          return;
        }

        if (!message || message.source !== 'vidspark-player') {
          return;
        }

        sendToFlutter('cinewordsPlayerEvent', message);
      });

      window.__cinewordsSendPlayerCommand = (command) => {
        if (!playerFrame || !playerFrame.contentWindow) {
          return false;
        }

        playerFrame.contentWindow.postMessage(
          command,
          VIDSPARK_ORIGIN
        );

        return true;
      };

      playerFrame.addEventListener('load', () => {
        sendToFlutter('cinewordsPlayerReady', {
          ready: true
        });

        setTimeout(() => {
          window.__cinewordsSendPlayerCommand({
            action: 'getStatus'
          });
        }, 500);
      });
    })();
  </script>
</body>
</html>
''';
  }

  void _handlePlayerEvent(List<dynamic> arguments) {
    if (arguments.isEmpty || !mounted) {
      return;
    }

    try {
      final dynamic raw = arguments.first;
      final Map<String, dynamic> data;

      if (raw is String) {
        final decoded = jsonDecode(raw);

        if (decoded is! Map) {
          return;
        }

        data = Map<String, dynamic>.from(decoded);
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else {
        return;
      }

      if (data['source'] != 'vidspark-player') {
        return;
      }

      final event = data['event']?.toString() ?? '';
      final currentTime = _readDouble(data['currentTime']);
      final duration = _readDouble(data['duration']);

      if (currentTime != null &&
          currentTime.isFinite &&
          currentTime >= 0) {
        _eventPosition = Duration(
          milliseconds: (currentTime * 1000).round(),
        );

        if (widget.showReplicas) {
          _playerProvider.updatePosition(_eventPosition);
        }
      }

      if (duration != null &&
          duration.isFinite &&
          duration > 0) {
        _duration = Duration(
          milliseconds: (duration * 1000).round(),
        );
      }

      switch (event) {
        case 'play':
          _setPlaybackState(true);
          break;

        case 'pause':
        case 'ended':
          _setPlaybackState(false);
          break;

        case 'playerstatus':
          final paused = data['paused'];

          if (paused is bool) {
            _setPlaybackState(!paused);
          }
          break;

        case 'seeked':
        case 'timeupdate':
          _restartPositionClockIfPlaying();
          break;
      }
    } catch (error, stackTrace) {
      debugPrint('[VidSpark] Invalid player event: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  double? _readDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  void _setPlaybackState(bool playing) {
    _isPlaying = playing;

    _positionStopwatch
      ..stop()
      ..reset();

    if (playing) {
      _positionStopwatch.start();
    }

    if (widget.showReplicas) {
      _playerProvider.setPlaying(playing);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _restartPositionClockIfPlaying() {
    _positionStopwatch
      ..stop()
      ..reset();

    if (_isPlaying) {
      _positionStopwatch.start();
    }
  }

  Future<void> _sendPlayerCommand(
    String action, {
    Map<String, dynamic> parameters = const {},
  }) async {
    final controller = _controller;

    if (controller == null) {
      return;
    }

    final command = jsonEncode({
      'action': action,
      ...parameters,
    });

    try {
      await controller.evaluateJavascript(
        source: '''
          (() => {
            if (
              typeof window.__cinewordsSendPlayerCommand === 'function'
            ) {
              return window.__cinewordsSendPlayerCommand($command);
            }

            return false;
          })();
        ''',
      );
    } catch (error) {
      debugPrint(
        '[VidSpark] Failed to send command "$action": $error',
      );
    }
  }

  Future<void> _togglePlayback() async {
    await _sendPlayerCommand('togglePlay');
  }

  Future<void> _seekTo(Duration position) async {
    var milliseconds = position.inMilliseconds;

    if (milliseconds < 0) {
      milliseconds = 0;
    }

    if (_duration > Duration.zero &&
        milliseconds > _duration.inMilliseconds) {
      milliseconds = _duration.inMilliseconds;
    }

    final target = Duration(milliseconds: milliseconds);

    await _sendPlayerCommand(
      'seek',
      parameters: {
        'time': target.inMilliseconds / 1000,
      },
    );

    _eventPosition = target;

    _restartPositionClockIfPlaying();

    if (widget.showReplicas) {
      _playerProvider.updatePosition(target);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _seekRelative(Duration difference) async {
    final currentPosition = widget.showReplicas
        ? _playerProvider.position
        : _eventPosition;

    await _seekTo(currentPosition + difference);
  }

  Future<void> _requestPlayerStatus() async {
    await _sendPlayerCommand('getStatus');
  }

  Future<void> _reloadPlayer() async {
    if (!mounted) return;

    _positionStopwatch
      ..stop()
      ..reset();

    _eventPosition = Duration.zero;
    _duration = Duration.zero;
    _isPlaying = false;
    _playerReady = false;

    if (widget.showReplicas) {
      _playerProvider.updatePosition(Duration.zero);
      _playerProvider.setPlaying(false);
    }

    setState(() {
      _error = null;
      _progress = 0;
    });

    await _controller?.reload();
  }

  Future<bool> _handleBack() async {
    // В iframe собственная история не должна блокировать закрытие экрана.
    // Проверяем только историю главной HTML-обёртки.
    final controller = _controller;

    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }

    return true;
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _positionStopwatch.stop();

    if (widget.showReplicas) {
      _playerProvider.setPlaying(false);
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uri = _embedUri;

    if (uri == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.movie.title),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'У фильма отсутствует IMDb или TMDB идентификатор.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: _handleBack,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            widget.movie.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Обновить плеер',
              onPressed: _reloadPlayer,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildWebView(uri),
            ),

            if (widget.showReplicas) ...[
              _buildCineWordsControls(),
              Expanded(
                child: _buildReplicas(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(Uri uri) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          initialData: InAppWebViewInitialData(
            data: _buildPlayerHtml(uri),
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri('https://cinewords.local/player/'),
          ),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            allowsInlineMediaPlayback: true,
            mediaPlaybackRequiresUserGesture: false,
            useShouldOverrideUrlLoading: true,
            supportMultipleWindows: true,
            javaScriptCanOpenWindowsAutomatically: false,
            thirdPartyCookiesEnabled: true,
            transparentBackground: false,
            disableContextMenu: true,
          ),
          onWebViewCreated: (controller) {
            _controller = controller;

            controller.addJavaScriptHandler(
              handlerName: 'cinewordsPlayerEvent',
              callback: (arguments) {
                _handlePlayerEvent(arguments);
                return null;
              },
            );

            controller.addJavaScriptHandler(
              handlerName: 'cinewordsPlayerReady',
              callback: (_) {
                if (!mounted) {
                  return null;
                }

                setState(() {
                  _playerReady = true;
                  _progress = 1;
                  _error = null;
                });

                _requestPlayerStatus();
                return null;
              },
            );
          },
          onLoadStart: (_, __) {
            if (!mounted) return;

            setState(() {
              _error = null;
              _progress = 0;
              _playerReady = false;
            });
          },
          onLoadStop: (_, __) {
            if (!mounted) return;

            // Это окончание загрузки локальной HTML-обёртки.
            // iframe VidSpark может продолжать загрузку.
            setState(() {
              if (_progress < 0.9) {
                _progress = 0.9;
              }
            });
          },
          onProgressChanged: (_, progress) {
            if (!mounted || _playerReady) {
              return;
            }

            setState(() {
              final value = progress / 100;

              // Последние 10% оставляем загрузке iframe.
              _progress = value * 0.9;
            });
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame != true || !mounted) {
              return;
            }

            setState(() {
              _error = error.description;
            });
          },
          shouldOverrideUrlLoading: (_, action) async {
            final url = action.request.url;

            if (url == null) {
              return NavigationActionPolicy.CANCEL;
            }

            final scheme = url.scheme.toLowerCase();

            if (scheme == 'about' || scheme == 'data') {
              return NavigationActionPolicy.ALLOW;
            }

            if (scheme != 'http' && scheme != 'https') {
              return NavigationActionPolicy.CANCEL;
            }

            // Навигация ресурсов и документов внутри VidSpark iframe.
            if (action.isForMainFrame != true) {
              return NavigationActionPolicy.ALLOW;
            }

            final host = url.host.toLowerCase();

            if (host == 'cinewords.local' ||
                host == 'vidspark.to' ||
                host.endsWith('.vidspark.to')) {
              return NavigationActionPolicy.ALLOW;
            }

            // Запрещаем внешним страницам заменять основной экран WebView.
            return NavigationActionPolicy.CANCEL;
          },
          onCreateWindow: (_, __) async {
            // Блокируем popup-окна.
            return false;
          },
        ),

        if (_progress < 1 && _error == null)
          Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
            ),
          ),

        if (_error != null)
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _reloadPlayer,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Повторить'),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCineWordsControls() {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        final position = provider.position;

        final effectiveDuration = _duration > Duration.zero
            ? _duration
            : Duration(
                seconds: _video.durationSec ?? 0,
              );

        final durationMs = effectiveDuration.inMilliseconds;
        final positionMs = position.inMilliseconds;

        final progress = durationMs > 0
            ? (positionMs / durationMs).clamp(0.0, 1.0)
            : 0.0;

        return Material(
          color: const Color(0xFF181818),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (durationMs > 0)
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                  ),
                  child: Slider(
                    value: progress,
                    onChanged: (value) {
                      final targetMs = (durationMs * value).round();

                      _seekTo(
                        Duration(milliseconds: targetMs),
                      );
                    },
                  ),
                )
              else
                const SizedBox(height: 8),

              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Назад на 10 секунд',
                      onPressed: () {
                        _seekRelative(
                          const Duration(seconds: -10),
                        );
                      },
                      icon: const Icon(
                        Icons.replay_10_rounded,
                        color: Colors.white,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: _isPlaying ? 'Пауза' : 'Воспроизвести',
                      onPressed: _playerReady
                          ? _togglePlayback
                          : null,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Вперёд на 10 секунд',
                      onPressed: () {
                        _seekRelative(
                          const Duration(seconds: 10),
                        );
                      },
                      icon: const Icon(
                        Icons.forward_10_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_formatDuration(position)}'
                        ' / '
                        '${effectiveDuration > Duration.zero ? _formatDuration(effectiveDuration) : '--:--'}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Полный экран',
                      onPressed: () {
                        _sendPlayerCommand('enterFullscreen');
                      },
                      icon: const Icon(
                        Icons.fullscreen_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReplicas() {
    return Consumer<PlayerProvider>(
      builder: (context, provider, _) {
        if (provider.isLoadingSubs) {
          return const ColoredBox(
            color: Color(0xFF111111),
            child: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final english = provider.englishSubs;
        final russian = provider.russianSubs;
        final currentId = provider.currentEnglishLine?.id;

        if (english.isEmpty) {
          final message = provider.subtitleError ??
              (
                widget.movie.tmdbId == null &&
                widget.movie.imdbId == null
                    ? 'У фильма отсутствуют TMDB и IMDb ID'
                    : 'Реплики не найдены в OpenSubtitles'
              );

          return ColoredBox(
            color: const Color(0xFF111111),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.subtitles_off_rounded,
                      color: Colors.white54,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () {
                        _playerProvider.loadVideo(_video);
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text(
                        'Повторить загрузку',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }


        return ColoredBox(
          color: const Color(0xFF111111),
          child: Column(
            children: [
              _buildCurrentReplica(provider),
              const Divider(
                height: 1,
                color: Colors.white12,
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: english.length,
                  itemBuilder: (context, index) {
                    final line = english[index];
                    final translation = _findTranslation(
                      line,
                      russian,
                    );

                    final active = line.id == currentId;

                    return Material(
                      color: active
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.18)
                          : Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _seekTo(
                            Duration(milliseconds: line.startMs),
                          );
                        },
                        child: AnimatedContainer(
                          duration: const Duration(
                            milliseconds: 200,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 12,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 52,
                                child: Text(
                                  _formatMilliseconds(line.startMs),
                                  style: TextStyle(
                                    color: active
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                        : Colors.white38,
                                    fontSize: 12,
                                    fontWeight: active
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.text,
                                      style: TextStyle(
                                        color: active
                                            ? Colors.white
                                            : Colors.white70,
                                        fontWeight: active
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                        height: 1.35,
                                      ),
                                    ),
                                    if (translation != null &&
                                        translation.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        translation,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          height: 1.3,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.play_circle_outline_rounded,
                                size: 20,
                                color: active
                                    ? Theme.of(context)
                                        .colorScheme
                                        .primary
                                    : Colors.white24,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentReplica(PlayerProvider provider) {
    final english = provider.currentEnglishLine;
    final russian = provider.currentRussianLine;

    final translation = russian?.text ?? english?.translation;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(
        minHeight: 78,
      ),
      padding: const EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12,
      ),
      color: const Color(0xFF181818),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            english?.text ?? 'Ожидание реплики…',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (translation != null &&
              translation.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              translation,
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String? _findTranslation(
    SubtitleLine english,
    List<SubtitleLine> russian,
  ) {
    // Сначала ищем перевод по исходному порядковому номеру.
    for (final line in russian) {
      if (line.sequenceIndex == english.sequenceIndex) {
        return line.text;
      }
    }

    // Если индексы дорожек не совпадают, ищем пересечение по времени.
    for (final line in russian) {
      final intersects =
          line.startMs <= english.endMs &&
          line.endMs >= english.startMs;

      if (intersects) {
        return line.text;
      }
    }

    return english.translation;
  }

  String _formatMilliseconds(int milliseconds) {
    return _formatDuration(
      Duration(milliseconds: milliseconds),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}
