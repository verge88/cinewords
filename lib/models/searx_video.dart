import 'package:equatable/equatable.dart';

import 'video_item.dart';

/// Результат поиска в категории `videos` SearXNG.
///
/// Набор полей соответствует шаблону `videos.html`
/// (см. docs.searxng.org → Simple Theme Templates): помимо url/title
/// движки отдают `iframe_src`, `thumbnail`, `length`, `author`,
/// `publishedDate` и `content`.
class SearxVideo extends Equatable {
  final String title;
  final String url;

  /// URL для встраивания в `<iframe>`. Есть не у всех движков.
  final String? iframeSrc;

  final String? thumbnailUrl;
  final String? author;
  final String? content;

  /// Движок-источник (youtube, peertube, vimeo, dailymotion, invidious...).
  final String? engine;

  final Duration? length;
  final DateTime? publishedDate;

  const SearxVideo({
    required this.title,
    required this.url,
    this.iframeSrc,
    this.thumbnailUrl,
    this.author,
    this.content,
    this.engine,
    this.length,
    this.publishedDate,
  });

  /// [baseUrl] нужен, чтобы развернуть относительные ссылки:
  /// многие инстансы отдают превью через свой image proxy
  /// (`/image_proxy?url=...`), а часть движков — протокол-относительные
  /// `//i.ytimg.com/...`.
  factory SearxVideo.fromJson(
    Map<String, dynamic> json, {
    required String baseUrl,
  }) {
    String? absolute(dynamic value) {
      final raw = value?.toString().trim();
      if (raw == null || raw.isEmpty) return null;
      if (raw.startsWith('//')) return 'https:$raw';
      if (raw.startsWith('/')) return '$baseUrl$raw';
      return raw;
    }

    return SearxVideo(
      title: (json['title'] ?? '').toString().trim(),
      url: (json['url'] ?? '').toString().trim(),
      iframeSrc: absolute(json['iframe_src']),
      thumbnailUrl: absolute(json['thumbnail'] ?? json['img_src']),
      author: (json['author'] as String?)?.trim(),
      content: (json['content'] as String?)?.trim(),
      engine: (json['engine'] as String?)?.trim(),
      length: _parseLength(json['length']),
      publishedDate: _parseDate(json['publishedDate']),
    );
  }

  /// `length` приходит в разных форматах: секунды числом, `3:15`,
  /// `0:03:15` (str(timedelta)) и изредка ISO-8601 `PT3M15S`.
  static Duration? _parseLength(dynamic value) {
    if (value == null) return null;

    if (value is num) {
      final seconds = value.round();
      return seconds > 0 ? Duration(seconds: seconds) : null;
    }

    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final asSeconds = int.tryParse(raw);
    if (asSeconds != null) {
      return asSeconds > 0 ? Duration(seconds: asSeconds) : null;
    }

    if (raw.startsWith('PT') || raw.startsWith('P')) {
      final match =
          RegExp(r'PT(?:(\d+)H)?(?:(\d+)M)?(?:([\d.]+)S)?').firstMatch(raw);
      if (match == null) return null;
      final h = int.tryParse(match.group(1) ?? '0') ?? 0;
      final m = int.tryParse(match.group(2) ?? '0') ?? 0;
      final s = double.tryParse(match.group(3) ?? '0')?.round() ?? 0;
      final total = h * 3600 + m * 60 + s;
      return total > 0 ? Duration(seconds: total) : null;
    }

    final parts = raw.split(':');
    if (parts.length < 2 || parts.length > 3) return null;

    final numbers = parts
        .map((p) => int.tryParse(p.split('.').first.trim()))
        .toList(growable: false);
    if (numbers.any((n) => n == null)) return null;

    final total = parts.length == 3
        ? numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!
        : numbers[0]! * 60 + numbers[1]!;

    return total > 0 ? Duration(seconds: total) : null;
  }

  static DateTime? _parseDate(dynamic value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  /// YouTube-идентификатор, если результат ведёт на YouTube или
  /// на его frontend (invidious/piped). Такие видео проигрываются
  /// нативным [PlayerScreen] вместе с транскриптом и словарём.
  String? get youtubeId {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;

    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;

    bool looksLikeId(String value) =>
        RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(value);

    if (host.endsWith('youtu.be')) {
      final id = segments.isNotEmpty ? segments.first : '';
      return looksLikeId(id) ? id : null;
    }

    final isYoutubeLike = host.endsWith('youtube.com') ||
        host.endsWith('youtube-nocookie.com') ||
        host.contains('invidious') ||
        host.contains('piped') ||
        host.contains('yewtu.be');

    if (!isYoutubeLike) return null;

    final fromQuery = uri.queryParameters['v'];
    if (fromQuery != null && looksLikeId(fromQuery)) return fromQuery;

    for (final prefix in const ['embed', 'shorts', 'v', 'live']) {
      final index = segments.indexOf(prefix);
      if (index != -1 && index + 1 < segments.length) {
        final id = segments[index + 1];
        if (looksLikeId(id)) return id;
      }
    }

    return null;
  }

  bool get isYoutube => youtubeId != null;

  /// Встраиваемый URL для WebView: сначала `iframe_src` от движка,
  /// иначе просто страница результата.
  String get playableUrl => (iframeSrc != null && iframeSrc!.isNotEmpty)
      ? iframeSrc!
      : url;

  String get formattedLength {
    final d = length;
    if (d == null || d == Duration.zero) return '';
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  /// Маппинг в модель приложения. Для YouTube отдаём `sourceType: youtube`,
  /// чтобы StreamService сам достал поток, для остального — `iframe`.
  VideoItem toVideoItem() {
    final id = youtubeId;

    return VideoItem(
      id: 'searx_${url.hashCode.abs()}',
      youtubeId: id ?? '',
      title: title,
      sourceType: id != null ? 'youtube' : 'iframe',
      videoUrl: id != null ? null : playableUrl,
      description: content,
      thumbnailUrl: thumbnailUrl,
      channelName: author ?? engine,
      durationSec: length?.inSeconds ?? 0,
      category: 'general',
    );
  }

  @override
  List<Object?> get props => [url, title];
}
