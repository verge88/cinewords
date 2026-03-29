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
  bool _hasError = false;
  String? _errorMessage;

  // Стандартный Chrome Mobile User-Agent (без "wv" — иначе YouTube
  // определяет WebView и блокирует embed с ошибкой 150/153).
  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.6099.230 Mobile Safari/537.36';

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

  String _buildEmbedUrl(String videoId) {
    final autoPlay = widget.autoPlay ? 1 : 0;
    final controls = widget.showControls ? 1 : 0;
    return 'https://www.youtube.com/embed/$videoId'
        '?autoplay=$autoPlay'
        '&controls=$controls'
        '&modestbranding=1'
        '&rel=0'
        '&playsinline=1'
        '&enablejsapi=1'
        '&cc_load_policy=0'
        '&iv_load_policy=3'
        '&fs=0'
        '&origin=https://www.youtube.com';
  }

  void _startPositionTracking() {
    _positionTimer?.cancel();
    _positionTimer =
        Timer.periodic(const Duration(milliseconds: 250), (_) async {
      if (_webController == null || !_isReady) return;
      try {
        final result = await _webController!.evaluateJavascript(
          source: 'document.querySelector("video")?.currentTime ?? 0;',
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

  Future<void> _injectTrackingScripts() async {
    await _webController?.evaluateJavascript(source: '''
      (function() {
        var attempts = 0;
        function setup() {
          var v = document.querySelector('video');
          if (!v) {
            attempts++;
            if (attempts < 30) setTimeout(setup, 500);
            return;
          }
          v.addEventListener('playing', function() {
            window.flutter_inappwebview.callHandler('onPlayState', true);
          });
          v.addEventListener('pause', function() {
            window.flutter_inappwebview.callHandler('onPlayState', false);
          });
          v.addEventListener('durationchange', function() {
            if (v.duration && !isNaN(v.duration)) {
              window.flutter_inappwebview.callHandler('onDuration', v.duration);
            }
          });
          if (v.duration && !isNaN(v.duration)) {
            window.flutter_inappwebview.callHandler('onDuration', v.duration);
          }
        }
        setup();
      })();
    ''');
  }

  // ──── Public API ────

  Future<void> seekTo(double seconds) async {
    await _webController?.evaluateJavascript(
      source:
          'var v = document.querySelector("video"); if(v) v.currentTime = $seconds;',
    );
  }

  Future<void> play() async {
    await _webController?.evaluateJavascript(
      source: 'var v = document.querySelector("video"); if(v) v.play();',
    );
  }

  Future<void> pause() async {
    await _webController?.evaluateJavascript(
      source: 'var v = document.querySelector("video"); if(v) v.pause();',
    );
  }

  Future<void> setPlaybackRate(double rate) async {
    await _webController?.evaluateJavascript(
      source:
          'var v = document.querySelector("video"); if(v) v.playbackRate = $rate;',
    );
  }

  Future<void> loadVideo(String videoId) async {
    _isReady = false;
    _hasError = false;
    _errorMessage = null;
    _positionTimer?.cancel();
    if (mounted) setState(() {});
    await _webController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(_buildEmbedUrl(videoId))),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white70, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage ?? 'Video playback error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => loadVideo(widget.videoId),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return InAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri(_buildEmbedUrl(widget.videoId)),
      ),
      initialSettings: InAppWebViewSettings(
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptEnabled: true,
        useHybridComposition: true,
        iframeAllowFullscreen: true,
        transparentBackground: true,
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        domStorageEnabled: true,
        thirdPartyCookiesEnabled: true,
        // КРИТИЧНО: стандартный User-Agent Chrome, без "wv".
        // YouTube блокирует embed в Android WebView (ошибка 150/153),
        // если видит "wv" в User-Agent.
        userAgent: _userAgent,
      ),
      onWebViewCreated: (controller) {
        _webController = controller;

        controller.addJavaScriptHandler(
          handlerName: 'onPlayState',
          callback: (args) {
            if (args.isNotEmpty) {
              widget.onPlayingChanged?.call(args[0] == true);
            }
          },
        );

        controller.addJavaScriptHandler(
          handlerName: 'onDuration',
          callback: (args) {
            if (args.isNotEmpty) {
              final duration = double.tryParse(args[0].toString()) ?? 0;
              widget.onDurationChanged?.call(
                Duration(milliseconds: (duration * 1000).round()),
              );
            }
          },
        );
      },
      onLoadStop: (controller, url) async {
        debugPrint('[YT Player] Page loaded: $url');
        _isReady = true;
        _startPositionTracking();
        await _injectTrackingScripts();
        if (widget.playbackRate != 1.0) {
          setPlaybackRate(widget.playbackRate);
        }
      },
      onConsoleMessage: (controller, consoleMessage) {
        debugPrint('[YT WebView Console] ${consoleMessage.message}');
      },
      onReceivedError: (controller, request, error) {
        debugPrint(
            '[YT Player] Load error: ${request.url} — ${error.description}');
        if (request.url.toString().contains('youtube.com/embed')) {
          if (mounted) {
            setState(() {
              _hasError = true;
              _errorMessage = error.description;
            });
          }
        }
      },
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }
}
