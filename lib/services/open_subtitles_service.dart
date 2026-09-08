// import 'dart:convert';
// import 'package:flutter/foundation.dart';
// import 'package:http/http.dart' as http;

// class OpenSubtitlesService {
//   /// API key for OpenSubtitles.com
//   /// Get yours free at https://www.opensubtitles.com/en/consumers
//   // static const String apiKey = 'FsiSSVjgKOG5ROA9BDJHlIhOxHxIwnEr';
//   static const String apiKey = 'IVYBsmS7v89EL6w3Z3DunIJkadt06p3K';
//   static const String _baseUrl = 'https://api.opensubtitles.com/api/v1';

//   static final http.Client _client = http.Client();

//   /// Search for subtitles by TMDB ID
//   /// Returns a list of subtitle file info maps [{file_id, language, url}, ...]
//   static Future<List<Map<String, dynamic>>> searchSubtitles({
//     required int tmdbId,
//     required String language,
//   }) async {
//     final uri = Uri.parse('$_baseUrl/subtitles').replace(queryParameters: {
//       'tmdb_id': tmdbId.toString(),
//       'languages': language,
//       'type': 'movie',
//     });

//     debugPrint('[OpenSubs] Searching $language subs for TMDB $tmdbId');

//     final response = await _client.get(uri, headers: {
//       'Api-Key': apiKey,
//       'Content-Type': 'application/json',
//       'User-Agent': 'Cinewords v1.0',
//     });

//     if (response.statusCode != 200) {
//       debugPrint('[OpenSubs] Search failed: ${response.statusCode}');
//       return [];
//     }

//     final json = jsonDecode(response.body);
//     final List data = json['data'] ?? [];

//     final results = <Map<String, dynamic>>[];

//     for (final item in data) {
//       final attrs = item['attributes'] ?? {};
//       final files = attrs['files'] as List? ?? [];

//       for (final file in files) {
//         results.add({
//           'file_id': file['file_id'],
//           'language': language,
//           'file_name': file['file_name'] ?? '',
//         });
//       }
//     }

//     debugPrint('[OpenSubs] Found ${results.length} $language subtitle files');
//     return results;
//   }

//   /// Download a subtitle file by file_id
//   /// Returns the raw subtitle content (SRT/VTT format)
//   static Future<String?> downloadSubtitle(int fileId) async {
//     final uri = Uri.parse('$_baseUrl/download');

//     debugPrint('[OpenSubs] Downloading subtitle file $fileId');

//     final response = await _client.post(
//       uri,
//       headers: {
//         'Api-Key': apiKey,
//         'Content-Type': 'application/json',
//         'User-Agent': 'Cinewords v1.0',
//         'Accept': '*/*',
//       },
//       body: jsonEncode({'file_id': fileId}),
//     );

//     if (response.statusCode != 200) {
//       debugPrint('[OpenSubs] Download request failed: ${response.statusCode} ${response.body}');
//       return null;
//     }

//     final json = jsonDecode(response.body);
//     final downloadLink = json['link'] as String?;

//     if (downloadLink == null) {
//       debugPrint('[OpenSubs] No download link in response');
//       return null;
//     }

//     // Download the actual subtitle file
//     final fileResponse = await _client.get(Uri.parse(downloadLink));
//     if (fileResponse.statusCode == 200) {
//       debugPrint('[OpenSubs] Downloaded subtitle (${fileResponse.body.length} bytes)');
//       return fileResponse.body;
//     }

//     debugPrint('[OpenSubs] File download failed: ${fileResponse.statusCode}');
//     return null;
//   }

//   /// Convenience: Search and download the best subtitle for a movie
//   static Future<String?> fetchSubtitle({
//     required int tmdbId,
//     required String language,
//   }) async {
//     try {
//       final results = await searchSubtitles(tmdbId: tmdbId, language: language);
//       if (results.isEmpty) return null;

