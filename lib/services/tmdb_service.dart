import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/movie.dart';
import 'tmdb_config.dart';

class TMDBService {
  final http.Client _client = http.Client();

  Future<List<Movie>> searchMovies(String query) async {
    final uri = Uri.parse('${TMDBConfig.baseUrl}/search/movie')
        .replace(queryParameters: {
      'api_key': TMDBConfig.apiKey,
      'query': query,
    });

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('TMDB search failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final List results = json['results'] ?? [];

    return results.map((e) => Movie.fromJson(e)).toList();
  }

  Future<List<Movie>> getTrendingMovies() async {
    final uri = Uri.parse('${TMDBConfig.baseUrl}/trending/movie/week')
        .replace(queryParameters: {
      'api_key': TMDBConfig.apiKey,
    });

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('TMDB trending failed: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    final List results = json['results'] ?? [];

    return results.map((e) => Movie.fromJson(e)).toList();
  }

  Future<Movie> getMovieDetails(int tmdbId) async {
    final uri = Uri.parse('${TMDBConfig.baseUrl}/movie/$tmdbId')
        .replace(queryParameters: {
      'api_key': TMDBConfig.apiKey,
    });

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw Exception('TMDB details failed: ${response.statusCode}');
    }

    return Movie.fromJson(jsonDecode(response.body));
  }

  void dispose() {
    _client.close();
  }
}
