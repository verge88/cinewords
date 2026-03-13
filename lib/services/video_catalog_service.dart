import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Результат обработки одного видео
class VideoProcessingResult {
  final String youtubeId;
  final String title;
  final String status; // 'ready', 'skipped', 'failed'
  final int subtitleCount;
  final String? error;

  VideoProcessingResult({
    required this.youtubeId,
    required this.title,
    required this.status,
    this.subtitleCount = 0,
    this.error,
  });
}

/// Прогресс-коллбэк
typedef ProgressCallback = void Function(
    int processed,
    int total,
    String currentTitle,
    );

/// ============================================================
/// Сервис каталогизации YouTube-видео с субтитрами
/// ============================================================
class VideoCatalogService {
  final SupabaseClient _supabase;
  final YoutubeExplode _yt;
  final http.Client _httpClient;

  /// Задержка между запросами к YouTube (мс), чтобы не получить 429
  final int requestDelayMs;

  /// Языки субтитров, которые мы ищем
  final List<String> targetLanguages;

  bool _disposed = false;

  VideoCatalogService({
    required SupabaseClient supabaseClient,
    this.requestDelayMs = 1500,
    this.targetLanguages = const ['en'],
  })  : _supabase = supabaseClient,
        _yt = YoutubeExplode(),
        _httpClient = http.Client();

  // ============================================================
  // ПУБЛИЧНЫЙ API
  // ============================================================

