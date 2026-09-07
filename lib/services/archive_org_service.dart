import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

/// Прямой URL потока + (опционально) URL файла субтитров,
/// извлечённые из метаданных Internet Archive.
class ArchiveStream {
  final String videoUrl;
  final String? subtitleUrl;
  const ArchiveStream({required this.videoUrl, this.subtitleUrl});
}

/// Каталог фильмов с archive.org (Internet Archive).
///
/// Альтернатива vidsrc/Kinopoisk: только public-domain, прямые .mp4 ссылки,
/// никакой extraction-логики и блокировок. Идеально для языкового приложения —
/// многие фильмы из коллекций `feature_films`, `classic_tv_movies` имеют
/// английские субтитры прямо внутри элемента.
class ArchiveOrgService {
  static const String _base = 'https://archive.org';
  static const String _searchUrl = '$_base/advancedsearch.php';
  static const String _metaUrl = '$_base/metadata';
  static const Duration _timeout = Duration(seconds: 15);

  final http.Client _client = http.Client();

  Future<List<Movie>> getTrendingMovies({int limit = 30}) {
    return _search(
      query:
          'collection:(feature_films) AND mediatype:(movies) AND format:(MPEG4)',
      sort: 'downloads desc',
      limit: limit,
    );
  }

  Future<List<Movie>> searchMovies(String query, {int limit = 30}) {
    if (query.trim().isEmpty) return getTrendingMovies(limit: limit);
    final escaped = query.replaceAll('"', r'\"');
    return _search(
      query:
          'mediatype:(movies) AND format:(MPEG4) AND (title:("$escaped") OR description:("$escaped"))',
      sort: 'downloads desc',
      limit: limit,
    );
  }

  Future<List<Movie>> _search({
    required String query,
    required String sort,
    required int limit,
  }) async {
    final uri = Uri.parse(_searchUrl).replace(queryParameters: {
      'q': query,
      'fl[]': 'identifier,title,description,year,creator',
      'sort[]': sort,
      'rows': '$limit',
      'page': '1',
      'output': 'json',
    });
    debugPrint('[Archive] GET $uri');
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Archive.org HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final docs = (json['response']?['docs'] as List?) ?? [];
    return docs
        .map((d) => _toMovie(d as Map<String, dynamic>))
        .where((m) => m.title.isNotEmpty)
        .toList();
  }

  Movie _toMovie(Map<String, dynamic> j) {
    final id = j['identifier'] as String;
    final title = _flatten(j['title']) ?? id;
    return Movie(
      id: id.hashCode.abs(),
      title: title,
      overview: _flatten(j['description']) ?? '',
      posterUrl: '$_base/services/img/$id',
      backdropUrl: '$_base/services/img/$id',
      releaseDate: j['year']?.toString() ?? '',
      voteAverage: 0,
      archiveId: id,
    );
  }

  static String? _flatten(dynamic v) {
    if (v == null) return null;
    if (v is String) return v;
    if (v is List) return v.whereType<String>().join(' ').trim();
    return v.toString();
  }

  /// Резолвит конкретный архивный элемент в прямой URL .mp4 + URL субтитров.
  /// Лезет в `metadata`-эндпоинт, выбирает самый большой видеофайл и первый
  /// найденный .srt/.vtt.
  Future<ArchiveStream> resolveStream(String archiveId) async {
    final uri = Uri.parse('$_metaUrl/$archiveId');
    debugPrint('[Archive] GET $uri');
    final res = await _client.get(uri).timeout(_timeout);
    if (res.statusCode != 200) {
      throw Exception('Archive.org metadata HTTP ${res.statusCode}');
    }
    final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final files = (json['files'] as List?) ?? [];

    String? bestVideo;
    int bestVideoSize = 0;
    String? bestSub;

    bool isVideoFile(String name, String format) {
      final n = name.toLowerCase();
      final f = format.toLowerCase();
      if (n.endsWith('.mp4') || n.endsWith('.m4v')) return true;
      if (f.contains('h.264') || f == 'mpeg4' || f == '512kb mpeg4') return true;
      return false;
    }

    bool isSubFile(String name) {
      final n = name.toLowerCase();
      return n.endsWith('.srt') || n.endsWith('.vtt');
    }

    for (final raw in files) {
      final m = raw as Map<String, dynamic>;
      final name = m['name'] as String? ?? '';
      final format = m['format'] as String? ?? '';
      final size = int.tryParse(m['size']?.toString() ?? '0') ?? 0;

      if (isVideoFile(name, format) && size > bestVideoSize) {
        bestVideo = name;
        bestVideoSize = size;
      }
      if (bestSub == null && isSubFile(name)) {
        bestSub = name;
      }
    }

    if (bestVideo == null) {
      throw Exception('В архиве "$archiveId" не нашлось mp4-файла');
    }

    String fileUrl(String name) =>
        '$_base/download/$archiveId/${Uri.encodeComponent(name)}';

    return ArchiveStream(
      videoUrl: fileUrl(bestVideo),
      subtitleUrl: bestSub != null ? fileUrl(bestSub) : null,
    );
  }

  void dispose() => _client.close();
}