//       final fileId = results.first['file_id'] as int;
//       return await downloadSubtitle(fileId);
//     } catch (e) {
//       debugPrint('[OpenSubs] fetchSubtitle error: $e');
//       return null;
//     }
//   }
// }


import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class OpenSubtitlesService {
  static const String _baseUrl =
      'https://api.opensubtitles.com/api/v1';

  /// Лучше передавать через:
  /// flutter run --dart-define=OPENSUBTITLES_API_KEY=...
  ///
  /// Не храните рабочий ключ в публичном GitHub-репозитории.
  static const String apiKey = String.fromEnvironment(
    'IVYBsmS7v89EL6w3Z3DunIJkadt06p3K',
    defaultValue: 'IVYBsmS7v89EL6w3Z3DunIJkadt06p3K',
  );

  static final http.Client _client = http.Client();

  static Map<String, String> get _headers => {
        'Api-Key': apiKey,
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'CineWords v1.0',
      };

  /// OpenSubtitles ожидает IMDb ID без префикса `tt`
  /// и без ведущих нулей.
  ///
  /// Например:
  /// tt0111161 -> 111161
  static String? normalizeImdbId(String? value) {
    if (value == null) return null;

    var normalized = value.trim().toLowerCase();

    if (normalized.startsWith('tt')) {
      normalized = normalized.substring(2);
    }

    normalized = normalized.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );

    if (normalized.isEmpty) {
      return null;
    }

    normalized = normalized.replaceFirst(
      RegExp(r'^0+'),
      '',
    );

    return normalized.isEmpty ? '0' : normalized;
  }

  /// Поиск субтитров.
  ///
  /// Сначала можно использовать TMDB ID, а если его нет
  /// или результат пустой — IMDb ID.
  static Future<List<Map<String, dynamic>>> searchSubtitles({
    int? tmdbId,
    String? imdbId,
    required String language,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint(
        '[OpenSubs] OPENSUBTITLES_API_KEY is empty',
      );
      return [];
    }

    final normalizedImdb = normalizeImdbId(imdbId);

    if (tmdbId == null && normalizedImdb == null) {
      debugPrint(
        '[OpenSubs] Search skipped: TMDB and IMDb IDs are missing',
      );
      return [];
    }

    final queryParameters = <String, String>{
      'languages': language,
      'type': 'movie',
      'order_by': 'download_count',
      'order_direction': 'desc',
    };

    if (tmdbId != null) {
      queryParameters['tmdb_id'] = tmdbId.toString();
    } else {
      queryParameters['imdb_id'] = normalizedImdb!;
    }

    final uri = Uri.parse(
      '$_baseUrl/subtitles',
    ).replace(
      queryParameters: queryParameters,
    );

    debugPrint(
      '[OpenSubs] Searching $language: $uri',
    );

    try {
      final response = await _client
          .get(
            uri,
            headers: _headers,
          )
          .timeout(
            const Duration(seconds: 20),
          );

      if (response.statusCode != 200) {
        debugPrint(
          '[OpenSubs] Search failed: '
          '${response.statusCode} ${response.body}',
        );
        return [];
      }

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '[OpenSubs] Unexpected search response',
        );
        return [];
      }

      final data = decoded['data'];

      if (data is! List) {
        return [];
      }

      final results = <Map<String, dynamic>>[];

      for (final item in data) {
        if (item is! Map) continue;

        final attributes = item['attributes'];

        if (attributes is! Map) continue;

        final files = attributes['files'];

        if (files is! List) continue;

        final hearingImpaired =
            attributes['hearing_impaired'] == true;

        final downloadCount =
            (attributes['download_count'] as num?)
                    ?.toInt() ??
                0;

        for (final file in files) {
          if (file is! Map) continue;

          final fileId = file['file_id'];

          if (fileId is! num) continue;

          results.add({
            'file_id': fileId.toInt(),
            'language': language,
            'file_name':
                file['file_name']?.toString() ?? '',
            'hearing_impaired': hearingImpaired,
            'download_count': downloadCount,
          });
        }
      }

      // Обычные субтитры ставим перед SDH.
      results.sort((a, b) {
        final aHearing =
            a['hearing_impaired'] == true ? 1 : 0;
        final bHearing =
            b['hearing_impaired'] == true ? 1 : 0;

        final hearingComparison =
            aHearing.compareTo(bHearing);

        if (hearingComparison != 0) {
          return hearingComparison;
        }

        final aDownloads =
            a['download_count'] as int? ?? 0;
        final bDownloads =
            b['download_count'] as int? ?? 0;

        return bDownloads.compareTo(aDownloads);
      });

      debugPrint(
        '[OpenSubs] Found ${results.length} '
        '$language subtitle files',
      );

      return results;
    } catch (error, stackTrace) {
      debugPrint(
        '[OpenSubs] Search exception: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return [];
    }
  }

  static Future<String?> downloadSubtitle(
    int fileId,
  ) async {
    if (apiKey.isEmpty) {
      debugPrint(
        '[OpenSubs] Download skipped: API key is empty',
      );
      return null;
    }

    final uri = Uri.parse(
      '$_baseUrl/download',
    );

    debugPrint(
      '[OpenSubs] Downloading subtitle file $fileId',
    );

    try {
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'file_id': fileId,
            }),
          )
          .timeout(
            const Duration(seconds: 20),
          );

      if (response.statusCode != 200) {
        debugPrint(
          '[OpenSubs] Download request failed: '
          '${response.statusCode} ${response.body}',
        );
        return null;
      }

      final decoded = jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      final downloadLink =
          decoded['link']?.toString();

      if (downloadLink == null ||
          downloadLink.isEmpty) {
        debugPrint(
          '[OpenSubs] No download link in response',
        );
        return null;
      }

      final fileResponse = await _client
          .get(
            Uri.parse(downloadLink),
            headers: const {
              'Accept': '*/*',
            },
          )
          .timeout(
            const Duration(seconds: 20),
          );

      if (fileResponse.statusCode != 200) {
        debugPrint(
          '[OpenSubs] File download failed: '
          '${fileResponse.statusCode}',
        );
        return null;
      }

      final body = _decodeBody(
        fileResponse.bodyBytes,
      );

      debugPrint(
        '[OpenSubs] Downloaded subtitle: '
        '${fileResponse.bodyBytes.length} bytes',
      );

      return body;
    } catch (error, stackTrace) {
      debugPrint(
        '[OpenSubs] Download exception: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  /// Сначала ищет по TMDB.
  /// Если ничего не найдено — повторяет запрос по IMDb.
  static Future<String?> fetchSubtitle({
    int? tmdbId,
    String? imdbId,
    required String language,
  }) async {
    try {
      if (tmdbId != null) {
        final byTmdb = await searchSubtitles(
          tmdbId: tmdbId,
          language: language,
        );

        final downloaded =
            await _downloadFirstAvailable(byTmdb);

        if (downloaded != null) {
          return downloaded;
        }
      }

      if (normalizeImdbId(imdbId) != null) {
        final byImdb = await searchSubtitles(
          imdbId: imdbId,
          language: language,
        );

        final downloaded =
            await _downloadFirstAvailable(byImdb);

        if (downloaded != null) {
          return downloaded;
        }
      }

      return null;
    } catch (error, stackTrace) {
      debugPrint(
        '[OpenSubs] fetchSubtitle error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  /// Пробуем не только первый результат.
  ///
  /// Иногда первый файл удалён, недоступен или упирается
  /// в ограничение OpenSubtitles.
  static Future<String?> _downloadFirstAvailable(
    List<Map<String, dynamic>> results,
  ) async {
    final candidates = results.take(3);

    for (final candidate in candidates) {
      final fileId = candidate['file_id'];

      if (fileId is! int) continue;

      final content = await downloadSubtitle(
        fileId,
      );

      if (content != null &&
          content.trim().isNotEmpty) {
        return content;
      }
    }

    return null;
  }

  static String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }
}
