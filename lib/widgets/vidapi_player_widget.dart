import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class VidApiPlayerWidget extends StatefulWidget {
  final String embedUrl;

  const VidApiPlayerWidget({
    super.key,
    required this.embedUrl,
  });

  @override
  State<VidApiPlayerWidget> createState() => _VidApiPlayerWidgetState();
}

class _VidApiPlayerWidgetState extends State<VidApiPlayerWidget> {
  InAppWebViewController? _webController;
  bool _hasError = false;
  String? _errorMessage;

  static const _userAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.6099.230 Mobile Safari/537.36';

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
                onPressed: () {
                  setState(() {
                    _hasError = false;
                    _errorMessage = null;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(widget.embedUrl)),
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
          userAgent: _userAgent,
          // Блокируем всплывающие окна
          javaScriptCanOpenWindowsAutomatically: false,
          useShouldOverrideUrlLoading: true,
          supportMultipleWindows: false,
          contentBlockers: [
            // Блокируем известные рекламные домены
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: ".*(ads|pop|click|doubleclick|taboola|outbrain).*"),
              action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                  urlFilter: ".*\\.js",
                  resourceType: [ContentBlockerTriggerResourceType.SCRIPT]),
              action: ContentBlockerAction(
                type: ContentBlockerActionType.CSS_DISPLAY_NONE,
                selector: ".ads, .ad, .mgid-container, #popunder, .popunder",
              ),
            ),
          ],
        ),
        onWebViewCreated: (controller) {
          _webController = controller;
        },
        onPermissionRequest: (controller, request) async {
          return PermissionResponse(
            resources: request.resources,
            action: PermissionResponseAction.GRANT,
          );
        },
        shouldOverrideUrlLoading: (controller, navigationAction) async {
          final uri = navigationAction.request.url;
          if (uri != null) {
            final host = uri.host.toLowerCase();
            final url = uri.toString().toLowerCase();

            // Разрешаем основной домен и важные ресурсы
            if (host.contains('vidsrc') ||
                host.contains('2embed') ||
                host.contains('google') ||
                host.contains('gstatic') ||
                host.contains('cloudflare') ||
                host.contains('tmdb') ||
                host.contains('akamai') ||
                host.contains('fastly') ||
                url.contains('.m3u8') ||
                url.contains('.mp4')) {
              return NavigationActionPolicy.ALLOW;
            }
          }
          debugPrint('[VidAPI Player] Blocked navigation to: $uri');
          return NavigationActionPolicy.CANCEL;
        },
        onReceivedError: (controller, request, error) {
          // Игнорируем ошибки для рекламных доменов
          final url = request.url.toString().toLowerCase();
          if (url.contains('ads') ||
              url.contains('pop') ||
              url.contains('doubleclick')) {
            return;
          }

          debugPrint(
              '[VidAPI Player] Load error: ${request.url} — ${error.description}');
          if (mounted && request.isForMainFrame!) {
            setState(() {
              _hasError = true;
              _errorMessage = error.description;
            });
          }
        },
        onLoadStop: (controller, url) async {
          if (!mounted) return;

          // Инъекция скрипта для удаления рекламных элементов и блокировки window.open
          await controller.evaluateJavascript(source: """
            (function() {
              // Блокируем создание новых окон
              window.open = function() { return null; };
              
              const hideAds = () => {
                const selectors = [
                  '.ads', '.ad', 'img[src*="ads"]', 'div[id*="pop"]', 'div[class*="pop"]',
                  '.mgid-container', '#popunder', '.popunder', '.modal-backdrop', '.modal',
                  '#overlay', '.overlay', 'iframe[src*="ad"]', 'div[style*="position: fixed"]'
                ];
                selectors.forEach(s => {
                  document.querySelectorAll(s).forEach(el => {
                    el.style.display = 'none';
                    el.style.visibility = 'hidden';
                    el.style.pointerEvents = 'none';
                  });
                });
              };

              hideAds();
              setInterval(hideAds, 1000); // Повторяем для динамической рекламы

              // Пытаемся автоматически нажать Play
              const playButton = document.querySelector('.play-button, .vjs-big-play-button');
              if (playButton) playButton.click();
            })();
          """).catchError((e) => debugPrint('JS injection error: \$e'));
        },
      ),
    );
  }
}
