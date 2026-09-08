import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/searx_video.dart';

/// Плеер для видео, найденных через SearXNG, у которых нет
/// YouTube-идентификатора: воспроизводим `iframe_src` (или страницу
/// результата) внутри WebView.
class SearxWebPlayerScreen extends StatefulWidget {
  final SearxVideo video;

  const SearxWebPlayerScreen({super.key, required this.video});

  @override
  State<SearxWebPlayerScreen> createState() => _SearxWebPlayerScreenState();
}

class _SearxWebPlayerScreenState extends State<SearxWebPlayerScreen> {
  double _progress = 0;

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(widget.video.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final uri = WebUri(widget.video.playableUrl);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.video.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Открыть в браузере',
            onPressed: _openExternally,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
        bottom: _progress < 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(value: _progress),
              )
            : null,
      ),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: uri),
        initialSettings: InAppWebViewSettings(
          mediaPlaybackRequiresUserGesture: false,
          allowsInlineMediaPlayback: true,
          iframeAllowFullscreen: true,
          transparentBackground: true,
          supportZoom: false,
        ),
        onProgressChanged: (_, progress) {
          if (mounted) setState(() => _progress = progress / 100);
        },
      ),
    );
  }
}
