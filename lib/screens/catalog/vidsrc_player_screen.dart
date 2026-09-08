import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../models/movie.dart';

class VidsrcPlayerScreen extends StatefulWidget {
  final Movie movie;

  const VidsrcPlayerScreen({
    super.key,
    required this.movie,
  });

  @override
  State<VidsrcPlayerScreen> createState() => _VidsrcPlayerScreenState();
}

class _VidsrcPlayerScreenState extends State<VidsrcPlayerScreen> {
  InAppWebViewController? _controller;

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

  Future<bool> _handleBack() async {
    final controller = _controller;

    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return false;
    }

    return true;
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
              'Для этого фильма отсутствует IMDb или TMDB идентификатор.',
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
        body: Stack(
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

                // Запросы на открытие рекламных окон будут отклонены
                // обработчиком onCreateWindow.
                supportMultipleWindows: true,
                javaScriptCanOpenWindowsAutomatically: false,

                thirdPartyCookiesEnabled: true,
                transparentBackground: false,
                disableContextMenu: true,
              ),
              onWebViewCreated: (controller) {
                _controller = controller;
              },
              onLoadStart: (_, __) {
                if (!mounted) return;

                setState(() {
                  _error = null;
                  _progress = 0;
                });
              },
              onProgressChanged: (_, progress) {
                if (!mounted) return;

                setState(() {
                  _progress = progress / 100;
                });
              },
              onReceivedError: (_, request, error) {
                // Ошибки ресурсов внутри страницы не должны перекрывать
                // весь плеер сообщением об ошибке.
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

                // Ограничение применяется только к главному документу.
                // Вложенным iframe и медиаресурсам разрешаем загрузку.
                if (action.isForMainFrame != true) {
                  return NavigationActionPolicy.ALLOW;
                }

                if (url.scheme != 'https' && url.scheme != 'http') {
                  return NavigationActionPolicy.CANCEL;
                }

                final host = url.host.toLowerCase();

                if (host == 'vidsrcme.ru' ||
                    host.endsWith('.vidsrcme.ru')) {
                  return NavigationActionPolicy.ALLOW;
                }

                // Не даём рекламе или редиректам заменить страницу плеера.
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (_, __) async {
                // Запрещаем рекламные popup-окна.
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
                          size: 52,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Не удалось загрузить VidSrc\n\n$_error',
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
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
        ),
      ),
    );
  }
}
