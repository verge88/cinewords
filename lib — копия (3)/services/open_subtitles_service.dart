import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OpenSubtitlesService {
  /// API key for OpenSubtitles.com
  /// Get yours free at https://www.opensubtitles.com/en/consumers
  // static const String apiKey = 'FsiSSVjgKOG5ROA9BDJHlIhOxHxIwnEr';
  static const String apiKey = 'IVYBsmS7v89EL6w3Z3DunIJkadt06p3K';
  static const String _baseUrl = 'https://api.opensubtitles.com/api/v1';

  static final http.Client _client = http.Client();

  /// Search for subtitles by TMDB ID
  /// Returns a list of subtitle file info maps [{file_id, language, url}, ...]
  static Future<List<Map<String, dynamic>>> searchSubtitles({
    required int tmdbId,
    required String language,
  }) async {
    final uri = Uri.parse('$_baseUrl/subtitles').replace(queryParameters: {
      'tmdb_id': tmdbId.toString(),
      'languages': language,
      'type': 'movie',
    });

    debugPrint('[OpenSubs] Searching $language subs for TMDB $tmdbId');

    final response = await _client.get(uri, headers: {
      'Api-Key': apiKey,
      'Content-Type': 'application/json',
      'User-Agent': 'Cinewords v1.0',
    });

    if (response.statusCode != 200) {
      debugPrint('[OpenSubs] Search failed: ${response.statusCode}');
      return [];
    }

    final json = jsonDecode(response.body);
    final List data = json['data'] ?? [];

    final results = <Map<String, dynamic>>[];

    for (final item in data) {
      final attrs = item['attributes'] ?? {};
      final files = attrs['files'] as List? ?? [];

      for (final file in files) {
        results.add({
          'file_id': file['file_id'],
          'language': language,
          'file_name': file['file_name'] ?? '',
        });
      }
    }

    debugPrint('[OpenSubs] Found ${results.length} $language subtitle files');
    return results;
  }

  /// Download a subtitle file by file_id
  /// Returns the raw subtitle content (SRT/VTT format)
  static Future<String?> downloadSubtitle(int fileId) async {
    final uri = Uri.parse('$_baseUrl/download');

    debugPrint('[OpenSubs] Downloading subtitle file $fileId');

    final response = await _client.post(
      uri,
      headers: {
        'Api-Key': apiKey,
        'Content-Type': 'application/json',
        'User-Agent': 'Cinewords v1.0',
        'Accept': '*/*',
      },
      body: jsonEncode({'file_id': fileId}),
    );

    if (response.statusCode != 200) {
      debugPrint('[OpenSubs] Download request failed: ${response.statusCode} ${response.body}');
      return null;
    }

    final json = jsonDecode(response.body);
    final downloadLink = json['link'] as String?;

    if (downloadLink == null) {
      debugPrint('[OpenSubs] No download link in response');
      return null;
    }

    // Download the actual subtitle file
    final fileResponse = await _client.get(Uri.parse(downloadLink));
    if (fileResponse.statusCode == 200) {
      debugPrint('[OpenSubs] Downloaded subtitle (${fileResponse.body.length} bytes)');
      return fileResponse.body;
    }

    debugPrint('[OpenSubs] File download failed: ${fileResponse.statusCode}');
    return null;
  }

  /// Convenience: Search and download the best subtitle for a movie
  static Future<String?> fetchSubtitle({
    required int tmdbId,
    required String language,
  }) async {
    try {
      final results = await searchSubtitles(tmdbId: tmdbId, language: language);
      if (results.isEmpty) return null;

      final fileId = results.first['file_id'] as int;
      return await downloadSubtitle(fileId);
    } catch (e) {
      debugPrint('[OpenSubs] fetchSubtitle error: $e');
      return null;
    }
  }
}
