import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/movie.dart';

/// Сервис каталога фильмов на базе kinopoisk.dev.
///
/// Почему не TMDB: api.themoviedb.org и image.tmdb.org часто блокируются
/// у российских провайдеров (errno 111 / Connection refused). kinopoisk.dev
/// доступен из РФ напрямую, постеры лежат на Kinopoisk CDN, тоже доступны.
///
/// Для работы нужен бесплатный токен. Получить за минуту в Telegram-боте
/// https://t.me/kinopoiskdev_bot (команда /api). Лимит free-тарифа — около
/// 200 запросов в сутки на токен.
class KinopoiskService {
  static const String _apiKey = String.fromEnvironment(
    'KINOPOISK_API_KEY',
    defaultValue: 'B6H8D1M-2DJ4269-Q6WQKC6-S8CH6ZS',
  );

  static const String _baseUrl = 'https://api.kinopoisk.dev/v1.4';
  static const Duration _timeout = Duration(seconds: 12);

  final http.Client _client = http.Client();

  Map<String, String> get _headers => {
        'X-API-KEY': _apiKey,
        'accept': 'application/json',
      };

  Future<Map<String, dynamic>> _get(
    String path, {
    Map<String, String>? query,
  }) async {
    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    debugPrint('[KP] GET $uri');
    final res = await _client.get(uri, headers: _headers).timeout(_timeout);
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception(
        'Kinopoisk.dev: неверный или отсутствующий API-токен. '
        'Получите бесплатный токен в @kinopoiskdev_bot и пропишите его '
        'в KinopoiskService._apiKey или передайте через '
        '--dart-define=KINOPOISK_API_KEY=...',
      );
    }
    if (res.statusCode != 200) {
      throw Exception('Kinopoisk.dev HTTP ${res.statusCode}: ${res.body}');
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  /// Популярные фильмы (топ по рейтингу КП за последние годы).
  Future<List<Movie>> getTrendingMovies({int limit = 30}) async {
    final json = await _get('/movie', query: {
      'page': '1',
      'limit': '$limit',
      'selectFields':
          'id name alternativeName description year rating poster backdrop externalId',
      'sortField': 'votes.kp',
      'sortType': '-1',
      'type': 'movie',
      'rating.kp': '7-10',
    });
    final List docs = json['docs'] ?? [];
    return docs
        .map((e) => Movie.fromKinopoisk(e as Map<String, dynamic>))
        .where((m) => m.isPlayable && m.posterUrl.isNotEmpty)
        .toList();
  }

  /// Поиск по названию.
  Future<List<Movie>> searchMovies(String query, {int limit = 30}) async {
    if (query.trim().isEmpty) return getTrendingMovies(limit: limit);
    final json = await _get('/movie/search', query: {
      'page': '1',
      'limit': '$limit',
      'query': query,
    });
    final List docs = json['docs'] ?? [];
    return docs
        .map((e) => Movie.fromKinopoisk(e as Map<String, dynamic>))
        .where((m) => m.posterUrl.isNotEmpty)
        .toList();
  }

  /// Подробности по фильму (если понадобятся).
  Future<Movie> getMovieDetails(int id) async {
    final json = await _get('/movie/$id');
    return Movie.fromKinopoisk(json);
  }

  void dispose() => _client.close();
}
