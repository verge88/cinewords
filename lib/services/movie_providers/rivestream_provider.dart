import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'provider_base.dart';

/// Rivestream Scraper API — единственный найденный публичный JSON-эндпоинт
/// в начале 2026, который стабильно отдаёт прямые .m3u8 ссылки на фильмы
/// по TMDB id. Список под-провайдеров (asiacloud, primevids, guru, ...)
/// получается динамически из `/api/providers`, потом дёргается
/// `/api/provider?provider={name}&id={tmdb}`.
///
/// Источник архитектуры — `kodify-js/MovieDex` (`rive_providers/rive.dart`).
class RivestreamProvider implements MovieStreamProvider {
  static const String _baseUrl = 'https://scrapper.rivestream.org/api';

  /// Ручной приоритет: эти провайдеры стабильнее всего отдают английскую
  /// аудиодорожку, остальные перебираются после.
  static const List<String> _preferred = [
    'asiacloud',
    'primevids',
    'flowcast',
    'guru',
  ];

  /// Аудио-метки, которые не пытаемся показывать в первую очередь
  /// (иначе для языкового приложения это бесполезно).
  static const Set<String> _badLangHints = {
    'hindi',
    'tamil',
    'telugu',
    'malayalam',
    'bengali',
    'panjabi',
    'urdu',
    'vietsub',
    'vietnamese',
  };

  @override
  String get name => 'Rivestream';

  @override
  Future<MovieStream?> fetchStream({
    required int tmdbId,
    String? imdbId,
  }) async {
    final providers = await _listProviders();
    if (providers.isEmpty) return null;

    final ordered = <String>[
      ..._preferred.where(providers.contains),
      ...providers.where((p) => !_preferred.contains(p)),
    ];

    for (final p in ordered) {
      try {
        final stream = await _tryProvider(p, tmdbId);
        if (stream != null) return stream;
      } on TimeoutException {
        debugPrint('[Rive] $p timeout');
      } catch (e) {
        debugPrint('[Rive] $p error: $e');
      }
    }
    return null;
  }

  Future<List<String>> _listProviders() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/providers'))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return [];
      final json = jsonDecode(res.body);
      return List<String>.from(json['data'] ?? const []);
    } catch (e) {
      debugPrint('[Rive] /providers failed: $e');
      return [];
    }
  }

  Future<MovieStream?> _tryProvider(String provider, int tmdbId) async {
    final url = '$_baseUrl/provider?provider=$provider&id=$tmdbId';
    final res = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    final data = decoded['data'] as Map<String, dynamic>?;
    if (data == null) return null;

    final sources = (data['sources'] as List?) ?? const [];
    if (sources.isEmpty) return null;

    final picked = _pickBestSource(sources);
    if (picked == null) return null;

    final rawUrl = picked['url'] as String? ?? '';
    if (rawUrl.isEmpty) return null;

    // Иногда URL — обёртка `?url=...&headers=...` от прокси Rivestream.
    final parsed = Uri.parse(rawUrl);
    final cleanUrl = parsed.queryParameters['url'] ?? rawUrl;
    String? referer;
    final headersParam = parsed.queryParameters['headers'];
    if (headersParam != null) {
      try {
        final h = jsonDecode(headersParam) as Map<String, dynamic>;
        referer = h['Referer'] as String? ?? h['referer'] as String?;
      } catch (_) {}
    }

    final outHeaders = <String, String>{
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      if (referer != null && referer.isNotEmpty) 'Referer': referer,
    };

    final qualities = await _fetchQualities(cleanUrl, outHeaders);

    final captions = (data['captions'] as List?) ?? const [];
    final subs = <StreamSubtitle>[];
    for (final raw in captions) {
      final c = raw as Map<String, dynamic>;
      final u = (c['file'] as String? ?? c['url'] as String? ?? '').trim();
      final label = (c['label'] as String? ?? c['lang'] as String? ?? '').trim();
      if (u.isNotEmpty && label.isNotEmpty) {
        subs.add(StreamSubtitle(
          url: u,
          language: normalizeLanguageCode(label),
          label: label,
        ));
      }
    }

    return MovieStream(
      url: qualities.isNotEmpty ? qualities.first.url : cleanUrl,
      headers: outHeaders,
      qualities: qualities.isEmpty
          ? [StreamSource('auto', cleanUrl)]
          : qualities,
      subtitles: subs,
      audioLanguage: picked['quality'] as String?,
      providerName: 'Rivestream/$provider',
    );
  }

  /// Выбираем источник: сначала English/Original, потом любые HLS,
  /// исключая откровенно неподходящие аудио (хинди, вьетсаб и т.п.).
  Map<String, dynamic>? _pickBestSource(List sources) {
    Map<String, dynamic>? englishMatch;
    Map<String, dynamic>? hlsMatch;
    for (final raw in sources) {
      final s = raw as Map<String, dynamic>;
      final qual = (s['quality'] as String? ?? '').toLowerCase().trim();
      final url = (s['url'] as String? ?? '').trim();
      if (url.isEmpty) continue;
      if (_badLangHints.any(qual.contains)) continue;
      if (qual.contains('english') || qual.contains('original')) {
        englishMatch ??= s;
      } else if (qual.contains('hls') || url.contains('.m3u8')) {
        hlsMatch ??= s;
      }
    }
    if (englishMatch != null) return englishMatch;
    if (hlsMatch != null) return hlsMatch;
    // последний шанс — первый непустой
    for (final raw in sources) {
      final s = raw as Map<String, dynamic>;
      if ((s['url'] as String? ?? '').isNotEmpty) return s;
    }
    return null;
  }

  Future<List<StreamSource>> _fetchQualities(
    String url,
    Map<String, String> headers,
  ) async {
    if (!url.contains('.m3u8')) {
      return [StreamSource('auto', url)];
    }
    try {
      final res = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return [StreamSource('auto', url)];
      final body = res.body;
      if (body.contains('.ts') && !body.contains('#EXT-X-STREAM-INF')) {
        return [StreamSource('auto', url)];
      }
      final list = parseMasterPlaylist(body, url);
      if (list.isNotEmpty) {
        list.add(StreamSource('auto', url));
      }
      return list.isEmpty ? [StreamSource('auto', url)] : list;
    } catch (_) {
      return [StreamSource('auto', url)];
    }
  }
}