  /// Поиск видео по запросу, фильтрация и сохранение в БД.
  ///
  /// [query] — поисковый запрос (например, "English conversation practice").
  /// [maxResults] — максимальное количество видео для обработки.
  /// [requireCaptions] — пропускать видео без субтитров.
  /// [onProgress] — коллбэк прогресса.
  ///
  /// Возвращает список результатов обработки.
  Future<List<VideoProcessingResult>> searchAndPopulate({
    required String query,
    int maxResults = 50,
    bool requireCaptions = true,
    List<String>? languages,
    ProgressCallback? onProgress,
  }) async {
    final langs = languages ?? targetLanguages;
    final results = <VideoProcessingResult>[];

    // 1. Создаём задачу поиска
    final taskId = await _createSearchTask(query, langs.first, maxResults);

    try {
      await _updateSearchTaskStatus(taskId, 'running');

      // 2. Выполняем поиск на YouTube
      debugPrint('[Catalog] Searching YouTube: "$query" (max $maxResults)');
      final videos = await _searchYouTube(query, maxResults);
      debugPrint('[Catalog] Found ${videos.length} videos');

      await _updateSearchTaskField(taskId, 'videos_found', videos.length);

      int saved = 0;

      // 3. Обрабатываем каждое видео
      for (int i = 0; i < videos.length; i++) {
        if (_disposed) break;

        final video = videos[i];
        onProgress?.call(i + 1, videos.length, video.title);

        try {
          final result = await _processVideo(
            video: video,
            searchQuery: query,
            languages: langs,
            requireCaptions: requireCaptions,
          );

          results.add(result);
          if (result.status == 'ready') saved++;

          // Задержка между запросами
          if (i < videos.length - 1) {
            await Future.delayed(Duration(milliseconds: requestDelayMs));
          }
        } catch (e) {
          debugPrint('[Catalog] Error processing ${video.id}: $e');
          results.add(VideoProcessingResult(
            youtubeId: video.id.value,
            title: video.title,
            status: 'failed',
            error: e.toString(),
          ));
        }
      }

      // 4. Обновляем задачу
      await _supabase.from('search_tasks').update({
        'status': 'done',
        'videos_saved': saved,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', taskId);

      debugPrint('[Catalog] Done! Saved $saved/${videos.length} videos');
    } catch (e) {
      await _updateSearchTaskStatus(taskId, 'failed',
          error: e.toString());
      rethrow;
    }

    return results;
  }

  /// Обработка одного видео по YouTube ID.
  /// Полезно для добавления конкретного видео.
  Future<VideoProcessingResult> addVideoById({
    required String youtubeVideoId,
    List<String>? languages,
    bool requireCaptions = true,
  }) async {
    final langs = languages ?? targetLanguages;

    // Проверяем, есть ли уже в базе
    final existing = await _supabase
        .from('videos')
        .select('id, status')
        .eq('youtube_id', youtubeVideoId)
        .maybeSingle();

    if (existing != null && existing['status'] == 'ready') {
      return VideoProcessingResult(
        youtubeId: youtubeVideoId,
        title: '(already exists)',
        status: 'ready',
      );
    }

    final video = await _yt.videos.get(youtubeVideoId);

    return _processVideo(
      video: video,
      searchQuery: 'manual_add',
      languages: langs,
      requireCaptions: requireCaptions,
    );
  }

  /// Получить статистику базы.
  Future<Map<String, int>> getStats() async {
    final totalVideos = await _supabase
        .from('videos')
        .select('id')
        .count(CountOption.exact);

    final readyVideos = await _supabase
        .from('videos')
        .select('id')
        .eq('status', 'ready')
        .count(CountOption.exact);

    final withCaptions = await _supabase
        .from('videos')
        .select('id')
        .eq('has_captions', true)
        .count(CountOption.exact);

    final totalSubtitles = await _supabase
        .from('subtitle_lines')
        .select('id')
        .count(CountOption.exact);

    return {
      'total_videos': totalVideos.count,
      'ready_videos': readyVideos.count,
      'with_captions': withCaptions.count,
      'total_subtitle_lines': totalSubtitles.count,
    };
  }

  /// Пакетный поиск по нескольким запросам.
  Future<Map<String, List<VideoProcessingResult>>> batchSearchAndPopulate({
    required List<String> queries,
    int maxResultsPerQuery = 30,
    bool requireCaptions = true,
    List<String>? languages,
    ProgressCallback? onProgress,
  }) async {
    final allResults = <String, List<VideoProcessingResult>>{};

    for (final query in queries) {
      if (_disposed) break;

      debugPrint('[Catalog] === Processing query: "$query" ===');
      try {
        final results = await searchAndPopulate(
          query: query,
          maxResults: maxResultsPerQuery,
          requireCaptions: requireCaptions,
          languages: languages,
          onProgress: onProgress,
        );
        allResults[query] = results;
      } catch (e) {
        debugPrint('[Catalog] Query "$query" failed: $e');
        allResults[query] = [];
      }

      // Пауза между запросами
      await Future.delayed(const Duration(seconds: 3));
    }

    return allResults;
  }

  void dispose() {
    _disposed = true;
    _httpClient.close();
    _yt.close();
  }

  // ============================================================
  // ПРИВАТНЫЕ МЕТОДЫ
  // ============================================================

  /// Поиск видео на YouTube
  Future<List<Video>> _searchYouTube(String query, int maxResults) async {
    final searchList = await _yt.search.search(query);
    final videos = <Video>[];

    // Первая страница результатов
    for (final result in searchList) {
      if (videos.length >= maxResults) break;
      videos.add(result);
    }

    // Дополнительные страницы, если нужно
    var currentList = searchList;
    while (videos.length < maxResults) {
      try {
        final nextPage = await currentList.nextPage();
        if (nextPage == null || nextPage.isEmpty) break;

        for (final result in nextPage) {
          if (videos.length >= maxResults) break;
          videos.add(result);
        }
        currentList = nextPage;
      } catch (e) {
        debugPrint('[Catalog] No more search pages: $e');
        break;
      }
    }

    return videos.take(maxResults).toList();
  }

  /// Обработка одного видео: проверки → сохранение → субтитры
  Future<VideoProcessingResult> _processVideo({
    required Video video,
    required String searchQuery,
    required List<String> languages,
    required bool requireCaptions,
  }) async {
    final youtubeId = video.id.value;
    debugPrint('[Catalog] Processing: $youtubeId "${video.title}"');

    // --- Проверка ограничений ---
    final restrictions = await _checkRestrictions(youtubeId);

    if (!restrictions['is_playable']!) {
      debugPrint('[Catalog] SKIP $youtubeId: not playable');
      await _upsertVideo(
        video: video,
        searchQuery: searchQuery,
        restrictions: restrictions,
        captionLanguages: [],
        status: 'skipped',
        error: 'Video is not playable',
      );
      return VideoProcessingResult(
        youtubeId: youtubeId,
        title: video.title,
        status: 'skipped',
        error: 'Not playable',
      );
    }

    if (restrictions['is_age_restricted']!) {
      debugPrint('[Catalog] SKIP $youtubeId: age restricted');
      await _upsertVideo(
        video: video,
        searchQuery: searchQuery,
        restrictions: restrictions,
        captionLanguages: [],
        status: 'skipped',
        error: 'Age restricted',
      );
      return VideoProcessingResult(
        youtubeId: youtubeId,
        title: video.title,
        status: 'skipped',
        error: 'Age restricted',
      );
    }

    // --- Проверка и скачивание субтитров ---
    final captionData = await _fetchCaptionData(youtubeId);
    final availableLangs = captionData.keys.toList();

    debugPrint('[Catalog] Available captions: $availableLangs');

    // Фильтр: есть ли нужные языки
    final matchedLangs = <String>[];
    for (final lang in languages) {
      for (final available in availableLangs) {
        if (available == lang || available.startsWith(lang)) {
          matchedLangs.add(available);
          break;
        }
      }
    }

    if (requireCaptions && matchedLangs.isEmpty) {
      debugPrint('[Catalog] SKIP $youtubeId: no captions for $languages');
      await _upsertVideo(
        video: video,
        searchQuery: searchQuery,
        restrictions: restrictions,
        captionLanguages: availableLangs,
        status: 'skipped',
        error: 'No captions for requested languages',
      );
      return VideoProcessingResult(
        youtubeId: youtubeId,
        title: video.title,
        status: 'skipped',
        error: 'No captions for $languages',
      );
    }

    // --- Сохранение видео в БД ---
    final dbVideoId = await _upsertVideo(
      video: video,
      searchQuery: searchQuery,
      restrictions: restrictions,
      captionLanguages: availableLangs,
      status: 'ready',
    );

    // --- Скачивание и сохранение субтитров ---
    int totalSubtitleLines = 0;

    for (final lang in matchedLangs) {
      final trackUrl = captionData[lang];
      if (trackUrl == null) continue;

      try {
        final lines = await _downloadAndParseSubtitles(
          captionUrl: trackUrl,
          dbVideoId: dbVideoId,
          language: lang,
        );

        if (lines.isNotEmpty) {
          await _saveSubtitleLines(lines);
          totalSubtitleLines += lines.length;
          debugPrint('[Catalog] Saved ${lines.length} lines for $lang');
        }
      } catch (e) {
        debugPrint('[Catalog] Subtitle download error ($lang): $e');
      }

      // Пауза между языками
      await Future.delayed(Duration(milliseconds: requestDelayMs ~/ 2));
    }

    debugPrint(
        '[Catalog] SAVED $youtubeId: $totalSubtitleLines subtitle lines');

    return VideoProcessingResult(
      youtubeId: youtubeId,
      title: video.title,
      status: 'ready',
      subtitleCount: totalSubtitleLines,
    );
  }

  /// Проверяем ограничения видео через watch page
  Future<Map<String, bool>> _checkRestrictions(String videoId) async {
    final result = {
      'is_playable': true,
      'is_embeddable': true,
      'is_age_restricted': false,
      'is_region_restricted': false,
    };

    try {
      final playerResponse = await _fetchPlayerResponse(videoId);
      if (playerResponse == null) return result;

      // playabilityStatus
      final playability =
      playerResponse['playabilityStatus'] as Map<String, dynamic>?;
      if (playability != null) {
        final status = playability['status'] as String? ?? '';
        result['is_playable'] = (status == 'OK');

        // Проверка возрастных ограничений
        final reason = playability['reason'] as String? ?? '';
        if (reason.toLowerCase().contains('age') ||
            reason.toLowerCase().contains('sign in to confirm')) {
          result['is_age_restricted'] = true;
          result['is_playable'] = false;
        }

        // Проверка на «content warning»
        if (playability.containsKey('contentCheckOk')) {
          result['is_age_restricted'] = true;
        }
      }

      // Проверка встраиваемости
      final microformat = playerResponse['microformat'] as Map<String, dynamic>?;
      final playerMicroformat =
      microformat?['playerMicroformatRenderer'] as Map<String, dynamic>?;
      if (playerMicroformat != null) {
        final isFamilySafe = playerMicroformat['isFamilySafe'] as bool?;
        if (isFamilySafe == false) {
          result['is_age_restricted'] = true;
        }

        final isUnlisted = playerMicroformat['isUnlisted'] as bool?;
        if (isUnlisted == true) {
          // Unlisted видео допустимы, но помечаем
        }

        // Региональные ограничения
        final availableCountries =
        playerMicroformat['availableCountries'] as List<dynamic>?;
        if (availableCountries != null && availableCountries.length < 50) {
          result['is_region_restricted'] = true;
        }
      }

      // Embed check
      final videoDetails =
      playerResponse['videoDetails'] as Map<String, dynamic>?;
      if (videoDetails != null) {
        final allowRatings = videoDetails['allowRatings'] as bool?;
        // isLiveContent
        final isLive = videoDetails['isLiveContent'] as bool? ?? false;
        if (isLive) {
          result['is_playable'] = false; // Живые трансляции пропускаем
        }
      }

      // playabilityStatus.playableInEmbed
      if (playability != null) {
        final playableInEmbed =
            playability['playableInEmbed'] as bool? ?? true;
        result['is_embeddable'] = playableInEmbed;
      }
    } catch (e) {
      debugPrint('[Catalog] Restriction check error for $videoId: $e');
    }

    return result;
  }

  /// Получить ytInitialPlayerResponse со страницы видео
  Future<Map<String, dynamic>?> _fetchPlayerResponse(String videoId) async {
    final url =
        'https://www.youtube.com/watch?v=$videoId&bpctr=9999999999&hl=en';

    final response = await _httpClient.get(Uri.parse(url), headers: {
      'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'en-US,en;q=0.9',
    });

    if (response.statusCode != 200) return null;

    return _extractPlayerResponse(response.body);
  }

  /// Извлечь JSON из HTML страницы
  Map<String, dynamic>? _extractPlayerResponse(String html) {
    final patterns = [
      RegExp(
          r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\})\s*;\s*var\s',
          dotAll: true),
      RegExp(
          r'var\s+ytInitialPlayerResponse\s*=\s*(\{.+?\})\s*;',
          dotAll: true),
      RegExp(r'ytInitialPlayerResponse\s*=\s*(\{.+?\})\s*;', dotAll: true),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(html);
      if (match != null) {
        try {
          final jsonStr = match.group(1)!;
          final parsed = _extractJsonObject(jsonStr);
          if (parsed != null) return parsed;
        } catch (_) {}
      }
    }
    return null;
  }

