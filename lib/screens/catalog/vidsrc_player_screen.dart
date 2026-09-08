import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../models/movie.dart';
import '../../models/subtitle_line.dart';
import '../../models/video_item.dart';
import '../../providers/player_provider.dart';

class VidsrcPlayerScreen extends StatefulWidget {
  final Movie movie;

  /// false — обычный VidSrc-плеер;
  /// true — VidSrc + список реплик CineWords.
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
  InAppWebViewController? _controller;

  late final PlayerProvider _playerProvider;
  late final VideoItem _video;

  Timer? _positionTimer;
  final Stopwatch _positionStopwatch = Stopwatch();

  Duration _eventPosition = Duration.zero;
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
      'vidsrcme.ru',
      '/embed/movie/$id',
      const {
        'autoplay': '0',
        'ds_lang': 'en,ru',
      },
    );
  }

  @override
  void initState() {
    super.initState();

    _playerProvider = context.read<PlayerProvider>();
    _video = widget.movie.toVideoItem();

    if (widget.showReplicas) {
      _playerProvider.prepareVideo(_video, notify: false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _playerProvider.loadVideo(_video);
      });

      // VidSrc отправляет точную позицию примерно раз в 5 секунд.
      // Между событиями двигаем позицию локальным таймером.
      _positionTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) {
          if (!mounted || !_positionStopwatch.isRunning) return;

          _playerProvider.updatePosition(
            _eventPosition + _positionStopwatch.elapsed,
          );
        },
      );
    }
  }

  Future<void> _installPlayerEventBridge(
    InAppWebViewController controller,
  ) async {
    await controller.evaluateJavascript(
      source: r'''
        (() => {
          if (window.__cinewordsPlayerBridgeInstalled) {
            return;
          }

          window.__cinewordsPlayerBridgeInstalled = true;

          window.addEventListener('message', (event) => {
            const message = event.data;

            if (!message || message.type !== 'PLAYER_EVENT') {
              return;
            }

            if (!message.data) {
              return;
            }

            window.flutter_inappwebview.callHandler(
              'cinewordsPlayerEvent',
              JSON.stringify(message.data)
            );
          });
        })();
      ''',
    );
  }

  void _handlePlayerEvent(List<dynamic> arguments) {
    if (!widget.showReplicas || arguments.isEmpty || !mounted) {
      return;
    }

    try {
      final dynamic raw = arguments.first;

      final Map<String, dynamic> data;

      if (raw is String) {
        data = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } else if (raw is Map) {
        data = Map<String, dynamic>.from(raw);
      } else {
        return;
      }

      final status = data['player_status']?.toString() ?? '';
      final progress = (data['player_progress'] as num?)?.toDouble() ?? 0;

      _eventPosition = Duration(
        milliseconds: (progress * 1000).round(),
      );

      _positionStopwatch
        ..stop()
        ..reset();

      _playerProvider.updatePosition(_eventPosition);

      switch (status) {
        case 'playing':
          _positionStopwatch.start();
          _playerProvider.setPlaying(true);
          break;

        case 'paused':
        case 'seeked':
        case 'completed':
          _playerProvider.setPlaying(false);
          break;
      }
    } catch (e) {
      debugPrint('[VidSrcBridge] Invalid event: $e');
    }
  }

  Future<bool> _handleBack() async {
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
        appBar: AppBar(title: Text(widget.movie.title)),
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
              tooltip: 'Обновить',
              onPressed: () => _controller?.reload(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildWebView(uri),
            ),

            if (widget.showReplicas)
              Expanded(
                child: _buildReplicas(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebView(Uri uri) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(
            url: WebUri(uri.toString()),
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
          },
          onLoadStart: (_, __) {
            if (!mounted) return;

            setState(() {
              _error = null;
              _progress = 0;
            });
          },
          onLoadStop: (controller, _) async {
            if (!mounted) return;

            setState(() => _progress = 1);

            if (widget.showReplicas) {
              await _installPlayerEventBridge(controller);
            }
          },
          onProgressChanged: (_, progress) {
            if (!mounted) return;
            setState(() => _progress = progress / 100);
          },
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame != true || !mounted) return;

            setState(() {
              _error = error.description;
            });
          },
          shouldOverrideUrlLoading: (_, action) async {
            final url = action.request.url;

            if (url == null) {
              return NavigationActionPolicy.CANCEL;
            }

            if (action.isForMainFrame != true) {
              return NavigationActionPolicy.ALLOW;
            }

            if (url.scheme != 'http' && url.scheme != 'https') {
              return NavigationActionPolicy.CANCEL;
            }

            final host = url.host.toLowerCase();

            if (host == 'vidsrcme.ru' ||
                host.endsWith('.vidsrcme.ru')) {
              return NavigationActionPolicy.ALLOW;
            }

            return NavigationActionPolicy.CANCEL;
          },
          onCreateWindow: (_, __) async {
            // Запрещаем popup-окна.
            return false;
          },
        ),

        if (_progress < 1 && _error == null)
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
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
                      Icons.error_outline,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        setState(() {
                          _error = null;
                          _progress = 0;
                        });

                        _controller?.loadUrl(
                          urlRequest: URLRequest(
                            url: WebUri(uri.toString()),
                          ),
                        );
                      },
                      icon: const Icon(Icons.refresh),
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
          return ColoredBox(
            color: const Color(0xFF111111),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  provider.subtitleError ?? 'Реплики не найдены',
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
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

              const Divider(height: 1, color: Colors.white12),

              Expanded(
                child: ListView.builder(
                  itemCount: english.length,
                  itemBuilder: (context, index) {
                    final line = english[index];
                    final translation =
                        _findTranslation(line, russian);

                    final active = line.id == currentId;

                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: active
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.18)
                          : Colors.transparent,
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
                              _formatTime(line.startMs),
                              style: TextStyle(
                                color: active
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.white38,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
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
                        ],
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

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
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
          if (russian != null) ...[
            const SizedBox(height: 6),
            Text(
              russian.text,
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
    // Сначала ищем по sequenceIndex.
    for (final line in russian) {
      if (line.sequenceIndex == english.sequenceIndex) {
        return line.text;
      }
    }

    // Если индексы дорожек отличаются — ищем по времени.
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

  String _formatTime(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
