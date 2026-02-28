import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class YouTubePlayerWidget extends StatefulWidget {
  final String videoId;
  final bool autoPlay;
  final bool showControls;
  final double playbackRate;
  final ValueChanged<Duration>? onPositionChanged;
  final ValueChanged<bool>? onPlayingChanged;
  final ValueChanged<Duration>? onDurationChanged;

  const YouTubePlayerWidget({
    super.key,
    required this.videoId,
    this.autoPlay = true,
    this.showControls = true,
    this.playbackRate = 1.0,
    this.onPositionChanged,
    this.onPlayingChanged,
    this.onDurationChanged,
  });

  @override
  State<YouTubePlayerWidget> createState() => YouTubePlayerWidgetState();
}

class YouTubePlayerWidgetState extends State<YouTubePlayerWidget> {
  InAppWebViewController? _webController;
  Timer? _positionTimer;
  bool _isReady = false;

  // Completer for subtitle fetch requests
  Completer<String>? _subtitleCompleter;

  @override
  void didUpdateWidget(covariant YouTubePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playbackRate != widget.playbackRate) {
      setPlaybackRate(widget.playbackRate);
    }
    if (oldWidget.videoId != widget.videoId) {
      loadVideo(widget.videoId);
    }
  }

  String _buildPlayerHtml() {
    final autoPlay = widget.autoPlay ? 1 : 0;
    final controls = widget.showControls ? 1 : 0;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="referrer" content="strict-origin-when-cross-origin">
  <style>
    * { margin: 0; padding: 0; overflow: hidden; }
    html, body { width: 100%; height: 100%; background: #000; }
    #player { width: 100%; height: 100%; }
    iframe { width: 100%; height: 100%; border: none; }
  </style>
</head>
<body>
  <div id="player"></div>
  <script>
    var tag = document.createElement('script');
    tag.src = "https://www.youtube.com/iframe_api";
    var firstScriptTag = document.getElementsByTagName('script')[0];
    firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);

    var player;
    
    function onYouTubeIframeAPIReady() {
      player = new YT.Player('player', {
        videoId: '${widget.videoId}',
        host: 'https://www.youtube-nocookie.com',
        playerVars: {
          'autoplay': $autoPlay,
          'controls': $controls,
          'modestbranding': 1,
          'rel': 0,
          'playsinline': 1,
          'enablejsapi': 1,
          'origin': 'https://www.youtube-nocookie.com',
          'widget_referrer': 'https://www.youtube-nocookie.com',
          'cc_load_policy': 0,
          'iv_load_policy': 3
        },
        events: {
          'onReady': onPlayerReady,
          'onStateChange': onPlayerStateChange,
          'onError': onPlayerError
        }
      });
    }

    function onPlayerReady(event) {
      window.flutter_inappwebview.callHandler('onReady', player.getDuration());
    }

    function onPlayerStateChange(event) {
      var isPlaying = event.data == YT.PlayerState.PLAYING;
      window.flutter_inappwebview.callHandler('onStateChange', event.data, isPlaying);
    }

    function onPlayerError(event) {
      window.flutter_inappwebview.callHandler('onError', event.data);
    }

    function getPosition() {
      if (player && player.getCurrentTime) {
        return player.getCurrentTime();
      }
      return 0;
    }

    function seekTo(seconds) {
      if (player && player.seekTo) player.seekTo(seconds, true);
    }

    function playVideo() {
      if (player && player.playVideo) player.playVideo();
    }

    function pauseVideo() {
      if (player && player.pauseVideo) player.pauseVideo();
    }

    function setRate(rate) {
      if (player && player.setPlaybackRate) player.setPlaybackRate(rate);
    }

    function loadNewVideo(videoId) {
      if (player && player.loadVideoById) player.loadVideoById(videoId);
    }

    // ═══════════════════════════════════════════
    //  Subtitle fetching via XHR (uses browser cookies/session)
    // ═══════════════════════════════════════════
    function fetchSubtitleData(url) {
      return new Promise(function(resolve, reject) {
        var xhr = new XMLHttpRequest();
        xhr.open('GET', url, true);
        xhr.onload = function() {
          if (xhr.status === 200) {
            resolve(xhr.responseText);
          } else {
            resolve('');
          }
        };
        xhr.onerror = function() {
          resolve('');
        };
        xhr.send();
      });
    }

    async function downloadSubtitles(url) {
      try {
        var text = await fetchSubtitleData(url);
        window.flutter_inappwebview.callHandler('onSubtitlesLoaded', text);
      } catch(e) {
        window.flutter_inappwebview.callHandler('onSubtitlesLoaded', '');
      }
    }
  </script>
</body>
</html>
''';
  }

  void _startPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_webController == null || !_isReady) return;
      try {
        final result = await _webController!.evaluateJavascript(
          source: 'getPosition();',
        );
        if (result != null && result != 'null' && result != '') {
          final seconds = double.tryParse(result.toString());
          if (seconds != null && seconds > 0) {
            widget.onPositionChanged?.call(
              Duration(milliseconds: (seconds * 1000).round()),
            );
          }
        }
      } catch (_) {}
    });
  }

  // ──── Public API ────

  Future<void> seekTo(double seconds) async {
    await _webController?.evaluateJavascript(source: 'seekTo($seconds);');
  }

  Future<void> play() async {
    await _webController?.evaluateJavascript(source: 'playVideo();');
  }

  Future<void> pause() async {
    await _webController?.evaluateJavascript(source: 'pauseVideo();');
  }

  Future<void> setPlaybackRate(double rate) async {
    await _webController?.evaluateJavascript(source: 'setRate($rate);');
  }

  Future<void> loadVideo(String videoId) async {
    await _webController?.evaluateJavascript(
      source: "loadNewVideo('$videoId');",
    );
  }

  /// Download subtitles via the WebView's XHR (has correct cookies/session)
  Future<String> fetchSubtitlesViaWebView(String url) async {
    if (_webController == null || !_isReady) return '';

    _subtitleCompleter = Completer<String>();

    try {
      await _webController!.evaluateJavascript(
        source: "downloadSubtitles('${url.replaceAll("'", "\\'")}');",
      );

      // Wait for the JS callback with a timeout
      final result = await _subtitleCompleter!.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => '',
      );

      return result;
    } catch (e) {
      debugPrint('[Player] WebView subtitle fetch error: $e');
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllowFullscreen: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        useHybridComposition: true,
        userAgent:
            'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      ),
      initialData: InAppWebViewInitialData(
        data: _buildPlayerHtml(),
        baseUrl: WebUri('https://www.youtube-nocookie.com'),
        encoding: 'utf-8',
        mimeType: 'text/html',
      ),
      onWebViewCreated: (controller) {
        _webController = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onReady',
          callback: (args) {
            _isReady = true;
            if (args.isNotEmpty) {
              final duration = double.tryParse(args[0].toString()) ?? 0;
              widget.onDurationChanged?.call(
                Duration(milliseconds: (duration * 1000).round()),
              );
            }
            _startPositionTracking();
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onStateChange',
          callback: (args) {
            if (args.length >= 2) {
              final isPlaying = args[1] == true;
              widget.onPlayingChanged?.call(isPlaying);
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onError',
          callback: (args) {
            debugPrint('YouTube Player Error: ${args.firstOrNull}');
          },
        );

        // Handler for subtitle data coming back from JS
        controller.addJavaScriptHandler(
          handlerName: 'onSubtitlesLoaded',
          callback: (args) {
            final data = args.isNotEmpty ? args[0]?.toString() ?? '' : '';
            if (_subtitleCompleter != null && !_subtitleCompleter!.isCompleted) {
              _subtitleCompleter!.complete(data);
            }
          },
        );
      },
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }
}