  Map<String, dynamic>? _extractJsonObject(String str) {
    int braceCount = 0;
    int? start;

    for (int i = 0; i < str.length; i++) {
      if (str[i] == '{') {
        start ??= i;
        braceCount++;
      } else if (str[i] == '}') {
        braceCount--;
        if (braceCount == 0 && start != null) {
          try {
            return jsonDecode(str.substring(start, i + 1))
            as Map<String, dynamic>;
          } catch (_) {
            return null;
          }
        }
      }
    }
    return null;
  }

  /// Получить MAP {languageCode: captionUrl} из watch page
  Future<Map<String, String>> _fetchCaptionData(String videoId) async {
    final captions = <String, String>{};

    try {
      final playerResponse = await _fetchPlayerResponse(videoId);
      if (playerResponse == null) return captions;

      final captionsObj =
      playerResponse['captions'] as Map<String, dynamic>?;
      if (captionsObj == null) return captions;

      final renderer = captionsObj['playerCaptionsTracklistRenderer']
      as Map<String, dynamic>?;
      if (renderer == null) return captions;

      final tracks = renderer['captionTracks'] as List<dynamic>?;
      if (tracks == null) return captions;

      for (final track in tracks) {
        final langCode = track['languageCode'] as String? ?? '';
        final baseUrl = track['baseUrl'] as String? ?? '';
        if (langCode.isNotEmpty && baseUrl.isNotEmpty) {
          captions[langCode] = baseUrl;
        }
      }
    } catch (e) {
      debugPrint('[Catalog] Caption data fetch error for $videoId: $e');
    }

    return captions;
  }

