import 'dart:async';
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

  /// Build the embed URL directly — no HTML wrapper needed for the iframe,
  /// but we use the IFrame API via an HTML page loaded from youtube.com origin.
  String _buildPlayerHtml() {
    final autoPlay = widget.autoPlay ? 1 : 0;
    final controls = widget.showControls ? 1 : 0;

    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
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
        playerVars: {
          'autoplay': $autoPlay,
          'controls': $controls,
          'modestbranding': 1,
          'rel': 0,
          'playsinline': 1,
          'enablejsapi': 1,
          'cc_load_policy': 0,
          'iv_load_policy': 3,
          'fs': 0,
          // ДОБАВЛЕНО: Явное указание origin помогает обойти ошибку 150/152
          'origin': 'https://www.youtube.com' 
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
      console.log('YouTube error code: ' + event.data);
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

  @override
  Widget build(BuildContext context) {
    return InAppWebView(
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        iframeAllowFullscreen: true,
        javaScriptEnabled: true,
        transparentBackground: true,
        // useHybridComposition is important for Android video playback
        useHybridComposition: true,
        // Use a standard desktop user-agent so YouTube serves a full player
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
      ),
      // KEY FIX: Load HTML with baseUrl set to https://www.youtube.com
      // This makes the WebView send a proper Referer header to YouTube,
      // which prevents error 150/152-4.
      initialData: InAppWebViewInitialData(
        data: _buildPlayerHtml(),
        baseUrl: WebUri('https://www.youtube.com/'),
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
            debugPrint('[YT Player] Error: ${args.firstOrNull}');
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
