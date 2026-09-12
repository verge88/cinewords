import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/searx_video.dart';

/// Страница результатов ddgs.
class DdgsPage {
  final List<SearxVideo> videos;
  final int page;
  final bool hasMore;

  const DdgsPage({
    required this.videos,
    required this.page,
    required this.hasMore,
  });

  static const empty = DdgsPage(videos: [], page: 1, hasMore: false);
}

/// Поиск видео через ddgs API server (https://github.com/deedy5/ddgs).
///
/// ddgs — метапоиск, агрегирующий результаты разных сервисов
/// (для видео — DuckDuckGo). В отличие от SearXNG не требует
/// публичного инстанса с включённым JSON: сервер поднимается
/// локально командой `ddgs api` (по умолчанию порт 4479).
///
/// Адрес задаётся без пересборки:
/// `flutter run --dart-define=DDGS_BASE_URL=http://192.168.1.10:4479`
///
/// На эмуляторе Android хост-машина доступна как 10.0.2.2,
/// поэтому он используется значением по умолчанию.
class DdgsService {
  static const String _configuredBase = String.fromEnvironment(
    'DDGS_BASE_URL',
    defaultValue: '',
  );

  /// Кандидаты в порядке приоритета.
  static const List<String> _defaultInstances = [
    'http://10.0.2.2:4479', // Android-эмулятор -> localhost хоста
    'http://127.0.0.1:4479',
     'http://0.0.0.0:4479', // desktop / iOS-симулятор
  ];

  static String? _lastWorkingBase;

  static const Duration _timeout = Duration(seconds: 20);

  /// Сколько результатов запрашивать за страницу.
  static const int _pageSize = 20;

  /// Ограничение глубины пагинации, чтобы бесконечная прокрутка
  /// не молотила бэкенды вечно.
  static const int maxPage = 5;

  final http.Client _client = http.Client();

  List<String> get _instances {
    final ordered = <String>[];

    void add(String? value) {
      final normalized = value?.trim();
      if (normalized == null || normalized.isEmpty) return;
      final base = normalized.endsWith('/')
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
      if (!ordered.contains(base)) ordered.add(base);
    }

    add(_configuredBase);
    add(_lastWorkingBase);
    _defaultInstances.forEach(add);

    return ordered;
  }

  /// Поиск видео.
  ///
  /// [timeRange] — `d`, `w`, `m` (день/неделя/месяц), как в ddgs.
  /// [safesearch] — 0/1/2 в стиле SearXNG: 0 -> off, 2 -> on,
  /// остальное -> moderate.
  Future<DdgsPage> searchVideos(
    String query, {
    int page = 1,
    String language = 'en',
    String? timeRange,
    int safesearch = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return DdgsPage.empty;

    // ddgs ждёт регион вида "us-en"/"ru-ru"; если передали просто
    // язык ("en"), делаем разумный маппинг.
    final region = language.contains('-')
        ? language
        : (language == 'ru' ? 'ru-ru' : 'us-en');

    final safesearchStr = switch (safesearch) {
      0 => 'off',
      2 => 'on',
      _ => 'moderate',
    };

    final params = <String, String>{
      'query': trimmed,          // было: 'q'
      'region': region,
      'safesearch': safesearchStr,
      'max_results': '$_pageSize',
      'page': '$page',
      if (timeRange != null && timeRange.isNotEmpty)
        'timelimit': _mapTimeRange(timeRange),
    };

    final failures = <String>[];

    for (final base in _instances) {
      try {
        final results = await _requestJson(base, params);
        final videos = _parseResults(results);

        _lastWorkingBase = base;

        return DdgsPage(
          videos: videos,
          page: page,
          hasMore: videos.length >= _pageSize && page < maxPage,
        );
      } catch (error) {
        debugPrint('[ddgs] $base -> $error');
        failures.add('$base: $error');
      }
    }

    throw Exception(
      'ddgs API server недоступен. Запустите его: '
      '`pip install -U "ddgs[api]" && ddgs api`, либо укажите адрес: '
      '--dart-define=DDGS_BASE_URL=http://<host>:4479\n'
      '${failures.join('\n')}',
    );
  }

  /// SearXNG использовал day/month/year — приводим к d/w/m/y.
  String _mapTimeRange(String value) {
    return switch (value) {
      'day' => 'd',
      'week' => 'w',
      'month' => 'm',
      'year' => 'y',
      _ => value,
    };
  }

  List<SearxVideo> _parseResults(List<dynamic> raw) {
    final seen = <String>{};
    final videos = <SearxVideo>[];

    for (final item in raw) {
      if (item is! Map) continue;
      final json = Map<String, dynamic>.from(item);

      // Формат ddgs videos():
      // content (url видео), title, description, duration ("8:22"),
      // embed_url, images{large|medium|small}, publisher, uploader,
      // published (ISO-8601), provider.
      final url = (json['content'] ?? '').toString().trim();
      final title = (json['title'] ?? '').toString().trim();
      if (url.isEmpty || title.isEmpty) continue;
      if (!seen.add(url)) continue;

      String? thumbnail;
      final images = json['images'];
      if (images is Map) {
        thumbnail = (images['large'] ?? images['medium'] ?? images['small'])
            ?.toString();
      }

      videos.add(
        SearxVideo(
          title: title,
          url: url,
          iframeSrc: (json['embed_url'] as String?)?.trim(),
          thumbnailUrl: (thumbnail == null || thumbnail.isEmpty) ? null : thumbnail,
          author: (json['uploader'] as String?)?.trim(),
          content: (json['description'] as String?)?.trim(),
          engine: (json['provider'] ?? json['publisher'])?.toString(),
          length: _parseDuration(json['duration']),
          publishedDate: DateTime.tryParse(
            (json['published'] ?? '').toString(),
          ),
        ),
      );
    }

    return videos;
  }

  /// ddgs отдаёт длительность строкой вида "8:22" или "1:02:10".
  Duration? _parseDuration(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;

    final parts = raw.split(':');
    final numbers = parts.map(int.tryParse).toList(growable: false);
    if (numbers.any((n) => n == null)) return null;

    final total = numbers.length == 3
        ? numbers[0]! * 3600 + numbers[1]! * 60 + numbers[2]!
        : numbers.length == 2
            ? numbers[0]! * 60 + numbers[1]!
            : numbers[0]!;

    return total > 0 ? Duration(seconds: total) : null;
  }

  Future<List<dynamic>> _requestJson(
    String base,
    Map<String, String> params,
  ) async {
    final uri =
        Uri.parse('$base/search/videos').replace(queryParameters: params);
    debugPrint('[ddgs] GET $uri');

    final response = await _client.get(uri, headers: {
      'Accept': 'application/json',
      'User-Agent':
          'CineWords/1.0 (Flutter; +https://github.com/verge88/cinewords)',
    }).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes).trimLeft();
    if (body.isEmpty || body.startsWith('<')) {
      throw Exception('получен HTML вместо JSON');
    }

    final decoded = jsonDecode(body);

    // Сервер может вернуть либо чистый список результатов,
    // либо объект с ключом results — поддержим оба варианта.
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['results'] is List) {
      return decoded['results'] as List;
    }

    throw Exception('неожиданная структура ответа');
  }

  void dispose() => _client.close();
}