  /// Скачать и распарсить субтитры по URL трека
  Future<List<Map<String, dynamic>>> _downloadAndParseSubtitles({
    required String captionUrl,
    required String dbVideoId,
    required String language,
  }) async {
    // Запрашиваем JSON3 формат
    var url = captionUrl;
    if (!url.contains('fmt=')) {
      url += '&fmt=json3';
    } else {
      url = url.replaceAll(RegExp(r'fmt=[^&]*'), 'fmt=json3');
    }

    final response = await _httpClient.get(Uri.parse(url), headers: {
      'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    });

    if (response.statusCode != 200 || response.body.isEmpty) {
      // Fallback: XML
      final xmlUrl = captionUrl.contains('fmt=')
          ? captionUrl.replaceAll(RegExp(r'fmt=[^&]*'), 'fmt=srv3')
          : '$captionUrl&fmt=srv3';

      final xmlResponse =
      await _httpClient.get(Uri.parse(xmlUrl), headers: {
        'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      });

      if (xmlResponse.statusCode == 200 && xmlResponse.body.isNotEmpty) {
        return _parseSubtitleBody(xmlResponse.body, dbVideoId, language);
      }
      return [];
    }

    return _parseSubtitleBody(response.body, dbVideoId, language);
  }

  /// Универсальный парсер тела субтитров
  List<Map<String, dynamic>> _parseSubtitleBody(
      String body,
      String dbVideoId,
      String language,
      ) {
    // JSON3
    if (body.trimLeft().startsWith('{') || body.trimLeft().startsWith('[')) {
      final result = _parseJson3(body, dbVideoId, language);
      if (result.isNotEmpty) return result;
    }

    // XML
    if (body.contains('<text') || body.contains('<?xml')) {
      return _parseXml(body, dbVideoId, language);
    }

    // VTT
    if (body.contains('WEBVTT') || body.contains('-->')) {
      return _parseVtt(body, dbVideoId, language);
    }

    return [];
  }

  List<Map<String, dynamic>> _parseJson3(
      String body, String dbVideoId, String lang) {
    final lines = <Map<String, dynamic>>[];
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final events = json['events'] as List<dynamic>? ?? [];

      int i = 0;
      for (final ev in events) {
        if (ev is! Map) continue;

        final startMs = (ev['tStartMs'] as num?)?.toInt() ?? 0;
        final durMs = (ev['dDurationMs'] as num?)?.toInt() ?? 3000;
        final segs = ev['segs'] as List<dynamic>?;
        if (segs == null) continue;

        final text = segs
            .map((s) => (s is Map ? (s['utf8'] ?? '') : '').toString())
            .join()
            .replaceAll('\n', ' ')
            .trim();
        if (text.isEmpty) continue;

        lines.add({
          'id': '${dbVideoId}_${lang}_$i',
          'video_id': dbVideoId,
          'language': lang,
          'start_ms': startMs,
          'end_ms': startMs + durMs,
          'text': text,
          'sequence_index': i,
        });
        i++;
      }
    } catch (e) {
      debugPrint('[Catalog] JSON3 parse error: $e');
    }
    return lines;
  }

  List<Map<String, dynamic>> _parseXml(
      String body, String dbVideoId, String lang) {
    final lines = <Map<String, dynamic>>[];
    final regex = RegExp(
      r'<text\b[^>]*\bstart="([^"]*)"[^>]*\bdur="([^"]*)"[^>]*>(.*?)</text>',
      dotAll: true,
    );

    int i = 0;
    for (final m in regex.allMatches(body)) {
      final start = double.tryParse(m.group(1) ?? '') ?? 0;
      final dur = double.tryParse(m.group(2) ?? '2') ?? 2;
      final text = _decodeXml(m.group(3) ?? '').trim();
      if (text.isEmpty) continue;

      lines.add({
        'id': '${dbVideoId}_${lang}_$i',
        'video_id': dbVideoId,
        'language': lang,
        'start_ms': (start * 1000).round(),
        'end_ms': ((start + dur) * 1000).round(),
        'text': text,
        'sequence_index': i,
      });
      i++;
    }
    return lines;
  }

  List<Map<String, dynamic>> _parseVtt(
      String body, String dbVideoId, String lang) {
    final lines = <Map<String, dynamic>>[];
    final raw = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final all = raw.split('\n');

    int i = 0;
    int idx = 0;
    if (all.isNotEmpty && all[0].contains('WEBVTT')) idx = 1;

    while (idx < all.length) {
      while (idx < all.length && all[idx].trim().isEmpty) idx++;
      if (idx >= all.length) break;

      if (RegExp(r'^\d+$').hasMatch(all[idx].trim())) {
        idx++;
        if (idx >= all.length) break;
      }

      final timingLine = all[idx].trim();
      if (!timingLine.contains('-->')) {
        idx++;
        continue;
      }

      final parts = timingLine.split('-->');
      if (parts.length < 2) {
        idx++;
        continue;
      }

      final startMs = _vttTimeToMs(parts[0].trim());
      final endMs =
      _vttTimeToMs(parts[1].trim().split(RegExp(r'\s+')).first);
      idx++;

      final buffer = <String>[];
      while (idx < all.length && all[idx].trim().isNotEmpty) {
        buffer.add(all[idx].trim());
        idx++;
      }

      final text = buffer.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      if (text.isEmpty) continue;

      lines.add({
        'id': '${dbVideoId}_${lang}_$i',
        'video_id': dbVideoId,
        'language': lang,
        'start_ms': startMs,
        'end_ms': endMs > startMs ? endMs : (startMs + 2000),
        'text': text,
        'sequence_index': i,
      });
      i++;
    }
    return lines;
  }

  int _vttTimeToMs(String s) {
    final parts = s.trim().split(':');
    double seconds = 0;
    if (parts.length == 3) {
      seconds = (int.tryParse(parts[0]) ?? 0) * 3600 +
          (int.tryParse(parts[1]) ?? 0) * 60 +
          (double.tryParse(parts[2]) ?? 0);
    } else if (parts.length == 2) {
      seconds = (int.tryParse(parts[0]) ?? 0) * 60 +
          (double.tryParse(parts[1]) ?? 0);
    } else {
      seconds = double.tryParse(parts[0]) ?? 0;
    }
    return (seconds * 1000).round();
  }

  String _decodeXml(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'<[^>]+>'), '');
  }

  // ============================================================
  // МЕТОДЫ РАБОТЫ С SUPABASE
  // ============================================================

  /// Upsert видео в базу, возвращает UUID записи
  Future<String> _upsertVideo({
    required Video video,
    required String searchQuery,
    required Map<String, bool> restrictions,
    required List<String> captionLanguages,
    required String status,
    String? error,
  }) async {
    final data = {
      'youtube_id': video.id.value,
      'title': video.title,
      'author': video.author,
      'channel_id': video.channelId.value,
      'description': video.description.length > 5000
          ? video.description.substring(0, 5000)
          : video.description,
      'duration_ms': video.duration?.inMilliseconds,
      'thumbnail_url': video.thumbnails.highResUrl,
      'keywords': video.keywords.take(20).toList(),
      'has_captions': captionLanguages.isNotEmpty,
      'caption_languages': captionLanguages,
      'is_embeddable': restrictions['is_embeddable'] ?? true,
      'is_age_restricted': restrictions['is_age_restricted'] ?? false,
      'is_region_restricted':
      restrictions['is_region_restricted'] ?? false,
      'is_playable': restrictions['is_playable'] ?? true,
      'search_query': searchQuery,
      'status': status,
      'error_message': error,
    };

    final result = await _supabase
        .from('videos')
        .upsert(data, onConflict: 'youtube_id')
        .select('id')
        .single();

    return result['id'] as String;
  }

  /// Пакетное сохранение строк субтитров
  Future<void> _saveSubtitleLines(List<Map<String, dynamic>> lines) async {
    if (lines.isEmpty) return;

    // Supabase имеет ограничение на размер запроса.
    // Разбиваем на батчи по 500 строк.
    const batchSize = 500;

    for (int i = 0; i < lines.length; i += batchSize) {
      final batch = lines.skip(i).take(batchSize).toList();
      await _supabase
          .from('subtitle_lines')
          .upsert(batch, onConflict: 'id');
    }
  }

  /// Создать задачу поиска
  Future<String> _createSearchTask(
      String query, String language, int maxResults) async {
    final result = await _supabase.from('search_tasks').insert({
      'query': query,
      'language': language,
      'max_results': maxResults,
      'status': 'pending',
    }).select('id').single();

    return result['id'] as String;
  }

  /// Обновить статус задачи
  Future<void> _updateSearchTaskStatus(String taskId, String status,
      {String? error}) async {
    final update = <String, dynamic>{'status': status};
    if (error != null) update['error_message'] = error;
    if (status == 'done' || status == 'failed') {
      update['completed_at'] = DateTime.now().toUtc().toIso8601String();
    }
    await _supabase.from('search_tasks').update(update).eq('id', taskId);
  }

  /// Обновить поле задачи
  Future<void> _updateSearchTaskField(
      String taskId, String field, dynamic value) async {
    await _supabase
        .from('search_tasks')
        .update({field: value}).eq('id', taskId);
  }
}