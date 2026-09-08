import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/searx_video.dart';

/// Страница результатов SearXNG.
class SearxngPage {
  final List<SearxVideo> videos;
  final int page;
  final bool hasMore;

  const SearxngPage({
    required this.videos,
    required this.page,
    required this.hasMore,
  });

  static const empty = SearxngPage(videos: [], page: 1, hasMore: false);
}

/// Поиск видео через SearXNG Search API.
///
/// Документация: https://docs.searxng.org/dev/search_api.html
/// Запрос: `GET /search?q=...&categories=videos&format=json`.
///
/// Важно: формат `json` включается администратором инстанса в
/// `settings.yml` (секция `search.formats`), и на многих публичных
/// инстансах он выключен — тогда приходит 403. Поэтому сервис
/// перебирает список инстансов, запоминает первый рабочий и умеет
/// повторить запрос методом POST (часть инстансов режет GET по UA/фильтрам).
///
/// Свой инстанс задаётся без пересборки логики:
/// `flutter run --dart-define=SEARXNG_BASE_URL=https://searx.example.org`
class SearxngService {
  static const String _configuredBase = String.fromEnvironment(
    'SEARXNG_BASE_URL',
    defaultValue: '',
  );

  /// Публичные инстансы-кандидаты. Порядок = приоритет.
  static const List<String> _publicInstances = [
    'https://searx.be',
    'https://baresearch.org',
    'https://search.inetol.net',
    'https://priv.au',
    'https://opnxng.com',
  ];

  /// Последний инстанс, ответивший корректным JSON, — переиспользуется
  /// между запросами и экранами.
  static String? _lastWorkingBase;

  static const Duration _timeout = Duration(seconds: 15);

  /// SearXNG отдаёт результаты постранично, но не сообщает общее число
  /// страниц. Ограничиваем глубину, чтобы бесконечная прокрутка не
  /// молотила инстанс вечно.
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
    _publicInstances.forEach(add);

    return ordered;
  }

  /// Поиск видео.
  ///
  /// [timeRange] — `day`, `month` или `year` (см. параметр `time_range`).
  /// [safesearch] — 0/1/2, как в API.
  Future<SearxngPage> searchVideos(
    String query, {
    int page = 1,
    String language = 'en',
    String? timeRange,
    int safesearch = 1,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return SearxngPage.empty;

    final params = <String, String>{
      'q': trimmed,
      'categories': 'videos',
      'format': 'json',
      'language': language,
      'pageno': '$page',
      'safesearch': '$safesearch',
      if (timeRange != null && timeRange.isNotEmpty) 'time_range': timeRange,
    };

    final failures = <String>[];

    for (final base in _instances) {
      try {
        final json = await _requestJson(base, params);
        final videos = _parseResults(json, base);

        _lastWorkingBase = base;

        return SearxngPage(
          videos: videos,
          page: page,
          hasMore: videos.isNotEmpty && page < maxPage,
        );
      } catch (error) {
        debugPrint('[SearXNG] $base -> $error');
        failures.add('$base: $error');
      }
    }

    throw Exception(
      'Ни один инстанс SearXNG не отдал JSON. На публичных инстансах '
      'формат json часто отключён — укажите свой через '
      '--dart-define=SEARXNG_BASE_URL=https://searx.example.org\n'
      '${failures.join('\n')}',
    );
  }

  List<SearxVideo> _parseResults(Map<String, dynamic> json, String base) {
    final raw = (json['results'] as List?) ?? const [];
    final seen = <String>{};
    final videos = <SearxVideo>[];

    for (final item in raw) {
      if (item is! Map) continue;

      final video = SearxVideo.fromJson(
        Map<String, dynamic>.from(item),
        baseUrl: base,
      );

      if (video.url.isEmpty || video.title.isEmpty) continue;
      if (!seen.add(video.url)) continue;

      videos.add(video);
    }

    return videos;
  }

  Future<Map<String, dynamic>> _requestJson(
    String base,
    Map<String, String> params,
  ) async {
    final uri = Uri.parse('$base/search').replace(queryParameters: params);
    debugPrint('[SearXNG] GET $uri');

    final headers = {
      'Accept': 'application/json',
      // Часть инстансов отбивает запросы без User-Agent как ботов.
      'User-Agent': 'CineWords/1.0 (Flutter; +https://github.com/verge88/cinewords)',
    };

    var response = await _client.get(uri, headers: headers).timeout(_timeout);

    // POST-форма иногда проходит там, где GET заблокирован лимитером.
    if (response.statusCode == 403 || response.statusCode == 429) {
      debugPrint('[SearXNG] GET ${response.statusCode}, пробуем POST');
      response = await _client
          .post(
            Uri.parse('$base/search'),
            headers: {
              ...headers,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: params,
          )
          .timeout(_timeout);
    }

    if (response.statusCode == 403) {
      throw Exception('формат json отключён на инстансе (HTTP 403)');
    }
    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    final body = utf8.decode(response.bodyBytes).trimLeft();
    if (body.isEmpty || body.startsWith('<')) {
      throw Exception('получен HTML вместо JSON');
    }

    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('неожиданная структура ответа');
    }

    return decoded;
  }

  void dispose() => _client.close();
}
